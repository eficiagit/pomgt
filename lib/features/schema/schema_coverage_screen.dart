import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/info_tip.dart';
import '../../data/phase1_schema.dart';

class SchemaCoverageScreen extends StatefulWidget {
  const SchemaCoverageScreen({super.key});
  @override
  State<SchemaCoverageScreen> createState() => _SchemaCoverageScreenState();
}

class _SchemaCoverageScreenState extends State<SchemaCoverageScreen> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    final entries = Phase1Schema.tables.entries.where((e) {
      final q = search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return e.key.toLowerCase().contains(q) ||
          UiCopy.tableTitle(e.key, e.value.title).toLowerCase().contains(q) ||
          e.value.fields.any(
            (f) =>
                f.name.toLowerCase().contains(q) ||
                UiCopy.fieldLabel(f.name, f.label).toLowerCase().contains(q),
          );
    }).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 28,
        compact ? 14 : 24,
        compact ? 12 : 28,
        compact ? 18 : 28,
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
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  'Cobertura del esquema',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const InfoTip(
                'Auditoría visual de la primera fase. Todas las tablas y atributos de la base de datos están declarados en la interfaz. Los campos técnicos como identificadores, fechas de creación y actualización, y usuario creador se usan internamente aunque no se capturen manualmente.',
              ),
              Text(
                '${Phase1Schema.tables.length} tablas',
                style: const TextStyle(color: PomgtColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 56,
            child: TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: const InputDecoration(
                hintText: 'Buscar tabla o atributo…',
                prefixIcon: Icon(CupertinoIcons.search, size: 20),
                prefixIconConstraints: BoxConstraints(minWidth: 46),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final e = entries[i];
                return ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  backgroundColor: Colors.white,
                  collapsedBackgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: PomgtRadii.borderMd,
                    side: BorderSide(color: PomgtColors.line),
                  ),
                  collapsedShape: const RoundedRectangleBorder(
                    borderRadius: PomgtRadii.borderMd,
                    side: BorderSide(color: PomgtColors.line),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          UiCopy.tableTitle(e.key, e.value.title),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        e.key,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: PomgtColors.subtle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${e.value.fields.length}',
                        style: const TextStyle(
                          color: PomgtColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    UiCopy.tableDescription(e.key, e.value.description),
                    style: const TextStyle(
                      color: PomgtColors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: PomgtColors.line),
                        ),
                      ),
                      child: Column(
                        children: e.value.fields
                            .map(
                              (f) => SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  width: 680,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 9,
                                  ),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: PomgtColors.line,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 220,
                                        child: Text(
                                          UiCopy.fieldLabel(f.name, f.label),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 220,
                                        child: Text(
                                          f.name,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11.5,
                                            color: PomgtColors.muted,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: Text(
                                          _kindLabel(f.kind),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: PomgtColors.muted,
                                          ),
                                        ),
                                      ),
                                      if (f.required)
                                        const Text(
                                          'Requerido',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: PomgtColors.blue,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      if (f.readOnly)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 10),
                                          child: Text(
                                            'Sistema',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: PomgtColors.subtle,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
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
  }

  String _kindLabel(DbFieldKind kind) {
    switch (kind) {
      case DbFieldKind.textValue:
        return 'Texto';
      case DbFieldKind.integerValue:
        return 'Entero';
      case DbFieldKind.numberValue:
        return 'Número';
      case DbFieldKind.booleanValue:
        return 'Sí / No';
      case DbFieldKind.dateValue:
        return 'Fecha';
      case DbFieldKind.dateTimeValue:
        return 'Fecha y hora';
      case DbFieldKind.enumValue:
        return 'Selección';
      case DbFieldKind.reference:
        return 'Relación';
      case DbFieldKind.jsonValue:
        return 'Datos estructurados';
    }
  }
}
