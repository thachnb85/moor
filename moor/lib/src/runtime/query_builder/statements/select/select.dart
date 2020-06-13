part of '../../query_builder.dart';

/// Signature of a function that generates an [OrderingTerm] when provided with
/// a table.
typedef OrderClauseGenerator<T> = OrderingTerm Function(T tbl);

/// A select statement that doesn't use joins
class SimpleSelectStatement<T extends Table, D extends DataClass>
    extends Query<T, D>
    with SingleTableQueryMixin<T, D>, LimitContainerMixin<T, D>, Selectable<D> {
  /// Whether duplicate rows should be eliminated from the result (this is a
  /// `SELECT DISTINCT` statement in sql). Defaults to false.
  final bool distinct;

  /// Used internally by moor, users will want to call [QueryEngine.select]
  /// instead.
  SimpleSelectStatement(QueryEngine database, TableInfo<T, D> table,
      {this.distinct = false})
      : super(database, table);

  /// The tables this select statement reads from.
  @visibleForOverriding
  Set<TableInfo> get watchedTables => {table};

  @override
  void writeStartPart(GenerationContext ctx) {
    ctx.buffer
      ..write(_beginOfSelect(distinct))
      ..write(' * FROM ${table.tableWithAlias}');
  }

  @override
  Future<List<D>> get() async {
    final ctx = constructQuery();
    return _getWithQuery(ctx);
  }

  Future<List<D>> _getWithQuery(GenerationContext ctx) async {
    final results = await ctx.executor.doWhenOpened((e) async {
      return await e.runSelect(ctx.sql, ctx.boundVariables);
    });
    return results.map(table.map).toList();
  }

  /// Creates a select statement that operates on more than one table by
  /// applying the given joins.
  ///
  /// Example from the todolist example which will load the category for each
  /// item:
  /// ```
  /// final results = await select(todos).join([
  ///   leftOuterJoin(categories, categories.id.equalsExp(todos.category))
  /// ]).get();
  ///
  /// return results.map((row) {
  ///   final entry = row.readTable(todos);
  ///   final category = row.readTable(categories);
  ///   return EntryWithCategory(entry, category);
  /// }).toList();
  /// ```
  ///
  /// See also:
  ///  - https://moor.simonbinder.eu/docs/advanced-features/joins/#joins
  ///  - [innerJoin], [leftOuterJoin] and [crossJoin], which can be used to
  ///  construct a [Join].
  ///  - [DatabaseConnectionUser.alias], which can be used to build statements
  ///  that refer to the same table multiple times.
  JoinedSelectStatement join(List<Join> joins) {
    final statement = JoinedSelectStatement(database, table, joins, distinct);

    if (whereExpr != null) {
      statement.where(whereExpr.predicate);
    }
    if (orderByExpr != null) {
      statement.orderBy(orderByExpr.terms);
    }
    if (limitExpr != null) {
      statement.limitExpr = limitExpr;
    }

    return statement;
  }

  /// {@macro moor_select_addColumns}
  JoinedSelectStatement addColumns(List<Expression> expressions) {
    return join(const [])..addColumns(expressions);
  }

  /// Orders the result by the given clauses. The clauses coming first in the
  /// list have a higher priority, the later clauses are only considered if the
  /// first clause considers two rows to be equal.
  ///
  /// Example that first displays the users who are awesome and sorts users by
  /// their id as a secondary criterion:
  /// ```
  /// (db.select(db.users)
  ///    ..orderBy([
  ///      (u) =>
  ///        OrderingTerm(expression: u.isAwesome, mode: OrderingMode.desc),
  ///      (u) => OrderingTerm(expression: u.id)
  ///    ]))
  ///  .get()
  /// ```
  void orderBy(List<OrderClauseGenerator<T>> clauses) {
    orderByExpr = OrderBy(clauses.map((t) => t(table.asDslTable)).toList());
  }

  @override
  Stream<List<D>> watch() {
    final query = constructQuery();
    final fetcher = QueryStreamFetcher<List<D>>(
      readsFrom: TableUpdateQuery.onAllTables(watchedTables),
      fetchData: () => _getWithQuery(query),
      key: StreamKey(query.sql, query.boundVariables, D),
    );

    return database.createStream(fetcher);
  }
}

String _beginOfSelect(bool distinct) {
  return distinct ? 'SELECT DISTINCT' : 'SELECT';
}

/// A result row in a [JoinedSelectStatement] that can parse the result of
/// multiple entities.
class TypedResult {
  /// Creates the result from the parsed table data.
  TypedResult(
    this._parsedData,
    this.rawData, [
    this._parsedExpressions = const {},
  ]);

  final Map<TableInfo, dynamic> _parsedData;
  final Map<Expression, dynamic> _parsedExpressions;

  /// The raw data contained in this row.
  final QueryRow rawData;

  /// Reads all data that belongs to the given [table] from this row.
  D readTable<T extends Table, D extends DataClass>(TableInfo<T, D> table) {
    if (!_parsedData.containsKey(table)) {
      throw NotInResultSetError._(
        'This result set does not contain a full row for ${table.tableName}. \n'
        "Please make sure that you're including the table in the select() "
        'function or a join clause.',
      );
    }

    return _parsedData[table] as D;
  }

  /// Reads a single column from an [expr]. The expression must have been added
  /// as a column, for instance via [JoinedSelectStatement.addColumns].
  ///
  /// To access the underlying columns directly, use
  D read<D>(Expression<D> expr) {
    if (!_parsedExpressions.containsKey(expr)) {
      throw NotInResultSetError._(
        'The requested expression is not included in this result set, so it '
        "can't be returned here. \n"
        'Please make sure that the expression was added via addColumns(). '
        "If you're receiving this error after a hot-reload, try extracting the"
        'affected expression to a local variable.',
      );
    }

    return _parsedExpressions[expr] as D;
  }
}

/// This error is thrown by [TypedResult.readTable] or [TypedResult.read] when
/// attempting to read a column or table that is not present in the result.
class NotInResultSetError extends Error {
  final String _message;

  NotInResultSetError._(this._message);

  @override
  String toString() => _message;
}
