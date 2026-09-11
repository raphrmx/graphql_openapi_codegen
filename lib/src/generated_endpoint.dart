import 'package:gql/ast.dart' as gql;

class GeneratedEndpoint {
  final String filePath;
  final String handlerName;
  final String routePath;
  final gql.FieldDefinitionNode? field;

  GeneratedEndpoint(
    this.filePath,
    this.handlerName,
    this.routePath, {
    this.field,
  });
}
