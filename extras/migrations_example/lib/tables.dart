import 'package:drift/drift.dart';

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();

  // added in schema version 2, got a default in version 4
  TextColumn get name => text().withDefault(const Constant('name'))();
}
