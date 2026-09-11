/// GraphQL documentation page.
/// Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.
library;

import 'package:shelf/shelf.dart';

/// Serves a GraphQL Playground over the API.
///
/// Add whatever pipeline the project needs around it: this handler applies the
/// CORS headers it is given and nothing else.
Handler graphQLDocHandler(Map<String, String> cors) =>
    const Pipeline().addHandler((request) {
      const html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Acme Shop GraphQL</title>
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
    <h2>Acme Shop GraphQL</h2>
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
        endpoint: '/graphql',
        settings: { 'editor.theme': 'dark', 'request.credentials': 'same-origin' },
        headers: token ? { 'Authorization': 'Bearer ' + token } : {}
      });
    }
  </script>
</body>
</html>
''';

      return Response.ok(
        html,
        headers: {'Content-Type': 'text/html'},
      ).change(headers: cors);
    });
