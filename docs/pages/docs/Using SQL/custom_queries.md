---
data:
  title: "Custom queries"
  weight: 10
  description: Let drift generate Dart from your SQL statements
aliases:
  - /queries/custom
template: layouts/docs/single
---

Although drift includes a fluent api that can be used to model most statements, advanced
features like `WITH` clauses or subqueries aren't supported yet. You can
use these features with custom statements. You don't have to miss out on other benefits
drift brings, though: Drift helps you parse the result rows and custom queries also
support auto-updating streams.

## Statements with a generated api

You can instruct drift to automatically generate a typesafe
API for your select, update and delete statements. Of course, you can still write custom
 sql manually. See the sections below for details.

To use this feature, all you need to is define your queries in your `DriftDatabase` annotation:
```dart
@DriftDatabase(
  tables: [Todos, Categories],
  queries: {
    'categoriesWithCount':
        'SELECT *, (SELECT COUNT(*) FROM todos WHERE category = c.id) AS "amount" FROM categories c;'
  },
)
class MyDatabase extends _$MyDatabase {
  // rest of class stays the same
}
```
After running the build step again, drift will have written the `CategoriesWithCountResult` class for you -
it will hold the result of your query. Also, the `_$MyDatabase` class from which you inherit will have the
methods `categoriesWithCount` (which runs the query once) and `watchCategoriesWithCount` (which returns
an auto-updating stream).

Queries can have parameters in them by using the `?` or `:name` syntax. When your queries contains parameters,
drift will figure out an appropriate type for them and include them in the generated methods. For instance,
`'categoryById': 'SELECT * FROM categories WHERE id = :id'` will generate the method `categoryById(int id)`.

{% block "blocks/alert" title="On table names" color="info" %}
To use this feature, it's helpful to know how Dart tables are named in sql. For tables that don't
override `tableName`, the name in sql will be the `snake_case` of the class name. So a Dart table
called `Categories` will be named `categories`, a table called `UserAddressInformation` would be
called `user_address_information`. The same rule applies to column getters without an explicit name.
Tables and columns declared in [Drift files]({{ "moor_files.md" | pageUrl }}) will always have the
name you specified.
{% endblock %}

You can also use `UPDATE` or `DELETE` statements here. Of course, this feature is also available for 
[daos]({{ "../Advanced Features/daos.md" | pageUrl }}),
and it perfectly integrates with auto-updating streams by analyzing what tables you're reading from or
writing to.

## Custom select statements
If you don't want to use the statements with an generated api, you can
still send custom queries by calling `customSelect` for a one-time query or
`customSelectStream` for a query stream that automatically emits a new set of items when
the underlying data changes. Using the todo example introduced in the 
[getting started guide]({{ "../Getting started/index.md" | pageUrl }}), we can
write this query which will load the amount of todo entries in each category:
```dart
class CategoryWithCount {
  final Category category;
  final int count; // amount of entries in this category

  CategoryWithCount(this.category, this.count);
}

// then, in the database class:
Stream<List<CategoryWithCount>> categoriesWithCount() {
    // select all categories and load how many associated entries there are for
    // each category
    return customSelect(
      'SELECT *, (SELECT COUNT(*) FROM todos WHERE category = c.id) AS "amount" FROM categories c;',
      readsFrom: {todos, categories}, // used for the stream: the stream will update when either table changes
      ).watch().map((rows) {
        // we get list of rows here. We just have to turn the raw data from the row into a
        // CategoryWithCount. As we defined the Category table earlier, drift knows how to parse
        // a category. The only thing left to do manually is extracting the amount
        return rows
          .map((row) => CategoryWithCount(Category.fromData(row.data, this), row.readInt('amount')))
          .toList();
    });
  }
```
For custom selects, you should use the `readsFrom` parameter to specify from which tables the query is
reading. When using a `Stream`, drift will be able to know after which updates the stream should emit
items. 

You can also bind SQL variables by using question-mark placeholders and the `variables` parameter:

```dart
Stream<int> amountOfTodosInCategory(int id) {
  return customSelect(
    'SELECT COUNT(*) AS c FROM todos WHERE category = ?',
    variables: [Variable.withInt(id)],
    readsFrom: {todos},
  ).map((row) => row.readInt('c')).watch();
}
```

Of course, you can also use indexed variables (like `?12`) - for more information on them, see 
[the sqlite3 documentation](https://sqlite.org/lang_expr.html#varparam).

## Custom update statements
For update and delete statements, you can use `customUpdate`. Just like `customSelect`, that method
also takes a sql statement and optional variables. You can also tell drift which tables will be
affected by your query using the optional `updates` parameter. That will help with other select
streams, which will then update automatically.
