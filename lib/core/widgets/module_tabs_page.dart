import 'package:flutter/material.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../theme/pomgt_theme.dart';
import '../utils/ui_copy.dart';
import 'entity_crud_panel.dart';
import 'info_tip.dart';

class ModuleTable {
  const ModuleTable(this.table, {this.label, this.help});
  final String table;
  final String? label;
  final String? help;
}

class ModuleTabsPage extends StatelessWidget {
  const ModuleTabsPage({
    super.key,
    required this.title,
    required this.help,
    required this.tables,
    required this.repository,
    required this.lookups,
  });
  final String title;
  final String help;
  final List<ModuleTable> tables;
  final GenericRepository repository;
  final LookupRepository lookups;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return DefaultTabController(
      length: tables.length,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 32,
          compact ? 14 : 18,
          compact ? 12 : 32,
          compact ? 18 : 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: PomgtColors.ink,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                InfoTip(help, size: 19),
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
                  color: PomgtColors.navySelected,
                  borderRadius: PomgtRadii.borderSm,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: PomgtColors.ink,
                unselectedLabelColor: PomgtColors.muted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                tabs: tables.map((t) {
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
                children: tables.map((t) {
                  return EntityCrudPanel(
                    table: t.table,
                    repository: repository,
                    lookups: lookups,
                    description: t.help,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
