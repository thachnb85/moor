part of '../query_builder.dart';

/// Represents an insert statement
class InsertStatement<T extends Table, D extends DataClass> {
  /// The database to use then executing this statement
  @protected
  final QueryEngine database;

  /// The table we're inserting into
  @protected
  final TableInfo<T, D> table;

  /// Constructs an insert statement from the database and the table. Used
  /// internally by moor.
  InsertStatement(this.database, this.table);

  /// Inserts a row constructed from the fields in [entity].
  ///
  /// All fields in the entity that don't have a default value or auto-increment
  /// must be set and non-null. Otherwise, an [InvalidDataException] will be
  /// thrown.
  ///
  /// By default, an exception will be thrown if another row with the same
  /// primary key already exists. This behavior can be overridden with [mode],
  /// for instance by using [InsertMode.replace] or [InsertMode.insertOrIgnore].
  ///
  /// To apply a partial or custom update in case of a conflict, you can also
  /// use an [upsert clause](https://sqlite.org/lang_UPSERT.html) by using
  /// [onConflict].
  /// For instance, you could increase a counter whenever a conflict occurs:
  ///
  /// ```dart
  /// class Words extends Table {
  ///   TextColumn get word => text()();
  ///   IntColumn get occurrences => integer()();
  /// }
  ///
  /// Future<void> addWord(String word) async {
  ///   await into(words).insert(
  ///     WordsCompanion.insert(word: word, occurrences: 1),
  ///     onConflict: DoUpdate((old) => WordsCompanion.custom(
  ///       occurrences: old.occurrences + Constant(1),
  ///     )),
  ///   );
  /// }
  /// ```
  ///
  /// When calling `addWord` with a word not yet saved, the regular insert will
  /// write it with one occurrence. If it already exists however, the insert
  /// behaves like an update incrementing occurrences by one.
  /// Be aware that upsert clauses and [onConflict] are not available on older
  /// sqlite versions.
  ///
  /// If the table contains an auto-increment column, the generated value will
  /// be returned. If there is no auto-increment column, you can't rely on the
  /// return value, but the future will complete with an error if the insert
  /// fails.
  Future<int> insert(
    Insertable<D> entity, {
    InsertMode mode,
    DoUpdate<T, D> onConflict,
  }) async {
    final ctx = createContext(entity, mode ?? InsertMode.insert,
        onConflict: onConflict);

    return await database.doWhenOpened((e) async {
      final id = await e.runInsert(ctx.sql, ctx.boundVariables);
      database
          .notifyUpdates({TableUpdate.onTable(table, kind: UpdateKind.insert)});
      return id;
    });
  }

  /// Attempts to [insert] [entity] into the database. If the insert would
  /// violate a primary key or uniqueness constraint, updates the columns that
  /// are present on [entity].
  ///
  /// Note that this is subtly different from [InsertMode.replace]! When using
  /// [InsertMode.replace], the old row will be deleted and replaced with the
  /// new row. With [insertOnConflictUpdate], columns from the old row that are
  /// not present on [entity] are unchanged, and no row will be deleted.
  ///
  /// Be aware that [insertOnConflictUpdate] uses an upsert clause, which is not
  /// available on older sqlite implementations.
  Future<int> insertOnConflictUpdate(Insertable<D> entity) {
    return insert(entity, onConflict: DoUpdate((_) => entity));
  }

