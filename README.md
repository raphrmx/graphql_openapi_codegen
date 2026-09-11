# GraphQL OpenAPI Codegen

[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/graphql_openapi_codegen/ci.yml?branch=main&label=build)](https://github.com/raphrmx/graphql_openapi_codegen/actions/workflows/ci.yml)
[![Pub Version](https://img.shields.io/pub/v/graphql_openapi_codegen?color=blue)](https://pub.dev/packages/graphql_openapi_codegen)
[![License](https://img.shields.io/badge/Licence-MIT-blue)](LICENSE)

## One schema in, a whole backend out

You have a GraphQL schema and you want a Dart backend from it. Run this once and
you have everything you need to start: the models, the enums, the resolver
stubs, a REST endpoint for every operation, an **OpenAPI 3.1.1 document**, and
two pages your API serves by itself.

Those two pages are what you notice first. A **GraphQL Playground** on
`/graphql-doc`, where anyone can browse your schema and run a real query against
the live API. A **Swagger UI** on `/rest-doc`, over the OpenAPI document the same
run produced. Both written, both mounted, both on whatever path you want.

The resolver bodies are the only code you write.

```graphql
type Query {
  product(query: ProductQuery!): Product
}
```

```
lib/models/product_type.dart               the model, serialisable, documented
lib/resolvers/query_product_resolver.dart  ← the one file you write
lib/rest/endpoints/query_product_endpoint.dart
lib/rest/rest_routes.dart                  registerRestRoutes(Router)
lib/routes/graphql_doc_route.dart          the GraphQL Playground page
lib/routes/rest_doc_route.dart             the Swagger UI page
lib/routes/doc_routes.dart                 registerDocRoutes(Router)
assets/openapi.yaml
```

### Why this one and not the others

Everything else on pub.dev in this space generates **clients**.
[graphql_codegen](https://pub.dev/packages/graphql_codegen),
[artemis](https://pub.dev/packages/artemis) and
[gql_build](https://pub.dev/packages/gql_build) take your schema and your
queries and give you typed request code to call someone else's API.

This one goes the other way: it builds the API. And it is the only one that
hands you an OpenAPI document, so the same schema serves GraphQL clients and
REST clients without you writing the REST layer twice.

Use it if you recognise any of these:

- you maintain a GraphQL server in Dart and write the model classes by hand;
- you need to expose a REST facade over an existing GraphQL API;
- someone asked you for an OpenAPI spec and your source of truth is a `.graphql`
  file;
- your schema moves and the boilerplate never keeps up.

## The stack underneath

This generator writes the code. Four packages run it, all on pub.dev and all
maintained alongside this one:

| | |
| --- | --- |
| [graphql_parser3](https://pub.dev/packages/graphql_parser3) | parses an incoming query into an AST, for the runtime below |
| [graphql_schema3](https://pub.dev/packages/graphql_schema3) | the type system: object, input, union, enum and scalar types |
| [graphql_generator3](https://pub.dev/packages/graphql_generator3) | a `build_runner` builder turning the annotated model classes into those types |
| [graphql_server3](https://pub.dev/packages/graphql_server3) | the runtime that executes a query, a mutation or a subscription against a schema |

They fit together in one direction, and the run walks the whole way:

```
schema.graphql
  → this generator          writes Product, annotated @graphQLClass
  → graphql_generator3      writes productGraphQLType into product_type.g.dart
  → this generator          writes queryFields, which reference that type
  → you                     GraphQLSchema(queryType: objectType('Query', fields: queryFields))
  → graphql_server3         GraphQL(schema).parseAndExecute(query)
```

The schema assembly is the one line you write, and it does not change when the
schema does. See `example/bin/server.dart`.

### graphql_server3 is optional

Nothing forces you to serve GraphQL at all. The generated REST endpoints call
your resolvers directly and never go through the executor, so leaving
`graphql_server3` out costs you the API on `/graphql` and the Playground page,
which `routes.graphql_doc: ''` then turns off. The endpoints, the OpenAPI
document and the Swagger page stand on their own.

## What it writes

| From the SDL | It generates |
| --- | --- |
| `type` | a model class with `@graphQLClass`, `@JsonSerializable()` and optionally `@CopyWith()` |
| `input` | the same, as a GraphQL input class |
| `enum` | one shared `enums.dart`, values keeping their SDL spelling |
| a field with arguments | a resolver stub, created once and never overwritten |
| `Query` / `Mutation` / `Subscription` | the field list, plus one REST endpoint each |
| a custom `@_directive` | a validator stub, created once |
| the whole schema | an OpenAPI 3.1.1 document |
| the whole schema | a GraphQL Playground page and a Swagger UI page, mounted for you |

Generated code comes out lint-clean and formatted.

## Usage

```bash
dart pub add dev:graphql_openapi_codegen
dart run graphql_openapi_codegen
```

It reads the SDL, writes the sources, runs `build_runner` for the `.g.dart`
parts, then `dart format` on what it wrote. It also writes a `build.yaml`
switching on the builders it brings with it, so your `dev_dependencies` need
hold nothing but this package.

`example/` is a server built this way. Four files in it carry hand-written
logic; the rest came out of a schema of seven definitions.

## Configuration

Everything is read from the `graphql_openapi_codegen:` section of your
`pubspec.yaml`, next to the package name the generator has to read anyway.
Every entry is optional; the defaults describe a plain package with no
versioned layout and no class prefix.

```yaml
graphql_openapi_codegen:
  schema: lib/schema.graphql     # the SDL every generator reads
  class_prefix: ''               # replaces the leading `_` of a host type
  copy_with: true                # emit @CopyWith() on the models
  api_name: ''                   # OpenAPI title, defaults to the package name
  api_servers: []                # OpenAPI `servers:` entries
  routes:                        # every entry here is an HTTP path
    graphql: /graphql            # where the GraphQL API answers
    rest: ''                     # prefix the REST endpoints are mounted under
    graphql_doc: /graphql-doc    # the Playground page, '' disables it
    rest_doc: /rest-doc          # the Swagger UI page, '' disables it
    openapi: /openapi.yaml       # where Swagger fetches the document
  output:                        # every entry here is a filesystem path
    models: lib/models             # the model, input and enum classes
    fields: lib/graphql/fields     # the Query/Mutation/Subscription field lists
    validators: lib/validators     # one stub per custom `@_directive`
    resolvers: lib/resolvers       # the resolver stubs and register_all.dart
    graphql: lib/graphql           # graphql_resolvers_registry.dart
    rest: lib/rest                 # rest_routes.dart
    endpoints: lib/rest/endpoints  # one handler per operation
    openapi: assets                # where openapi.yaml is written
    routes: lib/routes             # the two doc pages and doc_routes.dart
```

`routes` holds HTTP paths, `output` holds filesystem paths. They share some
names on purpose: `routes.rest` is the prefix your REST endpoints answer on,
`output.rest` is the directory `rest_routes.dart` lands in. It prefixes the
OpenAPI `paths:` too, so Swagger cannot call a path your server does not serve.

The SDL marks a type belonging to the host with a leading underscore, which is
not a legal start for a public Dart identifier. `class_prefix` is what replaces
it: `_Company` becomes `Company` when empty, `BmcCompany` when set to `Bmc`.

## What it overwrites, and what it does not

Regenerated on every run, so never edit them:

- everything under `output.models` and `output.fields`
- `rest_routes.dart`, `doc_routes.dart`, `register_all.dart`, the
  `validators.dart` facade
- the OpenAPI document

Created once and then yours, so the generator will not touch your work:

- the resolver stubs
- the REST endpoint handlers
- the individual validators
- the two documentation pages
- `graphql_resolvers_registry.dart`
- `build.yaml`

## Requirements

Declare what the generated code **imports**, and nothing else:

```yaml
dependencies:
  graphql_schema3: ^3.2.1        # the type system the models are annotated for
  json_annotation: ^4.12.0       # @JsonSerializable, @JsonKey
  graphql_server3: ^3.2.2        # only to serve GraphQL; REST needs none of it
  copy_with_extension: ^17.1.0   # only if copy_with is left on
  shelf: ^1.4.2                  # only if the schema has Query/Mutation fields
  shelf_router: ^1.1.4           # idem, for the generated REST routes

dev_dependencies:
  graphql_openapi_codegen: ^1.1.0
```

## Custom directives

A directive whose name starts with an underscore becomes a validator. Declare
it in the SDL, use it on an input field, and the generator scaffolds the
function once:

```graphql
"""Rejects a VAT number that fails the modulo 97 check."""
directive @_vatNo on INPUT_FIELD_DEFINITION

input CompanyInput {
  vatNo: String! @_vatNo
}
```

You get `lib/validators/valid_vat_no.dart` with a `validVatNo(dynamic value)` to
fill in. Name the directive after the field it guards, not after the check:
`valid` is prefixed for you, so `@_validVat` would give you `validValidVat`.

The model calls it from an **`assert`**, so it runs under
`dart run --enable-asserts` and is compiled out of a release build. Reject input
you do not trust in the resolver instead.

## Limitations

- One schema per package.
- `@JsonSerializable(fieldRename:)` is not read: honouring it would rename
  fields in schemas already serving traffic. Use `@JsonKey(name:)` instead.
- The documentation pages ship the bare minimum. They apply the CORS headers
  they are given and nothing else; authentication and branding are yours to add
  once, in files the generator will not overwrite.
