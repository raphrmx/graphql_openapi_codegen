# GraphQL OpenAPI Codegen

[![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/graphql_openapi_codegen/ci.yml?branch=main&label=build)](https://github.com/raphrmx/graphql_openapi_codegen/actions/workflows/ci.yml)
[![Pub Version](https://img.shields.io/pub/v/graphql_openapi_codegen?color=blue)](https://pub.dev/packages/graphql_openapi_codegen)
[![License](https://img.shields.io/badge/Licence-MIT-blue)](LICENSE)

Takes a GraphQL schema and writes the Dart server around it: the models, the
enums, the resolver stubs, the validators, a REST endpoint per operation, an
OpenAPI document describing them, and the two pages that document the whole
thing.

Schema-first, and for servers. Everything else on pub.dev in this space
generates **clients**: [graphql_codegen](https://pub.dev/packages/graphql_codegen),
[artemis](https://pub.dev/packages/artemis) and
[gql_build](https://pub.dev/packages/gql_build) turn a schema and your queries
into typed request code. This one goes the other way.

## What it writes

| From the SDL | It generates |
| --- | --- |
| `type` | a model class with `@graphQLClass`, `@JsonSerializable()` and optionally `@CopyWith()` |
| `input` | the same, as a GraphQL input class |
| `enum` | one shared `enums.dart` |
| a field with arguments | a resolver stub, created once and never overwritten |
| `Query` / `Mutation` / `Subscription` | the field list, plus one REST endpoint each |
| a custom `@_directive` | a validator stub, created once |
| the whole schema | an OpenAPI 3.0.3 document |
| | a GraphQL Playground page and a Swagger UI page |

Generated code is emitted lint-clean: sorted `package:` imports, a `library;`
directive under the header, one trailing newline, no `async` on a body that
never awaits.

## Usage

```bash
dart pub add dev:graphql_openapi_codegen
dart run graphql_openapi_codegen
```

It reads the SDL, writes the sources, runs `build_runner` for the `.g.dart`
parts, then `dart format` on what it overwrites.

## Configuration

Everything is read from the `graphql_openapi_codegen:` section of your
`pubspec.yaml`, next to the package name the generator has to read anyway.
Every entry is optional; the defaults describe a plain package with no
versioned layout and no class prefix.

```yaml
graphql_openapi_codegen:
  schema: lib/schema.graphql    # the SDL to read
  class_prefix: ''              # prefix for SDL types starting with `_`
  copy_with: true               # emit @CopyWith() on the models
  api_name: ''                  # OpenAPI title, defaults to the package name
  api_servers: []               # OpenAPI `servers:` entries
  git_add: false                # stage the result after a successful run
  doc_routes:
    graphql: /graphql-doc       # '' disables the page
    rest: /rest-doc
    graphql_endpoint: /graphql  # where the playground sends its queries
    openapi_url: /openapi.yaml  # where swagger fetches the document
  output:
    models: lib/models
    fields: lib/graphql/fields
    validators: lib/validators
    resolvers: lib/resolvers
    graphql: lib/graphql
    rest: lib/rest
    endpoints: lib/rest/endpoints
    openapi: assets
    routes: lib/routes
```

The SDL marks a type belonging to the host with a leading underscore, which is
not a legal start for a public Dart identifier. `class_prefix` is what replaces
it: `_Company` becomes `Company` when empty, `BmcCompany` when set to `Bmc`.

## What it overwrites, and what it does not

Regenerated on every run, so never edit them:

- everything under `output.models` and `output.fields`
- `rest_routes.dart`, `doc_routes.dart`, `register_all.dart`,
  `graphql_resolvers_registry.dart`, the `validators.dart` facade
- the OpenAPI document

Created once and then yours, so the generator will not touch your work:

- the resolver stubs
- the REST endpoint handlers
- the individual validators
- the two documentation pages

## Requirements

The generated code imports these, so the package you generate into declares
them:

```yaml
dependencies:
  graphql_schema3: ^3.2.1
  json_annotation: ^4.12.0
  copy_with_extension: ^17.1.0   # only if copy_with is left on
  shelf: ^1.4.2                  # only if the schema has Query/Mutation fields
  shelf_router: ^1.1.4           # idem, for the generated REST routes

dev_dependencies:
  build_runner: ^2.16.1
  graphql_generator3: ^3.2.1
  json_serializable: ^6.14.1
  copy_with_extension_gen: ^17.1.0   # only if copy_with is left on
```

## Custom directives

A directive whose name starts with an underscore becomes a validator. Declare
it in the SDL, use it on an input field, and the generator scaffolds the
function once:

```graphql
"""Rejects a VAT number that fails the modulo 97 check."""
directive @_validVat on INPUT_FIELD_DEFINITION

input CompanyInput {
  vatNo: String! @_validVat
}
```

You get `lib/validators/valid_vat.dart` with a `validVat(dynamic value)` to
fill in, and the model calls it from its constructor.

## Limitations

- One schema per package.
- `@JsonSerializable(fieldRename:)` is not read: honouring it would rename
  fields in schemas already serving traffic. Use `@JsonKey(name:)` instead.
- The documentation pages ship the bare minimum. They apply the CORS headers
  they are given and nothing else; authentication and branding are yours to add
  once, in files the generator will not overwrite.
