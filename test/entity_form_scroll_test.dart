import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/controllers/runtime_data_controller.dart';
import 'package:pomgt/core/widgets/entity_crud_panel.dart';
import 'package:pomgt/data/phase1_schema.dart';
import 'package:pomgt/data/repositories/generic_repository.dart';
import 'package:pomgt/data/repositories/lookup_repository.dart';
import 'package:pomgt/data/services/supabase_database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  setUp(() => client = SupabaseClient('https://example.supabase.co', 'test'));
  tearDown(() => client.dispose());
  for (final reduceMotion in [false, true]) {
    testWidgets(
      'reveals materials on selection, reduced motion: $reduceMotion',
      (tester) async {
        final runtime = RuntimeDataController();
        addTearDown(runtime.dispose);
        final repository = GenericRepository(
          SupabaseDatabaseService(client),
          client,
        );
        final lookups = LookupRepository(repository, runtime);
        final spec = DbTableSpec(
          table: 'routing_operations',
          title: 'Nuevo paso',
          description: '',
          fields: [
            const DbFieldSpec(
              name: 'operation_type',
              label: 'Tipo de paso',
              kind: DbFieldKind.enumValue,
              enumValues: ['activity', 'material'],
              defaultValue: 'activity',
            ),
            for (var index = 0; index < 12; index++)
              DbFieldSpec(
                name: 'field_$index',
                label: 'Campo $index',
                kind: DbFieldKind.textValue,
              ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
            home: Scaffold(
              body: EntityFormDialog(
                spec: spec,
                repository: repository,
                lookups: lookups,
                scrollToExtraWhenShown: true,
                extraContentBuilder: (_, values) =>
                    values['operation_type'] == 'material'
                    ? const SizedBox(
                        height: 180,
                        child: Text('Selector de materiales'),
                      )
                    : null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .controller!;
        expect(scroll.offset, 0);
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Material').last);
        for (
          var frame = 0;
          frame < 30 && find.text('Selector de materiales').evaluate().isEmpty;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.text('Selector de materiales'), findsOneWidget);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        if (!reduceMotion) {
          expect(scroll.offset, greaterThan(0));
          expect(scroll.offset, lessThan(scroll.position.maxScrollExtent));
        }
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, .1));
        expect(
          find.text('Selector de materiales').hitTestable(),
          findsOneWidget,
        );
        // Editing another field must not drag the user back down repeatedly.
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Paso de prueba',
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
