import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/widgets/categorized_picker.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/scroll_to_top.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../data/repositories/routing_repository.dart';

/// Lets the user link a manufacturing routing to a product that doesn't
/// have an active one yet, without a separate trip to the Rutas de
/// fabricación module. "Omitir por ahora" is always available — nothing
/// here is mandatory.
///
/// Two ways to do that: reuse a routing that already exists for this
/// product's category (or for another product in that category, which
/// only varies in materials/BOM, not in the manufacturing steps), or
/// create a brand-new one. Unlike [LinkBomDialog], creating a new routing
/// here doesn't let the user author operations (steps) inline — that's a
/// much heavier editor (work center, machine, labor role, sequence,
/// duration) out of scope for a quick unblock modal. Either way, the
/// result is immediately usable to release/prepare an OP, but a routing
/// with no operations still needs them added before it can actually run.
class LinkRoutingDialog extends StatefulWidget {
  const LinkRoutingDialog({super.key, required this.product});
  final Map<String, dynamic> product;

  @override
  State<LinkRoutingDialog> createState() => LinkRoutingDialogState();
}

class LinkRoutingDialogState extends State<LinkRoutingDialog> {
  late final TextEditingController _code;
  late final TextEditingController _name;
  bool _byCategory = false;
  String? _categoryId;
  bool _saving = false;
  String? _error;
  late Future<List<List<Map<String, dynamic>>>> _future;

