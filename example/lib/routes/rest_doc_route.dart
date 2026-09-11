/// REST documentation page.
/// Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.
library;

import 'package:shelf/shelf.dart';

/// Serves a Swagger UI over the generated OpenAPI document.
///
/// Add whatever pipeline the project needs around it: this handler applies the
/// CORS headers it is given and nothing else.
Handler restDocHandler(Map<String, String> cors) =>
    const Pipeline().addHandler((request) {
      const html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Acme Shop REST</title>
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
      url: '/static/openapi.yaml',
      dom_id: '#swagger-ui',
      presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
      layout: 'StandaloneLayout',
      persistAuthorization: true
    });
  </script>
</body>
</html>
''';

      return Response.ok(
        html,
        headers: {'Content-Type': 'text/html'},
      ).change(headers: cors);
    });
