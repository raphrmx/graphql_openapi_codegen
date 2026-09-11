# Change Log

## 1.0.0

Initial release. Extracted from the in-house tool that has generated the
`cms_client_communication` middleware since 2025, and made to stand on its own.

### Added
- Configuration through the `graphql_openapi_codegen:` section of `pubspec.yaml`:
  the SDL path, the class prefix, the OpenAPI title and servers, the HTTP paths
  under `routes:` and the filesystem paths under `output:`.
- Generated documentation routes: a GraphQL Playground and a Swagger UI, with
  their paths and targets configurable, mounted by a generated
  `registerDocRoutes(Router)`.
- An option to turn `@CopyWith()` off, which drops `copy_with_extension` from
  the consuming package entirely.
- `example/` is a runnable server generated from a nine-type schema, with the
  two resolvers and the validator filled in. Its `.g.dart` parts are not
  committed and do not ship; CI generates the example before analysing it, then
  fails on a diff, so a change to what the generator emits cannot land
  unnoticed.

### Changed
- Generated code is emitted lint-clean: the library doc comment sits against a
  `library;` directive, imports are `package:` URIs sorted into groups, files
  end with exactly one newline, string literals pick the quote that needs no
  escaping, and a body that never awaits is not declared `async`.
- Descriptions are escaped properly. The previous escaping handled the
  apostrophe and left the backslash and the dollar sign alone, so a description
  mentioning a Windows path emitted a tab, and one mentioning a price emitted a
  string interpolation that did not compile.
- `defaultValue:` is omitted when the SDL default renders as `null`, which is
  already the parameter's own default.
- Enum values keep their SDL spelling and the file carries
  `// ignore_for_file: constant_identifier_names`. Renaming them would change
  both the wire format and every call site.
- The `Query` and `Mutation` endpoint writers are one function. They were two
  copies that had drifted: only the query spread `req.context` into the
  resolver arguments, and the mutation typed its CORS map `Map<String, dynamic>`
  where the router calling it passes `Map<String, String>`.
- A stub is formatted the run that creates it. It used to be left unformatted
  because the formatter may never be pointed at a directory holding files the
  developer owns, which meant a fresh package failed `dart format --set-exit-if-changed`
  on code nobody had touched.

### Fixed
- A package with no `version:` in its `pubspec.yaml` aborted the whole run.
- REST endpoints accepted a `cors` map and then dropped it, so mounting
  `registerRestRoutes(router, cors: ...)` changed nothing about what they
  answered. The headers are now spread into the response.
- An operation the schema declares non-null emitted `result?.toJson() ?? {}` on
  a receiver that cannot be null, which the analyzer reports as
  `invalid_null_aware_operator`.
- Resolver stubs imported their models by relative path, which
  `always_use_package_imports` reports, and imported `dart:async` after them,
  which `directives_ordering` reports. `Future` and `Stream` come from
  `dart:core`, so the import is gone rather than moved. Subscription endpoints
  carried the same dead import, written above the block the others are sorted
  into.
- `graphql_resolvers_registry.dart` is created once, but the formatter ran over
  it on every run, reformatting whatever had been added to it.
- The validator name is derived in one place. The facade's exports and the stub
  file names were computed by two copies of the same expression.
- Removed `generateRestEndpoints`, 84 lines that nothing called.
- The interface generator emitted `graphql_schema3` annotations without
  importing the package.
- The class generator pointed its validator import at a path that does not
  exist, where the input generator had it right.
- The type resolver re-read and re-parsed the entire SDL from disk once per
  named type, then discarded the result.
