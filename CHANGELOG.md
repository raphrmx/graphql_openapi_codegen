# Change Log

## 1.1.2

### Changed

- The README carries its build badge again, pointed at the branch the repository
  actually builds from.
- `homepage` points at the package's card on packages.comapps.be, which lists every
  package published under COMAPPS.
- The README badge row carries the maintainer again, and a licence badge in a
  colour of its own rather than the grey shields puts in every label. Nothing
  about the library changed.
- The badge row carries a PayPal donation badge, `funding` points pub.dev
  at the same donation page, and the README ends on the other packages
  COMAPPS publishes.

## 1.1.1

### Fixed
- `routes.graphql_doc: ''` and `routes.rest_doc: ''` did not turn the pages off.
  A blank value was read as "not set" and replaced by the default path, so a
  package serving its own documentation got the generated pages anyway.

## 1.1.0

### Added
- The builders travel with the generator. `build_runner`, `graphql_generator3`,
  `json_serializable` and `copy_with_extension_gen` are its own dependencies,
  and it writes a `build.yaml` switching on the ones that need it. Your
  `dev_dependencies` hold `graphql_openapi_codegen` and nothing else.

### Changed
- The OpenAPI document is **3.1.1** rather than 3.0.3. Nullability is now JSON
  Schema's, a type union for a scalar or an array and an `anyOf` for a
  reference, because 3.1 removed `nullable: true`.

### Fixed
- An enum produced no `.g.dart` at all unless the target package declared
  `graphql_generator3` itself, leaving `part 'enums.g.dart'` pointing at
  nothing.
- Response schemas carried no `required:` list, so a field the schema declares
  non-null came out optional and every generated client treated it as such.

## 1.0.0

First release. Generates, from one GraphQL schema: the model, input and enum
classes, a resolver stub per operation, a REST endpoint per operation, an
OpenAPI 3.0.3 document, a GraphQL Playground page and a Swagger UI page.

Paths, output directories, the OpenAPI title and servers and the class prefix
are read from the `graphql_openapi_codegen:` section of `pubspec.yaml`.
`@CopyWith()` can be turned off.