  @override
  void initState() {
    super.initState();
    final sku = widget.product['sku']?.toString() ?? '';
    _code = TextEditingController(text: sku.isEmpty ? 'RT' : 'RT-$sku');
    _name = TextEditingController(
      text: 'Ruta de fabricación · ${widget.product['name'] ?? sku}',
    );
    _categoryId = widget.product['category_id']?.toString();
    final lookups = context.read<LookupRepository>();
    _future = Future.wait([
      lookups.rows('routings'),
      lookups.rows('routing_revisions'),
      lookups.rows('products'),
      lookups.rows('product_categories'),
    ]);
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _revisionsFor(
    String routingId,
    List<Map<String, dynamic>> revisions,
  ) {
    final rows = revisions
        .where((rev) => rev['routing_id']?.toString() == routingId)
        .toList();
    rows.sort((a, b) {
      final da = DateTime.tryParse(a['created_at']?.toString() ?? '');
      final db = DateTime.tryParse(b['created_at']?.toString() ?? '');
      if (da == null || db == null) return 0;
      return db.compareTo(da);
    });
    return rows;
  }

  /// Routings already relevant to this product's category: its own (even
  /// if not active yet), the category's own routing, or another product's
  /// routing within the same category — all candidates to reuse instead of
  /// creating a duplicate that would only differ in materials, not steps.
  List<Map<String, dynamic>> _candidates(
    List<Map<String, dynamic>> routings,
    List<Map<String, dynamic>> products,
  ) {
    final productId = widget.product['id']?.toString();
    final categoryId = widget.product['category_id']?.toString();
    final categoryByProduct = <String, String?>{
      for (final p in products)
        if (p['id'] != null) p['id'].toString(): p['category_id']?.toString(),
    };
    return routings.where((r) {
      if (r['is_active'] != true) return false;
      final rProductId = r['product_id']?.toString();
      final rCategoryId = r['category_id']?.toString();
      if (rProductId != null) {
        if (rProductId == productId) return true;
        return categoryId != null &&
            categoryByProduct[rProductId] == categoryId;
      }
      return rCategoryId != null && rCategoryId == categoryId;
    }).toList();
  }

  Future<void> _useExisting(
    Map<String, dynamic> routing,
    List<Map<String, dynamic>> revisions,
  ) async {
    final productId = widget.product['id']?.toString();
    final categoryId = widget.product['category_id']?.toString();
    final belongsToOtherProduct =
        routing['product_id'] != null &&
        routing['product_id'].toString() != productId;
    if (belongsToOtherProduct) {
      final confirmed = await showPomgtDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Convertir en ruta de categoría'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: const Text(
              'Esta ruta pertenece a otro producto. Para reusarla aquí, '
              'dejará de ser exclusiva de ese producto y aplicará a todos '
              'los productos de esta categoría, incluido este. Los pasos '
              'de fabricación son los mismos; solo cambian los materiales '
              'de cada producto.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Convertir y usar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final generic = context.read<GenericRepository>();
      final routingsSpec = Phase1Schema.tables['routings']!;
      final revisionsSpec = Phase1Schema.tables['routing_revisions']!;
      if (belongsToOtherProduct) {
        await generic.updateRow(routingsSpec, routing['id'].toString(), {
          'product_id': null,
          'category_id': categoryId,
        });
      }
      final hasActive = revisions.any(
        (rev) => rev['status']?.toString() == 'active',
      );
      if (!hasActive) {
        if (revisions.isEmpty) {
          await generic.createRow(revisionsSpec, {
            'routing_id': routing['id'].toString(),
            'revision_code': 'V.01',
            'status': 'active',
          });
        } else {
          await generic.updateRow(
            revisionsSpec,
            revisions.first['id'].toString(),
            {'status': 'active'},
          );
        }
      }
      if (!mounted) return;
      final lookups = context.read<LookupRepository>();
      lookups.invalidate('routings');
      lookups.invalidate('routing_revisions');
      showPomgtSnackBar(context, 'Ruta de fabricación vinculada.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ErrorCopy.message(
          e,
          fallback: 'No fue posible vincular la ruta de fabricación.',
        );
      });
    }
  }

  Future<void> _create() async {
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = 'Captura el código y el nombre de la ruta.');
      return;
    }
    if (_byCategory && _categoryId == null) {
      setState(() => _error = 'Selecciona una categoría.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final routings = context.read<RoutingRepository>();
      await routings.createWithInitialRevision(
        productId: _byCategory ? null : widget.product['id'].toString(),
        categoryId: _byCategory ? _categoryId : null,
        routingCode: _code.text.trim(),
        name: _name.text.trim(),
        isDefault: true,
        revisionStatus: 'active',
      );
      if (!mounted) return;
      final lookups = context.read<LookupRepository>();
      lookups.invalidate('routings');
      lookups.invalidate('routing_revisions');
      showPomgtSnackBar(context, 'Ruta de fabricación creada.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ErrorCopy.message(
          e,
          fallback: 'No fue posible crear la ruta de fabricación.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 560;
    final sku = widget.product['sku']?.toString() ?? '';
    final name = widget.product['name']?.toString() ?? '';
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 24,
        vertical: compact ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? screen.width - 20 : 560,
          maxHeight: screen.height * (compact ? .96 : .86),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 28,
            compact ? 16 : 24,
            compact ? 16 : 28,
            compact ? 14 : 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    LucideIcons.gitBranch,
                    color: PomgtColors.ink,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ruta de fabricación',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$sku · $name no tiene una ruta activa.',
                          style: const TextStyle(
                            color: PomgtColors.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
              const Divider(height: 24),
              Flexible(
                child: ScrollToTopArea(
                  padding: const EdgeInsets.all(12),
                  builder: (context, controller) => SingleChildScrollView(
                    controller: controller,
                    child: FutureBuilder<List<List<Map<String, dynamic>>>>(
                      future: _future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        final data =
                            snapshot.data ??
                            const [
                              <Map<String, dynamic>>[],
                              <Map<String, dynamic>>[],
                              <Map<String, dynamic>>[],
                              <Map<String, dynamic>>[],
                            ];
                        final routings = data[0];
                        final revisions = data[1];
                        final products = data[2];
                        final categories = data[3];
                        final candidates = _candidates(routings, products);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (candidates.isNotEmpty) ...[
                              const Text(
                                'Rutas existentes de esta categoría',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Mismos pasos de fabricación, solo cambian los '
                                'materiales por producto — reusa una en vez de '
                                'crear otra desde cero.',
                                style: TextStyle(
                                  color: PomgtColors.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (final routing in candidates)
                                _ExistingRoutingTile(
                                  routing: routing,
                                  revisions: _revisionsFor(
                                    routing['id'].toString(),
                                    revisions,
                                  ),
                                  ownProduct:
                                      routing['product_id']?.toString() ==
                                      widget.product['id']?.toString(),
                                  otherProductName:
                                      routing['product_id'] == null
                                      ? null
                                      : products
                                            .firstWhere(
                                              (p) =>
                                                  p['id']?.toString() ==
                                                  routing['product_id']
                                                      ?.toString(),
                                              orElse: () => const {},
                                            )['name']
                                            ?.toString(),
                                  enabled: !_saving,
                                  onUse: () => _useExisting(
                                    routing,
                                    _revisionsFor(
                                      routing['id'].toString(),
                                      revisions,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 18),
                              Row(
                                children: const [
                                  Expanded(child: Divider()),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Text(
                                      'o crea una nueva',
                                      style: TextStyle(
                                        color: PomgtColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('Producto específico'),
                                  icon: Icon(LucideIcons.package, size: 16),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('Categoría'),
                                  icon: Icon(LucideIcons.shapes, size: 16),
                                ),
                              ],
                              selected: {_byCategory},
                              onSelectionChanged: _saving
                                  ? null
                                  : (selection) => setState(() {
                                      _byCategory = selection.first;
                                      _error = null;
                                    }),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _byCategory
                                  ? 'Se vuelve la ruta predeterminada de '
                                        'cualquier producto de esta categoría '
                                        'que no tenga una ruta propia asignada.'
                                  : 'Ruta ligada únicamente a este producto.',
                              style: const TextStyle(
                                color: PomgtColors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (_byCategory)
                              CategorizedSearchPicker(
                                key: const ValueKey('link-routing-category'),
                                label: 'Categoría *',
                                hint: 'Buscar categoría…',
                                value: _categoryId,
                                items: [
                                  for (final c in categories)
                                    PickerItem(
                                      id: c['id'].toString(),
                                      label: '${c['code']} · ${c['name']}',
                                      category: 'Categorías',
                                    ),
                                ],
                                onChanged: (value) => setState(() {
                                  _categoryId = value;
                                  _error = null;
                                }),
                              ),
                            if (_byCategory) const SizedBox(height: 14),
                            TextFormField(
                              errorBuilder: pomgtValidationMessage,
                              controller: _code,
                              decoration: const InputDecoration(
                                labelText: 'Código *',
                                hintText: 'Ej. RT-0001',
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              errorBuilder: pomgtValidationMessage,
                              controller: _name,
                              decoration: const InputDecoration(
                                labelText: 'Nombre *',
                                hintText: 'Escribe el nombre de la ruta',
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Esta ruta todavía no tiene operaciones. '
                              'Agrégalas después en Rutas de fabricación — la '
                              'OP podrá prepararse, pero fallará al iniciar o '
                              'terminar un paso si la ruta sigue sin '
                              'operaciones.',
                              style: TextStyle(
                                color: PomgtColors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: PomgtColors.danger,
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Omitir por ahora'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _create,
                    icon: _saving
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.check, size: 18),
                    label: const Text('Crear ruta de fabricación'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExistingRoutingTile extends StatelessWidget {
  const _ExistingRoutingTile({
    required this.routing,
    required this.revisions,
    required this.ownProduct,
    required this.otherProductName,
    required this.enabled,
    required this.onUse,
  });
  final Map<String, dynamic> routing;
  final List<Map<String, dynamic>> revisions;
  final bool ownProduct;
  final String? otherProductName;
  final bool enabled;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final hasActive = revisions.any(
      (rev) => rev['status']?.toString() == 'active',
    );
    final isCategoryRouting = routing['category_id'] != null;
    final scopeLabel = ownProduct
        ? 'Este producto'
        : isCategoryRouting
        ? 'Esta categoría'
        : 'Producto: ${otherProductName ?? '—'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        border: Border.all(color: PomgtColors.line),
        borderRadius: PomgtRadii.borderSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${routing['routing_code'] ?? '—'} · ${routing['name'] ?? 'Ruta'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      scopeLabel,
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: hasActive
                            ? PomgtColors.mintSoft
                            : PomgtColors.amberSoft,
                        borderRadius: PomgtRadii.borderPill,
                      ),
                      child: Text(
                        hasActive ? 'Activa' : 'Borrador',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: hasActive
                              ? PomgtColors.success
                              : PomgtColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: enabled ? onUse : null,
            child: const Text('Usar'),
          ),
        ],
      ),
    );
  }
}