  /// Creates a [GenerationContext] which contains the sql necessary to run an
  /// insert statement fro the [entry] with the [mode].
  ///
  /// This method is used internally by moor. Consider using [insert] instead.
  GenerationContext createContext(Insertable<D> entry, InsertMode mode,
      {DoUpdate<T, D> onConflict}) {
    _validateIntegrity(entry);

    final rawValues = entry.toColumns(true);

    // apply default values for columns that have one
    final map = <String, Expression>{};
    for (final column in table.$columns) {
      final columnName = column.$name;

      if (rawValues.containsKey(columnName)) {
        map[columnName] = rawValues[columnName];
      } else {
        if (column.clientDefault != null) {
          map[columnName] = column._evaluateClientDefault();
        }
      }

      // column not set, and doesn't have a client default. So just don't
      // include this column
    }

    final ctx = GenerationContext.fromDb(database);
    ctx.buffer
      ..write(_insertKeywords[mode])
      ..write(' INTO ')
      ..write(table.$tableName)
      ..write(' ');

    if (map.isEmpty) {
      ctx.buffer.write('DEFAULT VALUES');
    } else {
      final columns = map.keys.map(escapeIfNeeded);

      ctx.buffer
        ..write('(')
        ..write(columns.join(', '))
        ..write(') ')
        ..write('VALUES (');

      var first = true;
      for (final variable in map.values) {
        if (!first) {
          ctx.buffer.write(', ');
        }
        first = false;

        variable.writeInto(ctx);
      }

      ctx.buffer.write(')');
    }

    if (onConflict != null) {
      final upsertInsertable = onConflict._createInsertable(table.asDslTable);

      if (!identical(entry, upsertInsertable)) {
        // We run a ON CONFLICT DO UPDATE, so make sure upsertInsertable is
        // valid for updates.
        // the identical check is a performance optimization - for the most
        // common call (insertOnConflictUpdate) we don't have to check twice.
        table
            .validateIntegrity(upsertInsertable, isInserting: false)
            .throwIfInvalid(upsertInsertable);
      }

      final updateSet = upsertInsertable.toColumns(true);

      ctx.buffer.write(' ON CONFLICT(');

      final conflictTarget = onConflict.target ?? table.$primaryKey.toList();
      var first = true;
      for (final target in conflictTarget) {
        if (!first) ctx.buffer.write(', ');

        target.writeInto(ctx);
        first = false;
      }

      ctx.buffer.write(') DO UPDATE SET ');

      first = true;
      for (final update in updateSet.entries) {
        final column = escapeIfNeeded(update.key);

        if (!first) ctx.buffer.write(', ');
        ctx.buffer.write('$column = ');
        update.value.writeInto(ctx);

        first = false;
      }
    }

    return ctx;
  }

  void _validateIntegrity(Insertable<D> d) {
    if (d == null) {
      throw InvalidDataException(
          'Cannot write null row into ${table.$tableName}');
    }

    table.validateIntegrity(d, isInserting: true).throwIfInvalid(d);
  }
}

/// Enumeration of different insert behaviors. See the documentation on the
/// individual fields for details.
enum InsertMode {
  /// A regular `INSERT INTO` statement. When a row with the same primary or
  /// unique key already exists, the insert statement will fail and an exception
  /// will be thrown. If the exception is caught, previous statements made in
  /// the same transaction will NOT be reverted.
  insert,

  /// Identical to [InsertMode.insertOrReplace], included for the sake of
  /// completeness.
  replace,

  /// Like [insert], but if a row with the same primary or unique key already
  /// exists, it will be deleted and re-created with the row being inserted.
  insertOrReplace,

  /// Similar to [InsertMode.insertOrAbort], but it will revert the surrounding
  /// transaction if a constraint is violated, even if the thrown exception is
  /// caught.
  insertOrRollback,

  /// Identical to [insert], included for the sake of completeness.
  insertOrAbort,

  /// Like [insert], but if multiple values are inserted with the same insert
  /// statement and one of them fails, the others will still be completed.
  insertOrFail,

  /// Like [insert], but failures will be ignored.
  insertOrIgnore,
}

const _insertKeywords = <InsertMode, String>{
  InsertMode.insert: 'INSERT',
  InsertMode.replace: 'REPLACE',
  InsertMode.insertOrReplace: 'INSERT OR REPLACE',
  InsertMode.insertOrRollback: 'INSERT OR ROLLBACK',
  InsertMode.insertOrAbort: 'INSERT OR ABORT',
  InsertMode.insertOrFail: 'INSERT OR FAIL',
  InsertMode.insertOrIgnore: 'INSERT OR IGNORE',
};

/// A [DoUpdate] upsert clause can be used to insert or update a custom
/// companion when the underlying companion already exists.
///
/// For an example, see [InsertStatement.insert].
class DoUpdate<T extends Table, D extends DataClass> {
  final Insertable<D> Function(T old) _creator;

  /// An optional list of columns to serve as an "conflict target", which
  /// specifies the uniqueness constraint that will trigger the upsert.
  ///
  /// By default, the primary key of the table will be used.
  final List<Column> /*?*/ target;

  /// For an example, see [InsertStatement.insert].
  DoUpdate(Insertable<D> Function(T old) update, {this.target})
      : _creator = update;

  Insertable<D> _createInsertable(T table) {
    return _creator(table);
  }
}
