/// The shop's catalogue, standing in for a database.
///
/// Hand written, like everything outside the generated directories. Swapping it
/// for a real store is the only change a production version of this example
/// would need.
library;

import 'package:acme_shop_api/models/enums.dart';
import 'package:acme_shop_api/models/product_type.dart';

/// Products by SKU, seeded so a first query answers something.
final Map<String, Product> catalogue = <String, Product>{
  'ACM1001': Product(
    sku: 'ACM1001',
    label: 'Anvil, 200 kg',
    priceCents: 24900,
    availability: Availability.IN_STOCK,
  ),
  'ACM2042': Product(
    sku: 'ACM2042',
    label: 'Rocket skates, pair',
    priceCents: 8990,
    availability: Availability.OUT_OF_STOCK,
  ),
};
