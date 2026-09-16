import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/module_tabs_page.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import 'material_types_admin.dart';

class MasterDataScreen extends StatelessWidget {
  const MasterDataScreen({super.key});

  static const _tables = [
    ModuleTable(
      'organizations',
      label: 'Organización',
      help:
          'Datos de la empresa actual, país, zona horaria, idioma/región y moneda predeterminada.',
    ),
    ModuleTable(
      'organization_members',
      label: 'Miembros',
      help:
          'Usuarios asociados a la organización. Los permisos finales se aplican con autenticación y políticas de acceso por registro.',
    ),
    ModuleTable(
      'currencies',
      label: 'Monedas',
      help: 'Catálogo de monedas utilizadas en clientes, pedidos y costos.',
    ),
    ModuleTable(
      'payment_terms',
      label: 'Condiciones de pago',
      help:
          'Días de crédito y descuentos por pronto pago reutilizados por clientes y pedidos.',
    ),
    ModuleTable(
      'uom_categories',
      label: 'Categorías de unidades',
      help:
          'Familias de unidades compatibles, por ejemplo cantidad, longitud, área o masa.',
    ),
    ModuleTable(
      'units_of_measure',
      label: 'Unidades de medida',
      help:
          'Unidades y factor de conversión respecto a la unidad base de su categoría.',
    ),
    ModuleTable(
      'product_categories',
      label: 'Categorías de producto',
      help:
          'Clasificación simple utilizada solo en el catálogo de productos. Incluye icono.',
    ),
    ModuleTable(
      'material_categories',
      label: 'Categorías de material',
      help:
          'Clasificación opcional utilizada solo en el catálogo de materiales.',
    ),
    ModuleTable(
      'product_types',
      label: 'Tipos de producto',
      help:
          'Tipos configurables como producto terminado, pieza especial o cualquier clasificación comercial propia de la empresa.',
    ),
    ModuleTable(
      'material_types',
      label: 'Tipos de material',
      help:
          'Tipos definidos por la empresa y sus atributos técnicos dinámicos.',
    ),
    ModuleTable(
      'number_sequences',
      label: 'Foliadores',
      help:
          'Secuencias automáticas utilizadas para clientes, pedidos, órdenes de producción, entregas, reclamaciones y no conformidades.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tables.length,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 32,
              compact ? 12 : 18,
              compact ? 12 : 32,
              compact ? 16 : 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: compact ? constraints.maxWidth - 40 : 520,
                      ),
                      child: Text(
                        'Datos maestros',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: PomgtColors.ink,
                              letterSpacing: 0,
                            ),
                      ),
                    ),
                    const InfoTip(
                      'Configuración compartida por los módulos. Aquí se administran catálogos que cambian con poca frecuencia.',
                      size: 19,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: PomgtColors.surfaceAlt,
                    borderRadius: PomgtRadii.borderSm,
                  ),
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    indicatorColor: PomgtColors.blue,
                    indicator: const BoxDecoration(
                      color: PomgtColors.canvas,
                      borderRadius: PomgtRadii.borderSm,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: PomgtColors.ink,
                    unselectedLabelColor: PomgtColors.muted,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                    tabs: _tables.map((t) {
                      final spec = Phase1Schema.tables[t.table];
                      final label =
                          t.label ?? UiCopy.tableTitle(t.table, spec?.title);
                      final tip =
                          t.help ??
                          UiCopy.tableDescription(t.table, spec?.description);
                      return Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(label),
                            const SizedBox(width: 5),
                            InfoTip(tip, size: 13),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: TabBarView(
                    children: _tables.map((t) {
                      if (t.table == 'material_types') {
                        return const MaterialTypesAdmin();
                      }
                      return EntityCrudPanel(
                        table: t.table,
                        repository: context.read<GenericRepository>(),
                        lookups: context.read<LookupRepository>(),
                        description: t.help,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
