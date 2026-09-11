// Created once by GraphQL Code-Gen. Edit freely; it will NOT be overwritten.

import 'dart:async';

typedef GraphQLFieldResolverFn =
    FutureOr<dynamic> Function(
      Object? serialized,
      Map<String, dynamic> argumentValues,
    );

final Map<String, GraphQLFieldResolverFn> resolverRegistry =
    <String, GraphQLFieldResolverFn>{};

/// Convenience helper (optional)
void registerResolver(String key, GraphQLFieldResolverFn fn) {
  resolverRegistry[key] = fn;
}
