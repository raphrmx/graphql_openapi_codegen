import 'dart:io';

import 'package:graphql_openapi_codegen/src/config.dart';
import 'package:graphql_openapi_codegen/src/consts.dart';
import 'package:graphql_openapi_codegen/src/helpers.dart';
import 'package:path/path.dart' as path;

/// Generates the two documentation pages and the file that mounts them.
///
/// The pages are a GraphQL Playground over [ImporterConfig.graphqlPath]
/// and a Swagger UI over [ImporterConfig.openApiUrl]. Both are written once
/// and never overwritten: they are a starting point, and every project ends up
/// wiring its own authentication, CORS and branding into them.
///
/// The file that mounts them is regenerated on every run, so a change of route
/// in `pubspec.yaml` takes effect without touching the pages themselves.
void generateDocRoutes(Directory routesDir) {
  final wantsGraphQL = importerConfig.graphqlDocPath.isNotEmpty;
  final wantsRest = importerConfig.restDocPath.isNotEmpty;
  if (!wantsGraphQL && !wantsRest) return;

  routesDir.createSync(recursive: true);

  if (wantsGraphQL) _writeGraphQLDocPage(routesDir);
  if (wantsRest) _writeRestDocPage(routesDir);

  _writeDocRoutes(routesDir, wantsGraphQL: wantsGraphQL, wantsRest: wantsRest);
}

String get _title => importerConfig.apiName.isEmpty
    ? importerConfig.packageName
    : importerConfig.apiName;

/// The GraphQL Playground page, created once.
void _writeGraphQLDocPage(Directory routesDir) {
  final file = File(path.join(routesDir.path, 'graphql_doc_route.dart'));
  if (file.existsSync()) return;

  final body = StringBuffer();
  body.writeln('''
/// Serves a GraphQL Playground over the API.
///
/// Add whatever pipeline the project needs around it: this handler applies the
/// CORS headers it is given and nothing else.
Handler graphQLDocHandler(Map<String, String> cors) => const Pipeline().addHandler((
  request,
) {
  const html = \'\'\'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>${htmlEscaped(_title)} GraphQL</title>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <link rel="stylesheet" href="https://unpkg.com/graphql-playground-react/build/static/css/index.css"/>
  <script src="https://unpkg.com/graphql-playground-react/build/static/js/middleware.js"></script>
  <style>
    body { margin: 0; font-family: sans-serif; }
    #root { height: 100vh; }
    #auth { position: absolute; inset: 0; display: flex; flex-direction: column;
            align-items: center; justify-content: center; background: #121212; color: #eee; }
    #auth input { width: 420px; max-width: calc(100vw - 48px); padding: 12px 10px;
                  background: transparent; color: #e0e0e0; border: none; border-bottom: 2px solid #555; }
    #auth button { margin-top: 24px; padding: 10px 24px; border: none; border-radius: 4px; cursor: pointer; }
  </style>
</head>
<body>
  <div id="auth">
    <h2>${htmlEscaped(_title)} GraphQL</h2>
    <input id="token" placeholder="Bearer token"/>
    <button onclick="start()">Open</button>
  </div>
  <div id="root" style="display:none"></div>
  <script>
    function start() {
      var raw = document.getElementById('token').value.trim();
      var token = raw.toLowerCase().indexOf('bearer ') === 0 ? raw.substring(7).trim() : raw;
      document.getElementById('auth').style.display = 'none';
      document.getElementById('root').style.display = 'block';
      GraphQLPlayground.init(document.getElementById('root'), {
        endpoint: '${importerConfig.graphqlPath}',
        settings: { 'editor.theme': 'dark', 'request.credentials': 'same-origin' },
        headers: token ? { 'Authorization': 'Bearer ' + token } : {}
      });
    }
  </script>
</body>
</html>
\'\'\';

  return Response.ok(
    html,
    headers: {'Content-Type': 'text/html'},
  ).change(headers: cors);
});''');

  writeGeneratedLibrary(
    file,
    description: 'GraphQL documentation page.',
    extra: const [
      'Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.',
    ],
    imports: ImportBlock()..add('package:shelf/shelf.dart'),
    body: body.toString(),
  );
  createdOnceFiles.add(file.path);
}

/// The Swagger UI page, created once.
void _writeRestDocPage(Directory routesDir) {
  final file = File(path.join(routesDir.path, 'rest_doc_route.dart'));
  if (file.existsSync()) return;

  final body = StringBuffer();
  body.writeln('''
/// Serves a Swagger UI over the generated OpenAPI document.
///
/// Add whatever pipeline the project needs around it: this handler applies the
/// CORS headers it is given and nothing else.
Handler restDocHandler(Map<String, String> cors) => const Pipeline().addHandler((
  request,
) {
  const html = \'\'\'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>${htmlEscaped(_title)} REST</title>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist/swagger-ui.css"/>
  <style> body { margin: 0; } </style>
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js"></script>
  <script src="https://unpkg.com/swagger-ui-dist/swagger-ui-standalone-preset.js"></script>
  <script>
    SwaggerUIBundle({
      url: '${importerConfig.openApiUrl}',
      dom_id: '#swagger-ui',
      presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
      layout: 'StandaloneLayout',
      persistAuthorization: true
    });
  </script>
</body>
</html>
\'\'\';

  return Response.ok(
    html,
    headers: {'Content-Type': 'text/html'},
  ).change(headers: cors);
});''');

  writeGeneratedLibrary(
    file,
    description: 'REST documentation page.',
    extra: const [
      'Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.',
    ],
    imports: ImportBlock()..add('package:shelf/shelf.dart'),
    body: body.toString(),
  );
  createdOnceFiles.add(file.path);
}

/// The file that mounts the pages, rewritten on every run so a route changed in
/// `pubspec.yaml` takes effect without touching the pages.
void _writeDocRoutes(
  Directory routesDir, {
  required bool wantsGraphQL,
  required bool wantsRest,
}) {
  final out = File(path.join(routesDir.path, 'doc_routes.dart'));

  final imports = ImportBlock()..add('package:shelf_router/shelf_router.dart');
  if (wantsGraphQL) {
    imports.addLibFile(path.join(routesDirPath, 'graphql_doc_route.dart'));
  }
  if (wantsRest) {
    imports.addLibFile(path.join(routesDirPath, 'rest_doc_route.dart'));
  }

  final body = StringBuffer();
  body.writeln(
    'void registerDocRoutes(Router router, '
    "{String prefix = '', Map<String, String>? cors}) {",
  );
  if (wantsGraphQL) {
    body.writeln(
      "  router.get('\$prefix${importerConfig.graphqlDocPath}', graphQLDocHandler(cors ?? const {}));",
    );
  }
  if (wantsRest) {
    body.writeln(
      "  router.get('\$prefix${importerConfig.restDocPath}', restDocHandler(cors ?? const {}));",
    );
  }
  body.writeln('}');

  writeGeneratedLibrary(
    out,
    description: 'Auto generated documentation routes.',
    extra: const ['Mounts the GraphQL and REST documentation pages.'],
    imports: imports,
    body: body.toString(),
  );
}
