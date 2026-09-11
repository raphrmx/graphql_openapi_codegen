# Example

A package that generates a small shop API from a schema.

## `pubspec.yaml`

```yaml
name: acme_shop_api

environment:
  sdk: ^3.8.0

dependencies:
  graphql_schema3: ^3.2.1
  json_annotation: ^4.12.0
  shelf: ^1.4.2
  shelf_router: ^1.1.4

dev_dependencies:
  build_runner: ^2.16.1
  graphql_generator3: ^3.2.1
  graphql_openapi_codegen: ^1.0.0
  json_serializable: ^6.14.1

graphql_openapi_codegen:
  copy_with: false
  api_name: Acme Shop
  api_servers:
    - https://api.acme.example
  doc_routes:
    graphql: /docs/playground
    rest: /docs/swagger
```

## `lib/schema.graphql`

```graphql
"""A product on sale."""
type Product {
  """The stock keeping unit."""
  sku: String!
  label: String!
  priceCents: Int!
}

enum Availability {
  IN_STOCK
  OUT_OF_STOCK
}

input ProductQuery {
  sku: String!
  includeArchived: Boolean = null
}

type Query {
  product(query: ProductQuery!): Product
}
```

## Run it

```bash
dart run graphql_openapi_codegen
```

## What comes out

```
lib/models/product_type.dart          the model, with @graphQLClass and @JsonSerializable
lib/models/product_query.dart         the input
lib/models/enums.dart                 Availability
lib/graphql/fields/query_fields.dart  the Query field list
lib/graphql/graphql_resolvers_registry.dart
lib/resolvers/query_product_resolver.dart   a stub to fill in, never overwritten
lib/resolvers/register_all.dart
lib/rest/endpoints/query_product_endpoint.dart
lib/rest/rest_routes.dart             registerRestRoutes(Router)
lib/routes/graphql_doc_route.dart     the Playground page, never overwritten
lib/routes/rest_doc_route.dart        the Swagger UI page, never overwritten
lib/routes/doc_routes.dart            registerDocRoutes(Router)
assets/openapi.yaml
```

Mount what it produced:

```dart
final router = Router();
registerRestRoutes(router);
registerDocRoutes(router);
```

Then fill in `query_product_resolver.dart`, which is the only file you have to
write by hand.
