# Acme Shop API

A runnable server generated from a nine-type GraphQL schema. Everything under
`lib/` except `catalogue.dart` and the two resolver bodies was written by
`graphql_openapi_codegen`.

```bash
dart pub get
dart run graphql_openapi_codegen     # writes lib/models, lib/rest, lib/routes, assets
dart run --enable-asserts bin/server.dart
```

| | |
| --- | --- |
| GraphQL Playground | <http://localhost:8080/docs/graphql> |
| Swagger UI | <http://localhost:8080/docs/rest> |
| the API | `POST /graphql`, `POST /rest/query/product` |

`--enable-asserts` is what turns the validators on; see the last section.

## The schema

`lib/schema.graphql` is the whole input. A type, an enum, two inputs, a custom
directive, a query and a mutation:

```graphql
"""Rejects a SKU that is not three letters followed by four digits."""
directive @_skuFormat on INPUT_FIELD_DEFINITION

"""A product on sale."""
type Product {
  """The stock keeping unit. Unique across the catalogue."""
  sku: String!
  label: String!
  priceCents: Int!
  availability: Availability!
}

input ProductInput {
  sku: String! @_skuFormat
  label: String!
  priceCents: Int!
  availability: Availability = IN_STOCK
}

type Query {
  """Reads one product, or null when the catalogue does not hold it."""
  product(query: ProductQuery!): Product
}

type Mutation {
  upsertProduct(input: ProductInput!): Product!
}
```

## What the run produces

```
lib/models/product_type.dart              the model, documented from the SDL
lib/models/product_query.dart             the inputs, asserting @_skuFormat
lib/models/product_input.dart
lib/models/enums.dart                     Availability
lib/graphql/fields/query_fields.dart      the field lists the schema is built from
lib/graphql/fields/mutation_fields.dart
lib/graphql/graphql_resolvers_registry.dart
lib/resolvers/query_product_resolver.dart       ← filled in by hand
lib/resolvers/mutation_upsert_product_resolver.dart  ← filled in by hand
lib/resolvers/register_all.dart
lib/rest/endpoints/query_product_endpoint.dart
lib/rest/endpoints/mutation_upsert_product_endpoint.dart
lib/rest/rest_routes.dart                 registerRestRoutes(Router)
lib/routes/graphql_doc_route.dart         the Playground page
lib/routes/rest_doc_route.dart            the Swagger UI page
lib/routes/doc_routes.dart                registerDocRoutes(Router)
lib/validators/valid_sku_format.dart      ← filled in by hand
assets/openapi.yaml
```

Four files carry hand-written logic. The rest is regenerated, and the two
resolvers and the validator are created once and never touched again.

## What `bin/server.dart` has to do

Mount two generated functions, and answer on `/graphql` yourself with
[graphql_server3](https://pub.dev/packages/graphql_server3), the runtime that
executes a document against the schema:

```dart
final schema = GraphQLSchema(
  queryType: objectType('Query', fields: queryFields),
  mutationType: objectType('Mutation', fields: mutationFields),
);

registerRestRoutes(router);   // POST /rest/query/product, /rest/mutation/upsertProduct
registerDocRoutes(router);    // GET /docs/graphql, /docs/rest
```

Serving `assets/openapi.yaml` is also yours, because where a file is served from
is a deployment question. `routes.openapi` in `pubspec.yaml` is the URL the
generated Swagger page fetches; this example answers it from disk.

## Try it

```bash
curl -s localhost:8080/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ product(query: {sku: \"ACM1001\"}) { sku label priceCents } }"}'
```

```json
{"data":{"product":{"sku":"ACM1001","label":"Anvil, 200 kg","priceCents":24900}}}
```

The same resolver through the REST door, which is the endpoint Swagger UI calls:

```bash
curl -s localhost:8080/rest/query/product -H 'Content-Type: application/json' \
  -d '{"query":{"sku":"ACM1001"}}'
```

```json
{"data":{"sku":"ACM1001","label":"Anvil, 200 kg","priceCents":24900,"availability":"IN_STOCK"}}
```

## The configuration this example uses

```yaml
graphql_openapi_codegen:
  api_name: Acme Shop
  api_servers:
    - https://api.acme.example
  copy_with: false
  routes:
    graphql: /graphql
    rest: /rest
    graphql_doc: /docs/graphql
    rest_doc: /docs/rest
    openapi: /static/openapi.yaml
```

`routes.rest` is why the endpoints answer on `/rest/query/product` and why
`assets/openapi.yaml` declares `/rest/query/product` rather than
`/query/product`. `copy_with: false` keeps `copy_with_extension` out of the
dependency list entirely.

Nothing under `output:` is set, so the layout is the default one.

## A word about the validators

`@_skuFormat` becomes an `assert` in the input's constructor, which means it
runs in development and is **compiled out of a release build**. That is the
right default for a check that restates what the schema already says, and the
wrong one for rejecting hostile input. Reject that in the resolver.

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/rest/query/product \
  -H 'Content-Type: application/json' -d '{"query":{"sku":"nope"}}'
```

`500` with `--enable-asserts`, `200` without.
