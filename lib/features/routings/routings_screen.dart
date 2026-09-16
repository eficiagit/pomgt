import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/feature_controllers.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/record_workspace.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';

class RoutingsScreen extends StatefulWidget {
  const RoutingsScreen({super.key});
  @override
  State<RoutingsScreen> createState() => _RoutingsScreenState();
}

class _RoutingsScreenState extends State<RoutingsScreen> {
  late Future<List<Map<String, dynamic>>> future;
  late int seenDataRevision;
  String search = '';
  String? selectedId;

  @override
  void initState() {
    super.initState();
    seenDataRevision = context.read<RuntimeDataController>().revision;
    future = _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dataRevision = context.watch<RuntimeDataController>().revision;
    if (dataRevision == seenDataRevision) return;
    seenDataRevision = dataRevision;
    _reload();
  }

  Future<List<Map<String, dynamic>>> _load() => context
      .read<GenericRepository>()
      .listRows(Phase1Schema.tables['routings']!);
  void _reload() {
    final next = _load();
    if (!mounted) return;
    setState(() {
      future = next;
    });
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['routings']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        original: row,
        title: row == null ? 'Nueva ruta' : 'Editar ruta',
        icon: Icons.route_outlined,
      ),
    );
    if (changed == true && mounted) {
      context.read<RoutingsController>().refresh();
      _reload();
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar ruta de fabricación'),
        content: const Text(
          'Esta acción no se puede deshacer. Los registros relacionados pueden impedir la eliminación para proteger la trazabilidad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<GenericRepository>().deleteRow(
        Phase1Schema.tables['routings']!,
        row,
      );
      if (!mounted) return;
      setState(() => selectedId = null);
      context.read<RoutingsController>().refresh();
      _reload();
    } catch (error) {
      if (!mounted) return;
      showPomgtSnackBar(context, error.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          final query = search.trim().toLowerCase();
          final filtered = rows
              .where(
                (row) =>
                    query.isEmpty ||
                    row.values.any(
                      (value) =>
                          value?.toString().toLowerCase().contains(query) ??
                          false,
                    ),
              )
              .toList();
          if (filtered.isNotEmpty &&
              (selectedId == null ||
                  !filtered.any((row) => row['id']?.toString() == selectedId)))
            selectedId = filtered.first['id']?.toString();
          final selected = filtered.cast<Map<String, dynamic>?>().firstWhere(
            (row) => row?['id']?.toString() == selectedId,
            orElse: () => filtered.isEmpty ? null : filtered.first,
          );
          if (snapshot.hasError)
            return const Center(
              child: Text(
                'No fue posible cargar rutas.',
                style: TextStyle(color: PomgtColors.danger),
              ),
            );
          final width = MediaQuery.sizeOf(context).width;
          final compact = width < 980;
          final sideWidth = width >= 1280 ? 280.0 : 310.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 14 : 18,
              compact ? 12 : 16,
              compact ? 18 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RoutingTitle(onCreate: () => _edit()),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final list = _RoutingList(
                        rows: filtered,
                        total: rows.length,
                        selectedId: selectedId,
                        search: search,
                        loading:
                            snapshot.connectionState == ConnectionState.waiting,
                        onSearch: (value) => setState(() => search = value),
                        onSelect: (id) => setState(() => selectedId = id),
                        onEdit: _edit,
                        onDelete: _delete,
                        onRefresh: _reload,
                      );
                      final detail = selected == null
                          ? const _RoutingPanel(
                              child: Center(
                                child: Text(
                                  'Selecciona una ruta para ver su expediente.',
                                  style: TextStyle(color: PomgtColors.muted),
                                ),
                              ),
                            )
                          : _RoutingOverview(
                              key: ValueKey(selected['id']),
                              routing: selected,
                              onEdit: () => _edit(selected),
                            );
                      if (constraints.maxWidth < 980) {
                        final listHeight = (constraints.maxHeight * .36).clamp(
                          240.0,
                          360.0,
                        );
                        return Column(
                          children: [
                            SizedBox(height: listHeight, child: list),
                            const SizedBox(height: 12),
                            Expanded(child: detail),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          SizedBox(width: sideWidth, child: list),
                          const SizedBox(width: 14),
                          Expanded(child: detail),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _RoutingDetail extends StatelessWidget {
  const _RoutingDetail({required this.routing});
  final Map<String, dynamic> routing;
  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = routing['id'].toString();
    Future<void> edit() async {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EntityFormDialog(
          spec: Phase1Schema.tables['routings']!,
          repository: generic,
          lookups: lookups,
          original: routing,
        ),
      );
      if (changed == true && context.mounted)
        context.read<RoutingsController>().refresh();
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: lookups.rows('products'),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <Map<String, dynamic>>[];
              final matches = rows
                  .where(
                    (p) =>
                        p['id']?.toString() ==
                        routing['product_id']?.toString(),
                  )
                  .toList();
              final productName = matches.isEmpty
                  ? 'Producto'
                  : lookups.display(
                      Phase1Schema.tables['products']!,
                      matches.first,
                    );
              return DetailHeader(
                icon: Icons.route_outlined,
                title: routing['name']?.toString() ?? 'Ruta de fabricación',
                subtitle: '${routing['routing_code']} · $productName',
                help:
                    'Ruta maestra de fabricación. Las operaciones se almacenan por revisión para mantener trazabilidad y permitir evolucionar el proceso sin cambiar órdenes históricas.',
                onEdit: edit,
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: DefaultTabController(
              length: 7,
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      indicatorColor: PomgtColors.blue,
                      labelColor: PomgtColors.ink,
                      unselectedLabelColor: PomgtColors.muted,
                      tabs: [
                        HelpTab(
                          label: 'General',
                          help:
                              'Información maestra de la ruta y producto que fabrica.',
                        ),
                        HelpTab(
                          label: 'Revisiones',
                          help:
                              'Versiones históricas o vigentes del proceso de fabricación.',
                        ),
                        HelpTab(
                          label: 'Operaciones',
                          help:
                              'Etapas de fabricación que componen cada revisión de la ruta.',
                        ),
                        HelpTab(
                          label: 'Detalle de operación',
                          help:
                              'Dependencias, materiales, personal, parámetros, verificación, calidad, costos y documentos de una operación.',
                        ),
                        HelpTab(
                          label: 'Recursos',
                          help:
                              'Centros de trabajo, máquinas, parámetros, roles de personal y procesos estándar.',
                        ),
                        HelpTab(
                          label: 'Plantillas',
                          help:
                              'Plantillas reutilizables de verificación y control de calidad.',
                        ),
                        HelpTab(
                          label: 'Documentos',
                          help:
                              'Instrucciones, planos y documentos controlados asociados a la ruta.',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _RoutingSummary(routing: routing),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: EntityCrudPanel(
                            table: 'routing_revisions',
                            repository: generic,
                            lookups: lookups,
                            fixedValues: {'routing_id': id},
                            title: 'Revisiones de la ruta',
                            description:
                                'Cada revisión representa una versión completa del proceso. Define vigencia, estado, aprobación y notas de cambio.',
                          ),
                        ),
                        NestedRelationPanel(
                          title: 'Operaciones por revisión',
                          help:
                              'Selecciona una revisión y agrega las operaciones de fabricación. POMGT asigna secuencias automáticamente en pasos de 10 para facilitar insertar operaciones entre etapas.',
                          parentTable: 'routing_revisions',
                          parentFilter: {'routing_id': id},
                          repository: generic,
                          lookups: lookups,
                          childTabs: const [
                            ChildTabDefinition(
                              table: 'routing_operations',
                              label: 'Operaciones',
                              foreignKey: 'routing_revision_id',
                              help:
                                  'Proceso, centro de trabajo, máquina preferida, preparación, tiempo, merma, rendimiento, instrucciones, calidad, lista de verificación y servicio externo.',
                            ),
                          ],
                        ),
                        _OperationDetailPanel(
                          routingId: id,
                          repository: generic,
                          lookups: lookups,
                        ),
                        _RoutingResources(
                          repository: generic,
                          lookups: lookups,
                        ),
                        _RoutingTemplates(
                          repository: generic,
                          lookups: lookups,
                        ),
                        NestedRelationPanel(
                          title: 'Documentos por revisión',
                          help:
                              'Vincula instrucciones, planos o documentos controlados a una revisión concreta de la ruta.',
                          parentTable: 'routing_revisions',
                          parentFilter: {'routing_id': id},
                          repository: generic,
                          lookups: lookups,
                          childTabs: const [
                            ChildTabDefinition(
                              table: 'document_links',
                              label: 'Documentos',
                              foreignKey: 'routing_revision_id',
                              help:
                                  'Documentos asociados a la revisión seleccionada.',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutingSummary extends StatelessWidget {
  const _RoutingSummary({required this.routing});
  final Map<String, dynamic> routing;

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: lookups.rows('products'),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final matches = rows
            .where(
              (p) => p['id']?.toString() == routing['product_id']?.toString(),
            )
            .toList();
        final productName = matches.isEmpty
            ? '—'
            : lookups.display(Phase1Schema.tables['products']!, matches.first);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Definición del proceso',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 7),
                  const InfoTip(
                    'La cabecera identifica la ruta. Las operaciones y todos sus requerimientos viven dentro de una revisión.',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 36,
                runSpacing: 22,
                children: [
                  _KV('Código', '${routing['routing_code']}'),
                  _KV('Producto', productName),
                  _KV(
                    'Predeterminado',
                    routing['is_default'] == true ? 'Sí' : 'No',
                  ),
                  _KV('Activo', routing['is_active'] == true ? 'Sí' : 'No'),
                ],
              ),
              if (routing['description'] != null) ...[
                const SizedBox(height: 30),
                Text(
                  routing['description'].toString(),
                  style: const TextStyle(
                    color: PomgtColors.secondaryInk,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OperationDetailPanel extends StatefulWidget {
  const _OperationDetailPanel({
    required this.routingId,
    required this.repository,
    required this.lookups,
  });
  final String routingId;
  final GenericRepository repository;
  final LookupRepository lookups;
  @override
  State<_OperationDetailPanel> createState() => _OperationDetailPanelState();
}

class _OperationDetailPanelState extends State<_OperationDetailPanel> {
  String? revisionId;
  String? operationId;
  late Future<List<Map<String, dynamic>>> revisions;
  @override
  void initState() {
    super.initState();
    revisions = widget.repository.listRows(
      Phase1Schema.tables['routing_revisions']!,
      filters: {'routing_id': widget.routingId},
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Configuración de operación',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 7),
            const InfoTip(
              'Todo lo necesario para ejecutar una etapa: dependencias, materiales, personal, parámetros de máquina, lista de verificación, calidad, costos y documentos.',
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: revisions,
          builder: (context, snap) {
            final revs = snap.data ?? const <Map<String, dynamic>>[];
            if (snap.connectionState == ConnectionState.waiting)
              return const Expanded(
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            if (revs.isEmpty)
              return const Expanded(
                child: Center(
                  child: Text(
                    'Crea primero una revisión de la ruta.',
                    style: TextStyle(color: PomgtColors.muted),
                  ),
                ),
              );
            revisionId ??= revs.first['id'].toString();
            return Expanded(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: revisionId,
                    decoration: const InputDecoration(labelText: 'Revisión'),
                    items: revs
                        .map(
                          (r) => DropdownMenuItem(
                            value: r['id'].toString(),
                            child: Text(
                              '${r['revision_code']} · ${UiCopy.enumLabel(r['status']?.toString() ?? '')}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      revisionId = v;
                      operationId = null;
                    }),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: widget.repository.listRows(
                        Phase1Schema.tables['routing_operations']!,
                        filters: {'routing_revision_id': revisionId},
                      ),
                      builder: (context, opSnap) {
                        final ops =
                            opSnap.data ?? const <Map<String, dynamic>>[];
                        if (opSnap.connectionState == ConnectionState.waiting)
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        if (ops.isEmpty)
                          return const Center(
                            child: Text(
                              'Agrega operaciones a esta revisión.',
                              style: TextStyle(color: PomgtColors.muted),
                            ),
                          );
                        operationId ??= ops.first['id'].toString();
                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: operationId,
                              decoration: const InputDecoration(
                                labelText: 'Operación',
                              ),
                              items: ops
                                  .map(
                                    (r) => DropdownMenuItem(
                                      value: r['id'].toString(),
                                      child: Text(
                                        '${r['sequence_no']} · ${r['name']}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => operationId = v),
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: DefaultTabController(
                                length: 8,
                                child: Column(
                                  children: [
                                    Container(
                                      color: PomgtColors.surfaceAlt,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: const TabBar(
                                        isScrollable: true,
                                        tabAlignment: TabAlignment.start,
                                        dividerColor: Colors.transparent,
                                        tabs: [
                                          HelpTab(
                                            label: 'Dependencias',
                                            help:
                                                'Reglas de precedencia entre operaciones.',
                                          ),
                                          HelpTab(
                                            label: 'Materiales',
                                            help:
                                                'Materiales consumidos durante esta operación.',
                                          ),
                                          HelpTab(
                                            label: 'Personal',
                                            help:
                                                'Roles y cantidad de personas requeridas.',
                                          ),
                                          HelpTab(
                                            label: 'Máquina',
                                            help:
                                                'Parámetros esperados de la máquina para ejecutar la operación.',
                                          ),
                                          HelpTab(
                                            label: 'Verificación',
                                            help:
                                                'Listas de verificación que debe completar el operador.',
                                          ),
                                          HelpTab(
                                            label: 'Calidad',
                                            help:
                                                'Controles de calidad requeridos durante la operación.',
                                          ),
                                          HelpTab(
                                            label: 'Costos',
                                            help:
                                                'Componentes de costo planeados de la operación.',
                                          ),
                                          HelpTab(
                                            label: 'Documentos',
                                            help:
                                                'Instrucciones y documentos vinculados a la operación.',
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: TabBarView(
                                        children: [
                                          _panel(
                                            'routing_operation_dependencies',
                                            'operation_id',
                                            'Dependencias',
                                            'Predecesores, tipo de dependencia, desfase y porcentaje mínimo de avance.',
                                          ),
                                          _panel(
                                            'routing_operation_materials',
                                            'routing_operation_id',
                                            'Materiales consumidos',
                                            'Relaciona componentes de la estructura de fabricación o materiales directos con el punto exacto de consumo.',
                                          ),
                                          _panel(
                                            'routing_operation_labor_requirements',
                                            'routing_operation_id',
                                            'Personal requerido',
                                            'Roles de personal, cantidad de personas y porcentaje de participación.',
                                          ),
                                          _panel(
                                            'routing_operation_machine_parameters',
                                            'routing_operation_id',
                                            'Parámetros de máquina',
                                            'Valores objetivo, mínimos, máximos y obligatoriedad para parámetros definidos en la máquina.',
                                          ),
                                          _panel(
                                            'routing_operation_checklists',
                                            'routing_operation_id',
                                            'Listas de verificación',
                                            'Plantillas de verificación que deben ejecutarse en esta operación.',
                                          ),
                                          _panel(
                                            'routing_operation_quality_checks',
                                            'routing_operation_id',
                                            'Controles de calidad',
                                            'Plantillas de calidad, orden, punto de ejecución y obligatoriedad.',
                                          ),
                                          _panel(
                                            'routing_operation_cost_components',
                                            'routing_operation_id',
                                            'Componentes de costo',
                                            'Costo de mano de obra, máquina, costos indirectos, subcontrato, fijo o fórmula.',
                                          ),
                                          _panel(
                                            'document_links',
                                            'routing_operation_id',
                                            'Documentos',
                                            'Instrucciones, fotografías de preparación, planos u otros documentos específicos de esta operación.',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );

  Widget _panel(String table, String fk, String title, String help) => Padding(
    padding: const EdgeInsets.all(14),
    child: operationId == null
        ? const Center(
            child: Text(
              'Selecciona una operación para configurar esta sección.',
              style: TextStyle(color: PomgtColors.muted),
            ),
          )
        : EntityCrudPanel(
            table: table,
            repository: widget.repository,
            lookups: widget.lookups,
            fixedValues: {fk: operationId},
            title: title,
            description: help,
            compact: true,
          ),
  );
}

class _RoutingResources extends StatelessWidget {
  const _RoutingResources({required this.repository, required this.lookups});
  final GenericRepository repository;
  final LookupRepository lookups;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    child: Column(
      children: [
        Container(
          color: PomgtColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: [
              HelpTab(
                label: 'Centros de trabajo',
                help: 'Áreas o estaciones donde se ejecutan operaciones.',
              ),
              HelpTab(
                label: 'Máquinas',
                help: 'Equipos disponibles y su centro de trabajo.',
              ),
              HelpTab(
                label: 'Parámetros',
                help: 'Variables configurables de las máquinas.',
              ),
              HelpTab(
                label: 'Roles',
                help: 'Roles de personal y costos estándar.',
              ),
              HelpTab(
                label: 'Procesos',
                help: 'Biblioteca de procesos estándar reutilizables.',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _p(
                'work_centers',
                'Centros de trabajo',
                'Áreas productivas con capacidad diaria y costo indirecto por hora.',
              ),
              _p(
                'machines',
                'Máquinas',
                'Equipos pertenecientes a un centro de trabajo con estado, fabricante, modelo y costos.',
              ),
              _p(
                'machine_parameter_definitions',
                'Parámetros de máquina',
                'Catálogo de variables configurables por equipo: velocidad, temperatura, presión, tensión, etc.',
              ),
              _p(
                'labor_roles',
                'Roles de personal',
                'Perfiles de trabajo utilizados por las rutas de fabricación para calcular capacidad y costo de mano de obra.',
              ),
              _p(
                'process_definitions',
                'Procesos estándar',
                'Biblioteca reusable de operaciones como impresión, corte, soldadura, inspección o empaque.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _p(String t, String title, String help) => Padding(
    padding: const EdgeInsets.all(20),
    child: EntityCrudPanel(
      table: t,
      repository: repository,
      lookups: lookups,
      title: title,
      description: help,
    ),
  );
}

class _RoutingTemplates extends StatelessWidget {
  const _RoutingTemplates({required this.repository, required this.lookups});
  final GenericRepository repository;
  final LookupRepository lookups;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Column(
      children: [
        Container(
          color: PomgtColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: [
              HelpTab(
                label: 'Listas de verificación',
                help:
                    'Plantillas reutilizables para validar tareas operativas.',
              ),
              HelpTab(
                label: 'Puntos de verificación',
                help: 'Preguntas o evidencias que componen una lista.',
              ),
              HelpTab(
                label: 'Calidad',
                help: 'Plantillas reutilizables de control de calidad.',
              ),
              HelpTab(
                label: 'Puntos de calidad',
                help:
                    'Mediciones o validaciones incluidas en una plantilla de calidad.',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              _p(
                'checklist_templates',
                'Plantillas de verificación',
                'Listas reutilizables para preparación, limpieza, seguridad o verificaciones operativas.',
              ),
              _p(
                'checklist_items',
                'Puntos de verificación',
                'Puntos y tipo de respuesta de cada plantilla. La secuencia se asigna automáticamente.',
              ),
              _p(
                'quality_check_templates',
                'Plantillas de calidad',
                'Conjuntos reutilizables de inspecciones para asociar a operaciones.',
              ),
              _p(
                'quality_check_items',
                'Puntos de calidad',
                'Mediciones, límites, unidad, valores permitidos, obligatoriedad y criticidad.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _p(String t, String title, String help) => Padding(
    padding: const EdgeInsets.all(20),
    child: EntityCrudPanel(
      table: t,
      repository: repository,
      lookups: lookups,
      title: title,
      description: help,
    ),
  );
}

class _KV extends StatelessWidget {
  const _KV(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: PomgtColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: PomgtColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _RoutingTitle extends StatelessWidget {
  const _RoutingTitle({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      final titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Rutas de fabricación',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const InfoTip(
                'Define la secuencia operativa, recursos, tiempos y controles para fabricar cada producto.',
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Define la secuencia operativa, recursos, tiempos y controles para fabricar cada producto.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: PomgtColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
      final button = FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(CupertinoIcons.add, size: 18),
        label: const Text('Nueva ruta'),
      );

      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 10), button],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: titleBlock),
          const SizedBox(width: 18),
          button,
        ],
      );
    },
  );
}

class _RoutingList extends StatelessWidget {
  const _RoutingList({
    required this.rows,
    required this.total,
    required this.selectedId,
    required this.search,
    required this.loading,
    required this.onSearch,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });
  final List<Map<String, dynamic>> rows;
  final int total;
  final String? selectedId;
  final String search;
  final bool loading;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onSelect;
  final Future<void> Function([Map<String, dynamic>?]) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => _RoutingPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextField(
                  onChanged: onSearch,
                  decoration: const InputDecoration(
                    hintText: 'Buscar rutas...',
                    prefixIcon: Icon(CupertinoIcons.search, size: 20),
                    prefixIconConstraints: BoxConstraints(minWidth: 46),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 18,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: onRefresh,
              icon: const Icon(CupertinoIcons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(child: _RoutingFilter('Todos los productos')),
            SizedBox(width: 8),
            Expanded(child: _RoutingFilter('Más recientes')),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '$total rutas',
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : rows.isEmpty
              ? const Center(
                  child: Text(
                    'Sin rutas.',
                    style: TextStyle(color: PomgtColors.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final selected = row['id']?.toString() == selectedId;
                    return InkWell(
                      borderRadius: PomgtRadii.borderSm,
                      onTap: () => onSelect(row['id']?.toString()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? PomgtColors.navySelected
                              : PomgtColors.canvas,
                          borderRadius: PomgtRadii.borderSm,
                          border: Border.all(
                            color: selected
                                ? PomgtColors.navySelectedBorder
                                : PomgtColors.line,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 30,
                              height: 30,
                              child: Icon(
                                CupertinoIcons.arrow_branch,
                                size: 17,
                                color: PomgtColors.ink,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row['routing_code']?.toString() ?? 'RUT',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    row['name']?.toString() ??
                                        'Ruta de fabricación',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    row['is_active'] == true
                                        ? 'Activa'
                                        : 'Inactiva',
                                    style: const TextStyle(
                                      color: PomgtColors.muted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Acciones',
                              padding: EdgeInsets.zero,
                              onSelected: (value) {
                                if (value == 'edit') onEdit(row);
                                if (value == 'delete') onDelete(row);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(CupertinoIcons.pencil, size: 17),
                                      SizedBox(width: 9),
                                      Text('Editar'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.trash,
                                        size: 17,
                                        color: PomgtColors.danger,
                                      ),
                                      SizedBox(width: 9),
                                      Text(
                                        'Eliminar',
                                        style: TextStyle(
                                          color: PomgtColors.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  CupertinoIcons.ellipsis_vertical,
                                  size: 17,
                                  color: PomgtColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _RoutingFilter extends StatelessWidget {
  const _RoutingFilter(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    height: 35,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(border: Border.all(color: PomgtColors.line)),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: PomgtColors.secondaryInk,
            ),
          ),
        ),
        const Icon(CupertinoIcons.chevron_down, size: 12),
      ],
    ),
  );
}

class _RoutingOverview extends StatelessWidget {
  const _RoutingOverview({
    super.key,
    required this.routing,
    required this.onEdit,
  });
  final Map<String, dynamic> routing;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = routing['id'].toString();
    return FutureBuilder<Map<String, dynamic>>(
      future: _load(generic, lookups, id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        final data = snapshot.data ?? const <String, dynamic>{};
        final revisions =
            data['revisions'] as List<Map<String, dynamic>>? ?? const [];
        final revision = revisions.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['status'] == 'active',
          orElse: () => revisions.isEmpty ? null : revisions.first,
        );
        final operations =
            data['operations'] as List<Map<String, dynamic>>? ?? const [];
        final products =
            data['products'] as List<Map<String, dynamic>>? ?? const [];
        final workCenters =
            data['workCenters'] as List<Map<String, dynamic>>? ?? const [];
        final processes =
            data['processes'] as List<Map<String, dynamic>>? ?? const [];
        return SingleChildScrollView(
          child: Column(
            children: [
              _RoutingHero(routing: routing, onEdit: onEdit),
              const SizedBox(height: 12),
              _RoutingKpis(
                revision: revision,
                operations: operations,
                quality: data['quality']?.length ?? 0,
                documents: data['documents']?.length ?? 0,
              ),
              const SizedBox(height: 12),
              _RoutingSequence(
                rows: operations,
                workCenters: workCenters,
                processes: processes,
                lookups: lookups,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final first = Column(
                    children: [
                      _RoutingSummaryCard(
                        routing: routing,
                        revision: revision,
                        products: products,
                        lookups: lookups,
                      ),
                      const SizedBox(height: 12),
                      _RoutingParameters(rows: operations),
                    ],
                  );
                  final second = Column(
                    children: [
                      _RoutingResourcesCard(
                        rows: operations,
                        workCenters: workCenters,
                        lookups: lookups,
                      ),
                      const SizedBox(height: 12),
                      _RoutingDocuments(rows: data['documents'] ?? const []),
                    ],
                  );
                  final third = Column(
                    children: [
                      _RoutingMaterials(
                        rows: data['materials'] ?? const [],
                        products: products,
                        lookups: lookups,
                      ),
                      const SizedBox(height: 12),
                      _RoutingAlerts(rows: data['alerts'] ?? const []),
                      const SizedBox(height: 12),
                      _RoutingActivity(rows: operations),
                    ],
                  );
                  if (constraints.maxWidth < 860) {
                    return Column(
                      children: [
                        first,
                        const SizedBox(height: 12),
                        second,
                        const SizedBox(height: 12),
                        third,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: first),
                      const SizedBox(width: 12),
                      Expanded(flex: 4, child: second),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: third),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _RoutingActions(routing: routing),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _load(
    GenericRepository generic,
    LookupRepository lookups,
    String id,
  ) async {
    final revisions = await generic.listRows(
      Phase1Schema.tables['routing_revisions']!,
      filters: {'routing_id': id},
    );
    final active = revisions.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['status'] == 'active',
      orElse: () => revisions.isEmpty ? null : revisions.first,
    );
    final operations = active == null
        ? <Map<String, dynamic>>[]
        : await generic.listRows(
            Phase1Schema.tables['routing_operations']!,
            filters: {'routing_revision_id': active['id']},
          );
    final results = await Future.wait([
      generic.listRows(
        Phase1Schema.tables['routing_operation_materials']!,
        filters: {
          'routing_operation_id': operations.isEmpty
              ? ''
              : operations.first['id'],
        },
      ),
      generic.listRows(
        Phase1Schema.tables['routing_operation_quality_checks']!,
        filters: {
          'routing_operation_id': operations.isEmpty
              ? ''
              : operations.first['id'],
        },
      ),
      generic.listRows(
        Phase1Schema.tables['document_links']!,
        filters: {'routing_revision_id': active?['id'] ?? ''},
      ),
      generic.listRows(
        Phase1Schema.tables['nonconformities']!,
        filters: {'product_id': routing['product_id']},
      ),
    ]);
    return {
      'revisions': revisions,
      'operations': operations,
      'materials': results[0],
      'quality': results[1],
      'documents': results[2],
      'alerts': results[3],
      'products': await lookups.rows('products'),
      'workCenters': await lookups.rows('work_centers'),
      'processes': await lookups.rows('process_definitions'),
    };
  }
}

class _RoutingHero extends StatelessWidget {
  const _RoutingHero({required this.routing, required this.onEdit});
  final Map<String, dynamic> routing;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => _RoutingPanel(
    padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 9,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Text(
                      routing['name']?.toString() ?? 'Ruta de fabricación',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: PomgtColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  _RouteStatus(active: routing['is_active'] == true),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${routing['routing_code'] ?? '—'} · Producto asociado · Ruta predeterminada: ${routing['is_default'] == true ? 'Sí' : 'No'}',
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(CupertinoIcons.pencil, size: 16),
            label: const Text('Editar ruta'),
          ),
        ),
      ],
    ),
  );
}

class _RouteStatus extends StatelessWidget {
  const _RouteStatus({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: active ? PomgtColors.mint : PomgtColors.danger,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        active ? 'Activa' : 'Inactiva',
        style: TextStyle(
          color: active ? PomgtColors.mint : PomgtColors.danger,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

String _routeLookupDisplay(
  List<Map<String, dynamic>> rows,
  dynamic id,
  DbTableSpec spec,
  LookupRepository lookups, {
  required String fallback,
}) {
  final key = id?.toString();
  if (key == null || key.trim().isEmpty) return fallback;
  final matches = rows.where((row) => row['id']?.toString() == key);
  if (matches.isEmpty) return fallback;
  return lookups.display(spec, matches.first);
}

class _RoutingKpis extends StatelessWidget {
  const _RoutingKpis({
    required this.revision,
    required this.operations,
    required this.quality,
    required this.documents,
  });
  final Map<String, dynamic>? revision;
  final List<Map<String, dynamic>> operations;
  final int quality;
  final int documents;
  @override
  Widget build(BuildContext context) {
    final setup = operations.fold<num>(
      0,
      (sum, row) => sum + ((row['setup_time_minutes'] as num?) ?? 0),
    );
    final cycle = operations.fold<num>(
      0,
      (sum, row) => sum + ((row['run_time_value'] as num?) ?? 0),
    );
    final items = [
      ('Operaciones', '${operations.length}', CupertinoIcons.list_number),
      ('Tiempo setup total', '${setup.round()} min', CupertinoIcons.timer),
      (
        'Tiempo ciclo est.',
        '${cycle.toStringAsFixed(1)} h',
        CupertinoIcons.clock,
      ),
      (
        'Centros de trabajo',
        '${operations.map((r) => r['work_center_id']).where((v) => v != null).toSet().length}',
        CupertinoIcons.building_2_fill,
      ),
      ('Materiales ligados', '—', CupertinoIcons.cube_box),
      ('Controles de calidad', '$quality', CupertinoIcons.checkmark_seal),
      ('Documentos', '$documents', CupertinoIcons.doc_text),
      (
        'Última actualización',
        revision?['updated_at']?.toString().split('T').first ?? '—',
        CupertinoIcons.calendar,
      ),
    ];
    return SizedBox(
      width: double.infinity,
      child: _RoutingPanel(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final rows = <Widget>[];
            for (var start = 0; start < items.length; start += columns) {
              final end = (start + columns).clamp(0, items.length);
              rows.add(
                Row(
                  children: [
                    for (var i = start; i < end; i++)
                      Expanded(
                        child: _RouteKpi(
                          items[i].$1,
                          items[i].$2,
                          items[i].$3,
                          (i - start) != columns - 1,
                        ),
                      ),
                    for (var i = end; i < start + columns; i++) const Spacer(),
                  ],
                ),
              );
              if (end < items.length) rows.add(const SizedBox(height: 8));
            }
            return Column(children: rows);
          },
        ),
      ),
    );
  }
}

class _RouteKpi extends StatelessWidget {
  const _RouteKpi(this.label, this.value, this.icon, this.divider);
  final String label;
  final String value;
  final IconData icon;
  final bool divider;
  @override
  Widget build(BuildContext context) => Container(
    height: 55,
    padding: const EdgeInsets.symmetric(horizontal: 11),
    decoration: BoxDecoration(
      border: Border(
        right: divider
            ? const BorderSide(color: PomgtColors.line)
            : BorderSide.none,
      ),
    ),
    child: Row(
      children: [
        Icon(icon, color: PomgtColors.blue, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RoutingSequence extends StatelessWidget {
  const _RoutingSequence({
    required this.rows,
    required this.workCenters,
    required this.processes,
    required this.lookups,
  });
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> workCenters;
  final List<Map<String, dynamic>> processes;
  final LookupRepository lookups;
  @override
  Widget build(BuildContext context) {
    final child = rows.isEmpty
        ? const SizedBox(
            height: 110,
            child: Center(
              child: Text(
                'Agrega operaciones a la revisión activa.',
                style: TextStyle(color: PomgtColors.muted),
              ),
            ),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < rows.length && i < 8; i++) ...[
                  _OperationCard(
                    index: i,
                    row: rows[i],
                    workCenters: workCenters,
                    processes: processes,
                    lookups: lookups,
                  ),
                  if (i < rows.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7),
                      child: Icon(
                        CupertinoIcons.arrow_right,
                        size: 16,
                        color: PomgtColors.blue,
                      ),
                    ),
                ],
              ],
            ),
          );
    return _RoutingSection(
      title: 'Secuencia de operaciones',
      link: rows.isEmpty ? null : 'Ver diagrama completo',
      child: child,
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.index,
    required this.row,
    required this.workCenters,
    required this.processes,
    required this.lookups,
  });
  final int index;
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> workCenters;
  final List<Map<String, dynamic>> processes;
  final LookupRepository lookups;

  String _workCenterName(dynamic id) => _routeLookupDisplay(
    workCenters,
    id,
    Phase1Schema.tables['work_centers']!,
    lookups,
    fallback: '—',
  );

  String _processName(dynamic id) => _routeLookupDisplay(
    processes,
    id,
    Phase1Schema.tables['process_definitions']!,
    lookups,
    fallback: '—',
  );

  @override
  Widget build(BuildContext context) => Container(
    width: 145,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: PomgtColors.canvas,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .65)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 11,
              backgroundColor: PomgtColors.blue,
              child: Text(
                '${row['sequence_no'] ?? (index + 1) * 10}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Spacer(),
            Icon(CupertinoIcons.doc_text, size: 14, color: PomgtColors.muted),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          row['name']?.toString() ?? 'Operación',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        _RouteSmall('CT', _workCenterName(row['work_center_id'])),
        _RouteSmall('Setup', '${row['setup_time_minutes'] ?? 0} min'),
        _RouteSmall('Tiempo', '${row['run_time_value'] ?? 0}'),
        _RouteSmall('Resp.', _processName(row['process_definition_id'])),
      ],
    ),
  );
}

class _RoutingSummaryCard extends StatelessWidget {
  const _RoutingSummaryCard({
    required this.routing,
    required this.revision,
    required this.products,
    required this.lookups,
  });
  final Map<String, dynamic> routing;
  final Map<String, dynamic>? revision;
  final List<Map<String, dynamic>> products;
  final LookupRepository lookups;

  String _productName(dynamic id) => _routeLookupDisplay(
    products,
    id,
    Phase1Schema.tables['products']!,
    lookups,
    fallback: '—',
  );

  @override
  Widget build(BuildContext context) => _RoutingSection(
    title: 'Resumen de la ruta',
    link: 'Editar',
    child: Column(
      children: [
        _RouteLine('Código', routing['routing_code']?.toString() ?? '—'),
        _RouteLine('Producto', _productName(routing['product_id'])),
        _RouteLine('Versión', revision?['revision_code']?.toString() ?? '—'),
        _RouteLine(
          'Revisión activa',
          UiCopy.enumLabel(revision?['status']?.toString() ?? '—'),
        ),
        _RouteLine('Tipo de proceso', 'Fabricación'),
        _RouteLine(
          'Predeterminada',
          routing['is_default'] == true ? 'Sí' : 'No',
        ),
        if (routing['description'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              routing['description'].toString(),
              style: const TextStyle(
                color: PomgtColors.secondaryInk,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
      ],
    ),
  );
}

class _RoutingResourcesCard extends StatelessWidget {
  const _RoutingResourcesCard({
    required this.rows,
    required this.workCenters,
    required this.lookups,
  });
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> workCenters;
  final LookupRepository lookups;

  String _workCenterName(dynamic id) => _routeLookupDisplay(
    workCenters,
    id,
    Phase1Schema.tables['work_centers']!,
    lookups,
    fallback: '—',
  );

  @override
  Widget build(BuildContext context) => _RoutingSection(
    title: 'Recursos y tiempos',
    link: 'Ver detalles',
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 620,
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(.6),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(.8),
            4: FlexColumnWidth(.8),
          },
          children: [
            _routeHeader(['Op.', 'Operación', 'Centro', 'Setup', 'Tiempo']),
            for (final row in rows.take(6))
              _routeRow([
                row['sequence_no']?.toString() ?? '—',
                row['name']?.toString() ?? '—',
                _workCenterName(row['work_center_id']),
                '${row['setup_time_minutes'] ?? 0} min',
                '${row['run_time_value'] ?? 0}',
              ]),
          ],
        ),
      ),
    ),
  );
}

class _RoutingMaterials extends StatelessWidget {
  const _RoutingMaterials({
    required this.rows,
    required this.products,
    required this.lookups,
  });
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> products;
  final LookupRepository lookups;

  String _productName(dynamic id) => _routeLookupDisplay(
    products,
    id,
    Phase1Schema.tables['products']!,
    lookups,
    fallback: 'Material',
  );

  @override
  Widget build(BuildContext context) => _RoutingSection(
    title: 'Materiales por operación',
    link: rows.isEmpty ? null : 'Ver todos',
    child: rows.isEmpty
        ? const Text(
            'Sin materiales ligados.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: [
              for (final row in rows.take(5))
                _RouteLine(
                  row['consumption_point']?.toString() ?? 'Material',
                  _productName(row['material_product_id']),
                ),
            ],
          ),
  );
}

class _RoutingParameters extends StatelessWidget {
  const _RoutingParameters({required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  Widget build(BuildContext context) => _RoutingSection(
    title: 'Parámetros y controles',
    link: rows.isEmpty ? null : 'Ver todos',
    child: rows.isEmpty
        ? const Text(
            'Sin parámetros registrados.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: [
              for (final row in rows.take(5))
                _RouteLine(
                  row['name']?.toString() ?? 'Operación',
                  row['requires_quality'] == true
                      ? 'Control de calidad'
                      : 'Sin control especial',
                ),
            ],
          ),
  );
}

class _RoutingDocuments extends StatelessWidget {
  const _RoutingDocuments({required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  Widget build(BuildContext context) => _RoutingSection(
    title: 'Documentos recientes',
    link: rows.isEmpty ? null : 'Ver todos',
    child: rows.isEmpty
        ? const Text(
            'Sin documentos ligados.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: [
              for (final row in rows.take(4))
                _RouteLine(
                  row['purpose']?.toString() ?? 'Documento',
                  row['created_at']?.toString().split('T').first ?? '—',
                ),
            ],
          ),
  );
}

class _RoutingAlerts extends StatelessWidget {
  const _RoutingAlerts({required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  Widget build(BuildContext context) => _RoutingSection(
    title: 'Alertas de la ruta',
    link: rows.isEmpty ? null : 'Ver todas',
    child: rows.isEmpty
        ? const _RouteLine(
            'Sin alertas activas',
            'Ruta sin incidencias',
            color: PomgtColors.mint,
          )
        : Column(
            children: [
              for (final row in rows.take(4))
                _RouteLine(
                  row['nc_number']?.toString() ?? 'No conformidad',
                  row['description']?.toString() ??
                      UiCopy.enumLabel(row['status']?.toString() ?? ''),
                  color: PomgtColors.amber,
                ),
            ],
          ),
  );
}

class _RoutingActivity extends StatelessWidget {
  const _RoutingActivity({required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  Widget build(BuildContext context) => _RoutingSection(
    title: 'Actividad reciente',
    link: rows.isEmpty ? null : 'Ver todas',
    child: rows.isEmpty
        ? const Text(
            'Sin actividad reciente.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: [
              for (final row in rows.take(4))
                _RouteLine(
                  row['name']?.toString() ?? 'Operación',
                  'Se modificó la operación',
                ),
            ],
          ),
  );
}

class _RoutingActions extends StatefulWidget {
  const _RoutingActions({required this.routing});
  final Map<String, dynamic> routing;

  @override
  State<_RoutingActions> createState() => _RoutingActionsState();
}

class _RoutingActionsState extends State<_RoutingActions> {
  late Future<_RouteSequenceData> _future;
  String? _revisionId;
  String? _operationId;

  String get _routingId => widget.routing['id'].toString();
  String? get _productId => widget.routing['product_id']?.toString();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RouteSequenceData> _load() async {
    final generic = context.read<GenericRepository>();
    final revisions = await generic.listRows(
      Phase1Schema.tables['routing_revisions']!,
      filters: {'routing_id': _routingId},
    );
    final selectedRevision = revisions.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['id']?.toString() == _revisionId,
      orElse: () => revisions.cast<Map<String, dynamic>?>().firstWhere(
        (row) => row?['status'] == 'active',
        orElse: () => revisions.isEmpty ? null : revisions.first,
      ),
    );
    final operations = selectedRevision == null
        ? <Map<String, dynamic>>[]
        : await generic.listRows(
            Phase1Schema.tables['routing_operations']!,
            filters: {'routing_revision_id': selectedRevision['id']},
          );
    final boms = _productId == null
        ? <Map<String, dynamic>>[]
        : await generic.listRows(
            Phase1Schema.tables['boms']!,
            filters: {'product_id': _productId},
          );
    final bom = boms.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['is_default'] == true,
      orElse: () => boms.isEmpty ? null : boms.first,
    );
    final bomRevisions = bom == null
        ? <Map<String, dynamic>>[]
        : await generic.listRows(
            Phase1Schema.tables['bom_revisions']!,
            filters: {'bom_id': bom['id']},
          );
    final bomRevision = bomRevisions.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['status'] == 'active',
      orElse: () => bomRevisions.isEmpty ? null : bomRevisions.first,
    );
    final bomItems = bomRevision == null
        ? <Map<String, dynamic>>[]
        : await generic.listRows(
            Phase1Schema.tables['bom_items']!,
            filters: {'bom_revision_id': bomRevision['id']},
          );
    return _RouteSequenceData(
      revisions: revisions,
      selectedRevision: selectedRevision,
      operations: operations,
      bomRevision: bomRevision,
      bomItems: bomItems,
    );
  }

  void _reload() {
    _future = _load();
    if (mounted) setState(() {});
  }

  Future<void> _editRevision([Map<String, dynamic>? revision]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['routing_revisions']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        original: revision,
        fixedValues: {'routing_id': _routingId},
        title: revision == null ? 'Nueva revisión de ruta' : 'Editar revisión',
        icon: CupertinoIcons.doc_text,
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _editOperation([
    Map<String, dynamic>? operation,
    String? revisionId,
    List<Map<String, dynamic>> bomItems = const [],
    Map<String, dynamic>? bomRevision,
  ]) async {
    final targetRevisionId = revisionId ?? _revisionId;
    if (targetRevisionId == null) return;
    final selectedBomItemIds = <String>{};
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['routing_operations']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        original: operation,
        fixedValues: {'routing_revision_id': targetRevisionId},
        hiddenFields: const {'operation_code', 'currency_code'},
        title: operation == null
            ? 'Nuevo paso de fabricación'
            : 'Editar paso de fabricación',
        description:
            'Define el título, descripción, tipo de paso, recursos, tiempos y controles. Los materiales se asignan en la secuencia del paso.',
        icon: _stepIcon(operation?['operation_type']?.toString()),
        extraContentBuilder: operation == null
            ? (dialogContext, values) {
                if (values['operation_type'] != 'material') return null;
                return _OperationMaterialDraftPicker(
                  bomRevision: bomRevision,
                  bomItems: bomItems,
                  selectedBomItemIds: selectedBomItemIds,
                  onChanged: (next) {
                    selectedBomItemIds
                      ..clear()
                      ..addAll(next);
                  },
                );
              }
            : null,
        afterSaved: operation == null
            ? (saved) async {
                if (saved['operation_type'] != 'material' ||
                    selectedBomItemIds.isEmpty) {
                  return;
                }
                final itemsById = {
                  for (final item in bomItems) item['id']?.toString(): item,
                };
                final repository = context.read<GenericRepository>();
                for (final id in selectedBomItemIds) {
                  final item = itemsById[id];
                  if (item == null) continue;
                  await repository.createRow(
                    Phase1Schema.tables['routing_operation_materials']!,
                    {
                      'routing_operation_id': saved['id'],
                      'bom_item_id': item['id'],
                      'material_product_id': item['component_product_id'],
                      'quantity_override': item['quantity'],
                      'uom_id': item['uom_id'],
                      'consumption_point': 'during',
                    },
                  );
                }
              }
            : null,
      ),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => _RoutingPanel(
    padding: EdgeInsets.zero,
    child: FutureBuilder<_RouteSequenceData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const SizedBox(
            height: 430,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        final data = snapshot.data ?? const _RouteSequenceData();
        final revisions = data.revisions;
        if (revisions.isEmpty)
          return SizedBox(
            height: 360,
            child: _EmptyRouteSetup(onCreateRevision: () => _editRevision()),
          );
        final selectedRevision = data.selectedRevision ?? revisions.first;
        _revisionId = selectedRevision['id']?.toString();
        final operations = [...data.operations]
          ..sort(
            (a, b) => ((a['sequence_no'] as num?)?.toInt() ?? 0).compareTo(
              ((b['sequence_no'] as num?)?.toInt() ?? 0),
            ),
          );
        if (operations.isNotEmpty &&
            (_operationId == null ||
                !operations.any(
                  (row) => row['id']?.toString() == _operationId,
                ))) {
          _operationId = operations.first['id']?.toString();
        }
        final selectedOperation = operations
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (row) => row?['id']?.toString() == _operationId,
              orElse: () => operations.isEmpty ? null : operations.first,
            );

        return SizedBox(
          height: 560,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 220,
                        maxWidth: 430,
                      ),
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Secuencia de fabricación',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const InfoTip(
                            'La ruta ordena qué operaciones se ejecutan, qué recursos usan y en qué paso se consumen los materiales de la estructura.',
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<String>(
                        initialValue: _revisionId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Revisión',
                        ),
                        items: revisions
                            .map(
                              (row) => DropdownMenuItem(
                                value: row['id'].toString(),
                                child: Text(
                                  '${row['revision_code']} · ${UiCopy.enumLabel(row['status']?.toString() ?? '')}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          _revisionId = value;
                          _operationId = null;
                          _reload();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: () => _editRevision(selectedRevision),
                      icon: const Icon(CupertinoIcons.pencil, size: 15),
                      label: const Text('Editar revisión'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: () => _editOperation(
                        null,
                        _revisionId,
                        data.bomItems,
                        data.bomRevision,
                      ),
                      icon: const Icon(CupertinoIcons.add, size: 17),
                      label: const Text('Agregar paso'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final list = _StepList(
                      operations: operations,
                      selectedId: selectedOperation?['id']?.toString(),
                      onSelect: (id) => setState(() => _operationId = id),
                      onEdit: _editOperation,
                    );
                    final detail = selectedOperation == null
                        ? _EmptyStepList(
                            onCreate: () => _editOperation(
                              null,
                              _revisionId,
                              data.bomItems,
                              data.bomRevision,
                            ),
                          )
                        : _StepDetail(
                            key: ValueKey(selectedOperation['id']),
                            operation: selectedOperation,
                            routingProductId: _productId,
                            bomRevision: data.bomRevision,
                            bomItems: data.bomItems,
                            onEdit: () =>
                                _editOperation(selectedOperation, _revisionId),
                            onChanged: _reload,
                          );
                    if (constraints.maxWidth < 780) {
                      final listHeight = constraints.maxHeight < 520
                          ? 170.0
                          : 220.0;
                      return Column(
                        children: [
                          SizedBox(height: listHeight, child: list),
                          const Divider(height: 1),
                          Expanded(child: detail),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: 330, child: list),
                        const VerticalDivider(width: 1),
                        Expanded(child: detail),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _RouteSequenceData {
  const _RouteSequenceData({
    this.revisions = const [],
    this.selectedRevision,
    this.operations = const [],
    this.bomRevision,
    this.bomItems = const [],
  });
  final List<Map<String, dynamic>> revisions;
  final Map<String, dynamic>? selectedRevision;
  final List<Map<String, dynamic>> operations;
  final Map<String, dynamic>? bomRevision;
  final List<Map<String, dynamic>> bomItems;
}

class _EmptyRouteSetup extends StatelessWidget {
  const _EmptyRouteSetup({required this.onCreateRevision});
  final VoidCallback onCreateRevision;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(CupertinoIcons.doc_text, size: 34, color: PomgtColors.ink),
        const SizedBox(height: 14),
        const Text(
          'Primero crea una revisión de ruta',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cada revisión contiene la secuencia completa de fabricación.',
          style: TextStyle(color: PomgtColors.muted),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onCreateRevision,
          icon: const Icon(CupertinoIcons.add, size: 17),
          label: const Text('Crear revisión'),
        ),
      ],
    ),
  );
}

class _StepList extends StatelessWidget {
  const _StepList({
    required this.operations,
    required this.selectedId,
    required this.onSelect,
    required this.onEdit,
  });
  final List<Map<String, dynamic>> operations;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final void Function(Map<String, dynamic>, String?) onEdit;
  @override
  Widget build(BuildContext context) {
    if (operations.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Esta revisión aún no tiene pasos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: PomgtColors.muted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: operations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = operations[index];
        final selected = row['id']?.toString() == selectedId;
        return InkWell(
          onTap: () => onSelect(row['id']?.toString()),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? PomgtColors.navySelected : PomgtColors.canvas,
              borderRadius: PomgtRadii.borderSm,
              border: Border.all(
                color: selected
                    ? PomgtColors.navySelectedBorder
                    : PomgtColors.line,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${row['sequence_no'] ?? (index + 1) * 10}',
                      style: const TextStyle(
                        color: PomgtColors.blue,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _stepIcon(row['operation_type']?.toString()),
                              size: 15,
                              color: _stepColor(
                                row['operation_type']?.toString(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                row['name']?.toString() ?? 'Paso sin título',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: PomgtColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _stepTypeLabel(row['operation_type']?.toString()),
                          style: TextStyle(
                            color: _stepColor(
                              row['operation_type']?.toString(),
                            ),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if ((row['description']?.toString() ?? '')
                            .isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            row['description'].toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PomgtColors.muted,
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar paso',
                    onPressed: () =>
                        onEdit(row, row['routing_revision_id']?.toString()),
                    icon: const Icon(CupertinoIcons.pencil, size: 16),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyStepList extends StatelessWidget {
  const _EmptyStepList({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          CupertinoIcons.list_number,
          size: 34,
          color: PomgtColors.ink,
        ),
        const SizedBox(height: 14),
        const Text(
          'Agrega la primera operación',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ejemplo: 10 Preprensa, 20 Impresión, 30 Corte, 40 Empaque.',
          style: TextStyle(color: PomgtColors.muted),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(CupertinoIcons.add, size: 17),
          label: const Text('Agregar paso'),
        ),
      ],
    ),
  );
}

class _StepDetail extends StatelessWidget {
  const _StepDetail({
    super.key,
    required this.operation,
    required this.routingProductId,
    required this.bomRevision,
    required this.bomItems,
    required this.onEdit,
    required this.onChanged,
  });
  final Map<String, dynamic> operation;
  final String? routingProductId;
  final Map<String, dynamic>? bomRevision;
  final List<Map<String, dynamic>> bomItems;
  final VoidCallback onEdit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        lookups.rows('work_centers'),
        lookups.rows('machines'),
      ]),
      builder: (context, snapshot) {
        final data =
            snapshot.data ??
            const [<Map<String, dynamic>>[], <Map<String, dynamic>>[]];
        final workCenterName = _routeLookupDisplay(
          data[0],
          operation['work_center_id'],
          Phase1Schema.tables['work_centers']!,
          lookups,
          fallback: 'Sin asignar',
        );
        final machineName = _routeLookupDisplay(
          data[1],
          operation['preferred_machine_id'],
          Phase1Schema.tables['machines']!,
          lookups,
          fallback: 'Sin asignar',
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _stepIcon(operation['operation_type']?.toString()),
                    color: _stepColor(operation['operation_type']?.toString()),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${operation['sequence_no'] ?? '—'} · ${operation['name'] ?? 'Paso de fabricación'}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _stepTypeLabel(
                            operation['operation_type']?.toString(),
                          ),
                          style: TextStyle(
                            color: _stepColor(
                              operation['operation_type']?.toString(),
                            ),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(CupertinoIcons.pencil, size: 15),
                    label: const Text('Editar paso'),
                  ),
                ],
              ),
              if ((operation['description']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  operation['description'].toString(),
                  style: const TextStyle(
                    color: PomgtColors.secondaryInk,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _StepFact('Centro de trabajo', workCenterName),
                  _StepFact('Máquina', machineName),
                  _StepFact(
                    'Setup',
                    '${operation['setup_time_minutes'] ?? 0} min',
                  ),
                  _StepFact(
                    'Tiempo estimado',
                    '${operation['run_time_value'] ?? '—'}',
                  ),
                  _StepFact(
                    'Merma esperada',
                    '${operation['expected_scrap_pct'] ?? 0}%',
                  ),
                  _StepFact(
                    'Rendimiento',
                    '${operation['expected_yield_pct'] ?? 100}%',
                  ),
                ],
              ),
              if ((operation['instructions']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 18),
                _RoutingSection(
                  title: 'Instrucciones del paso',
                  child: Text(
                    operation['instructions'].toString(),
                    style: const TextStyle(
                      color: PomgtColors.secondaryInk,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _StepMaterialManager(
                operation: operation,
                routingProductId: routingProductId,
                bomRevision: bomRevision,
                bomItems: bomItems,
                onChanged: onChanged,
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _StepRelatedPanel(
                      table: 'routing_operation_checklists',
                      fixedValues: {'routing_operation_id': operation['id']},
                      title: 'Verificaciones del paso',
                      description:
                          'Listas que el operador debe completar en esta operación.',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _StepRelatedPanel(
                      table: 'routing_operation_quality_checks',
                      fixedValues: {'routing_operation_id': operation['id']},
                      title: 'Controles de calidad',
                      description:
                          'Mediciones o aprobaciones necesarias para liberar el paso.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StepFact extends StatelessWidget {
  const _StepFact(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _StepMaterialManager extends StatefulWidget {
  const _StepMaterialManager({
    required this.operation,
    required this.routingProductId,
    required this.bomRevision,
    required this.bomItems,
    required this.onChanged,
  });
  final Map<String, dynamic> operation;
  final String? routingProductId;
  final Map<String, dynamic>? bomRevision;
  final List<Map<String, dynamic>> bomItems;
  final VoidCallback onChanged;

  @override
  State<_StepMaterialManager> createState() => _StepMaterialManagerState();
}

class _StepMaterialManagerState extends State<_StepMaterialManager> {
  late Future<List<Map<String, dynamic>>> _assignedFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _assignedFuture = context.read<GenericRepository>().listRows(
      Phase1Schema.tables['routing_operation_materials']!,
      filters: {'routing_operation_id': widget.operation['id']},
    );
    if (mounted) setState(() {});
  }

  Future<void> _addBomItem(Map<String, dynamic> item) async {
    await context
        .read<GenericRepository>()
        .createRow(Phase1Schema.tables['routing_operation_materials']!, {
          'routing_operation_id': widget.operation['id'],
          'bom_item_id': item['id'],
          'material_product_id': item['component_product_id'],
          'quantity_override': item['quantity'],
          'uom_id': item['uom_id'],
          'consumption_point': widget.operation['operation_type'] == 'packaging'
              ? 'finish'
              : 'during',
        });
    if (!mounted) return;
    _reload();
    widget.onChanged();
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    await context.read<GenericRepository>().deleteRow(
      Phase1Schema.tables['routing_operation_materials']!,
      row,
    );
    if (!mounted) return;
    _reload();
    widget.onChanged();
  }

  Future<void> _addDirect() async {
    final filters = <String, Map<String, dynamic>>{};
    if (widget.bomRevision != null) {
      filters['bom_item_id'] = {'bom_revision_id': widget.bomRevision!['id']};
    }
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['routing_operation_materials']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        fixedValues: {'routing_operation_id': widget.operation['id']},
        referenceFilters: filters,
        title: 'Asignar material al paso',
        description:
            'Relaciona un componente de la estructura o un material directo con este paso concreto.',
        icon: CupertinoIcons.cube_box,
      ),
    );
    if (changed == true && mounted) {
      _reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return _RoutingSection(
      title: 'Materiales usados en este paso',
      link:
          'estructura ${widget.bomRevision?['revision_code'] ?? 'sin revisión'}',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _assignedFuture,
        builder: (context, snapshot) {
          final assigned = snapshot.data ?? const <Map<String, dynamic>>[];
          final assignedBomIds = assigned
              .map((row) => row['bom_item_id']?.toString())
              .whereType<String>()
              .toSet();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.operation['operation_type'] == 'material' ||
                        widget.operation['operation_type'] == 'packaging'
                    ? 'Este paso puede consumir uno o varios componentes de la estructura del producto.'
                    : 'Opcional: asigna materiales si esta actividad consume algo físicamente.',
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.bomItems.isEmpty)
                const Text(
                  'El producto de esta ruta no tiene componentes en una estructura activa o seleccionable.',
                  style: TextStyle(color: PomgtColors.muted),
                )
              else
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: lookups.rows('products'),
                  builder: (context, productSnapshot) {
                    final productRows =
                        productSnapshot.data ?? const <Map<String, dynamic>>[];
                    final productById = {
                      for (final product in productRows)
                        product['id']?.toString(): product,
                    };
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in widget.bomItems)
                          _BomMaterialButton(
                            label: _bomItemLabel(item, productById),
                            selected: assignedBomIds.contains(
                              item['id']?.toString(),
                            ),
                            onPressed:
                                assignedBomIds.contains(item['id']?.toString())
                                ? null
                                : () => _addBomItem(item),
                          ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(minHeight: 2)
              else if (assigned.isEmpty)
                const Text(
                  'Sin materiales asignados a este paso.',
                  style: TextStyle(color: PomgtColors.muted),
                )
              else
                Column(
                  children: [
                    for (final row in assigned)
                      _AssignedMaterialRow(
                        row: row,
                        onRemove: () => _remove(row),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addDirect,
                  icon: const Icon(CupertinoIcons.add, size: 16),
                  label: const Text('Agregar material manual'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _bomItemLabel(
    Map<String, dynamic> item,
    Map<String?, Map<String, dynamic>> productById,
  ) {
    final product = productById[item['component_product_id']?.toString()];
    final name = product == null
        ? 'Material'
        : context.read<LookupRepository>().display(
            Phase1Schema.tables['products']!,
            product,
          );
    final qty = item['quantity'] == null ? '' : ' · ${item['quantity']}';
    return '${item['line_no'] ?? '—'} · $name$qty';
  }
}

class _OperationMaterialDraftPicker extends StatefulWidget {
  const _OperationMaterialDraftPicker({
    required this.bomRevision,
    required this.bomItems,
    required this.selectedBomItemIds,
    required this.onChanged,
  });
  final Map<String, dynamic>? bomRevision;
  final List<Map<String, dynamic>> bomItems;
  final Set<String> selectedBomItemIds;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_OperationMaterialDraftPicker> createState() =>
      _OperationMaterialDraftPickerState();
}

class _OperationMaterialDraftPickerState
    extends State<_OperationMaterialDraftPicker> {
  late final Set<String> _selected = {...widget.selectedBomItemIds};

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
    widget.onChanged(Set.unmodifiable(_selected));
  }

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .7)),
        color: PomgtColors.canvas,
        borderRadius: PomgtRadii.borderMd,
        boxShadow: PomgtShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  CupertinoIcons.cube_box,
                  size: 18,
                  color: PomgtColors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Materiales de la estructura para este paso',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'estructura ${widget.bomRevision?['revision_code'] ?? 'sin revisión'}',
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Selecciona los componentes que se consumirán o considerarán en este paso.',
              style: TextStyle(
                color: PomgtColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.bomItems.isEmpty)
              const Text(
                'El producto de esta ruta no tiene componentes en una estructura activa o seleccionable.',
                style: TextStyle(color: PomgtColors.muted),
              )
            else
              FutureBuilder<List<Map<String, dynamic>>>(
                future: lookups.rows('products'),
                builder: (context, snapshot) {
                  final productRows =
                      snapshot.data ?? const <Map<String, dynamic>>[];
                  final productById = {
                    for (final product in productRows)
                      product['id']?.toString(): product,
                  };
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in widget.bomItems)
                        _BomMaterialButton(
                          label: _draftBomItemLabel(context, item, productById),
                          selected: _selected.contains(item['id']?.toString()),
                          onPressed: () {
                            final id = item['id']?.toString();
                            if (id != null) _toggle(id);
                          },
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _draftBomItemLabel(
    BuildContext context,
    Map<String, dynamic> item,
    Map<String?, Map<String, dynamic>> productById,
  ) {
    final product = productById[item['component_product_id']?.toString()];
    final name = product == null
        ? 'Material'
        : context.read<LookupRepository>().display(
            Phase1Schema.tables['products']!,
            product,
          );
    final qty = item['quantity'] == null ? '' : ' · ${item['quantity']}';
    return '${item['line_no'] ?? '—'} · $name$qty';
  }
}

class _BomMaterialButton extends StatelessWidget {
  const _BomMaterialButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(
      selected ? CupertinoIcons.checkmark : CupertinoIcons.add,
      size: 14,
      color: selected ? PomgtColors.mint : PomgtColors.blue,
    ),
    label: Text(label, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      foregroundColor: selected ? PomgtColors.mint : PomgtColors.blue,
      side: BorderSide(
        color: selected ? PomgtColors.mint : PomgtColors.lineStrong,
      ),
      shape: const RoundedRectangleBorder(borderRadius: PomgtRadii.borderSm),
    ),
  );
}

class _AssignedMaterialRow extends StatelessWidget {
  const _AssignedMaterialRow({required this.row, required this.onRemove});
  final Map<String, dynamic> row;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: lookups.rows('products'),
      builder: (context, snapshot) {
        final products = snapshot.data ?? const <Map<String, dynamic>>[];
        final label = _routeLookupDisplay(
          products,
          row['material_product_id'],
          Phase1Schema.tables['products']!,
          lookups,
          fallback: 'Material asignado desde la estructura de fabricación',
        );
        return DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PomgtColors.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.cube_box,
                  size: 17,
                  color: PomgtColors.blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  UiCopy.enumLabel(
                    row['consumption_point']?.toString() ?? 'during',
                  ),
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar material del paso',
                  onPressed: onRemove,
                  icon: const Icon(CupertinoIcons.trash, size: 16),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StepRelatedPanel extends StatelessWidget {
  const _StepRelatedPanel({
    required this.table,
    required this.fixedValues,
    required this.title,
    required this.description,
  });
  final String table;
  final Map<String, dynamic> fixedValues;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: EntityCrudPanel(
      table: table,
      repository: context.read<GenericRepository>(),
      lookups: context.read<LookupRepository>(),
      fixedValues: fixedValues,
      title: title,
      description: description,
      compact: true,
    ),
  );
}

String _stepTypeLabel(String? value) {
  switch (value) {
    case 'material':
      return 'Consumo de materiales';
    case 'quality':
      return 'Control de calidad';
    case 'packaging':
      return 'Empaque';
    case 'setup':
      return 'Preparación';
    case 'external_service':
      return 'Servicio externo';
    default:
      return 'Actividad';
  }
}

IconData _stepIcon(String? value) {
  switch (value) {
    case 'material':
      return CupertinoIcons.cube_box;
    case 'quality':
      return CupertinoIcons.checkmark_seal;
    case 'packaging':
      return CupertinoIcons.archivebox;
    case 'setup':
      return CupertinoIcons.slider_horizontal_3;
    case 'external_service':
      return CupertinoIcons.arrow_up_right_square;
    default:
      return CupertinoIcons.doc_text;
  }
}

Color _stepColor(String? value) {
  switch (value) {
    case 'material':
      return PomgtColors.amber;
    case 'quality':
      return PomgtColors.mint;
    case 'packaging':
      return PomgtColors.blueHover;
    case 'setup':
      return PomgtColors.blue;
    case 'external_service':
      return PomgtColors.danger;
    default:
      return PomgtColors.secondaryInk;
  }
}

class _RoutingSection extends StatelessWidget {
  const _RoutingSection({required this.title, required this.child, this.link});
  final String title;
  final String? link;
  final Widget child;
  @override
  Widget build(BuildContext context) => _RoutingPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: PomgtColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const InfoTip('Información de la sección.', size: 14),
                ],
              ),
            ),
            if (link != null)
              Text(
                link!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 11),
        child,
      ],
    ),
  );
}

class _RoutingPanel extends StatelessWidget {
  const _RoutingPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: PomgtColors.canvas,
      borderRadius: PomgtRadii.borderMd,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
      boxShadow: PomgtShadows.card,
    ),
    child: child,
  );
}

class _RouteLine extends StatelessWidget {
  const _RouteLine(this.label, this.value, {this.color = PomgtColors.ink});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: PomgtColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PomgtColors.muted, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RouteSmall extends StatelessWidget {
  const _RouteSmall(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(
            '$label:',
            style: const TextStyle(color: PomgtColors.muted, fontSize: 9.5),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _RoutingTableCell extends StatelessWidget {
  const _RoutingTableCell(this.value, {this.header = false});
  final String value;
  final bool header;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: header ? PomgtColors.muted : PomgtColors.ink,
        fontSize: header ? 10 : 10.5,
        fontWeight: header ? FontWeight.w900 : FontWeight.w700,
      ),
    ),
  );
}

TableRow _routeHeader(List<String> values) => TableRow(
  decoration: const BoxDecoration(color: PomgtColors.surfaceAlt),
  children: [
    for (final value in values) _RoutingTableCell(value, header: true),
  ],
);
TableRow _routeRow(List<String> values) => TableRow(
  decoration: const BoxDecoration(
    border: Border(bottom: BorderSide(color: PomgtColors.line)),
  ),
  children: [for (final value in values) _RoutingTableCell(value)],
);
