import 'package:built_value/built_value.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.drift.dart';
part 'database.g.dart';

abstract class Foo implements Built<Foo, FooBuilder> {
  User get moorField;

  Foo._();

  factory Foo([void Function(FooBuilder) updates]) = _$Foo;
}

@DriftDatabase(include: {'tables.drift'})
class Database extends _$Database {
  Database() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
