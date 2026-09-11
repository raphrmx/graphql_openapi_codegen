# Change Log

## 1.0.0

Initial release. Extracted from the in-house tool that has generated the
`cms_client_communication` middleware since 2025, and made to stand on its own.

### Added
- Configuration through the `graphql_openapi_codegen:` section of `pubspec.yaml`:
  the SDL path, the class prefix, the output directories, the OpenAPI title and
  servers, and whether the result is staged with `git add`.
- Generated documentation routes: a GraphQL Playground and a Swagger UI, with
  their paths and targets configurable, mounted by a generated
  `registerDocRoutes(Router)`.
- An option to turn `@CopyWith()` off, which drops `copy_with_extension` from
  the consuming package entirely.

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

### Fixed
- A package with no `version:` in its `pubspec.yaml` aborted the whole run.
- `git add` failing, for instance outside a repository, failed the generation
  that had already succeeded. It is now opt-in and never fatal.
- The interface generator emitted `graphql_schema3` annotations without
  importing the package.
- The class generator pointed its validator import at a path that does not
  exist, where the input generator had it right.
- The type resolver re-read and re-parsed the entire SDL from disk once per
  named type, then discarded the result.
