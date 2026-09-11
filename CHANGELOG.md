# Change Log

## 1.1.0

### Added
- The builders travel with the generator. `build_runner`, `graphql_generator3`,
  `json_serializable` and `copy_with_extension_gen` are its own dependencies,
  and it writes a `build.yaml` switching on the ones that need it. Your
  `dev_dependencies` hold `graphql_openapi_codegen` and nothing else.

### Fixed
- An enum produced no `.g.dart` at all unless the target package declared
  `graphql_generator3` itself, leaving `part 'enums.g.dart'` pointing at
  nothing.

## 1.0.0

First release. Generates, from one GraphQL schema: the model, input and enum
classes, a resolver stub per operation, a REST endpoint per operation, an
OpenAPI 3.0.3 document, a GraphQL Playground page and a Swagger UI page.

Paths, output directories, the OpenAPI title and servers and the class prefix
are read from the `graphql_openapi_codegen:` section of `pubspec.yaml`.
`@CopyWith()` can be turned off.
