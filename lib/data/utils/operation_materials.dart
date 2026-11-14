/// Resolves types against this order's BOM, preserving repeated BOM lines.
List<Map<String, dynamic>> resolveOperationMaterialTypes(
  List<Map<String, dynamic>> links,
  List<Map<String, dynamic>> materials,
  Map<String, Map<String, dynamic>> products,
) {
  final resolved = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final link in links) {
    final typeId = link['material_type_id']?.toString();
    if (typeId == null) {
      resolved.add(link);
      continue;
    }
    for (final material in materials) {
      final productId = material['material_product_id']?.toString();
      if (products[productId]?['material_type_id']?.toString() != typeId) {
        continue;
      }
      final identity =
          material['bom_item_id']?.toString() ??
          material['id']?.toString() ??
          productId;
      if (identity == null || !seen.add(identity)) continue;
      resolved.add({
        ...link,
        'bom_item_id': material['bom_item_id'],
        'material_product_id': productId,
        'quantity_override': material['required_quantity'],
        'uom_id': material['uom_id'],
      });
    }
  }
  return resolved;
}
