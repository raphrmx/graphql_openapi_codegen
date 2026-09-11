/// This file contains a validation function for the `_skuFormat` GraphQL directive.
/// It is a placeholder that is generated once to allow custom validation logic.
/// GraphQL Description: Rejects a SKU that is not three letters followed by four
/// digits.
/// To implement it, replace the `return true` with your own logic.
/// The function should return `true` if the value is valid and `false` otherwise.
/// The function is called automatically in the constructor of the generated models.
/// Example:
/// ```dart
/// class ClassConstructor {
///   final String property;
///   const ClassConstructor(this.property) : assert(validSkuFormat(property));
/// }
/// ```
library;

/// Three capitals then four digits, the shape every Acme SKU has.
final RegExp _skuPattern = RegExp(r'^[A-Z]{3}\d{4}$');

bool validSkuFormat(dynamic value) =>
    value is String && _skuPattern.hasMatch(value);
