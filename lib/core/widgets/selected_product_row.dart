import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';
import 'number_input.dart';

/// A picked product with a quantity field and a remove button, used by
/// multi-product pickers (the pedido wizard's "Agregar productos" step, the
/// multi-product production-order dialog). Optionally shows a "no active
/// BOM yet" nudge with a "Vincular materiales" action, and/or a "no active
/// routing yet" nudge with a "Vincular ruta" action — a product without an
/// active BOM or routing can't be released/prepared into production. Both
/// warnings can show at once.
class SelectedProductRow extends StatelessWidget {
  const SelectedProductRow({
    super.key,
    required this.product,
    required this.controller,
    required this.onRemove,
    this.missingBom = false,
    this.onLinkBom,
    this.missingRouting = false,
    this.onLinkRouting,
  });
  final Map<String, dynamic> product;
  final TextEditingController controller;
  final VoidCallback onRemove;
  final bool missingBom;
  final VoidCallback? onLinkBom;
  final bool missingRouting;
  final VoidCallback? onLinkRouting;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border.all(color: PomgtColors.line),
        borderRadius: PomgtRadii.borderSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${product['sku'] ?? '—'} · ${product['name'] ?? 'Producto'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [ThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Cantidad',
                    hintText: 'Ej. 1',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                icon: const Icon(LucideIcons.x, size: 16),
                onPressed: onRemove,
              ),
            ],
          ),
          if (missingBom && onLinkBom != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.triangleAlert,
                    size: 13,
                    color: PomgtColors.warning,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Sin estructura de fabricación activa',
                      style: TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onLinkBom,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Vincular materiales',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          if (missingRouting && onLinkRouting != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.triangleAlert,
                    size: 13,
                    color: PomgtColors.warning,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Sin ruta de fabricación activa',
                      style: TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onLinkRouting,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Vincular ruta',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
