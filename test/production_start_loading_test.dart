import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/core/widgets/pomgt_loading.dart';
import 'package:pomgt/data/repositories/production_repository.dart';
import 'package:pomgt/data/services/supabase_database_service.dart';
import 'package:pomgt/features/production/production_operator_display.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StartRepository extends ProductionRepository {
  StartRepository(SupabaseClient client)
    : super(SupabaseDatabaseService(client), client);
  final transition = Completer<Map<String, dynamic>>();
  final reload = Completer<Map<String, dynamic>>();
  int loads = 0;

  Map<String, dynamic> data(String status) => {
    'order': {'id': 'op', 'op_number': 'OP-TEST'},
    'operations': [
      {
        'id': 'step',
        'routing_operation_id': 'source',
        'name': 'Fabricar',
        'sequence_no': 1,
        'status': status,
        'operation_type': 'activity',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> detail(String orderId) async {
    if (loads++ == 0) return data('ready');
    return reload.future;
  }

  @override
  Future<Map<String, dynamic>> transitionOperation(
    String operationId,
    String newStatus, {
    double? completedQuantity,
    double? rejectedQuantity,
    String? note,
  }) => transition.future;
}

void main() {
  late SupabaseClient client;
  setUp(() => client = SupabaseClient('https://example.supabase.co', 'test'));
  tearDown(() => client.dispose());

  for (final fail in [false, true]) {
    testWidgets(
      'start loading remains through refresh and recovers on failure: $fail',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repository = StartRepository(client);
        await tester.pumpWidget(
          MaterialApp(
            home: ProductionOperatorDisplay(
              orderId: 'op',
              repository: repository,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Iniciar producción').last);
        await tester.pump();
        expect(find.byType(PomgtLoading), findsOneWidget);
        expect(find.text('Iniciar producción'), findsNothing);
        if (fail) {
          repository.transition.completeError(
            StateError('No fue posible iniciar.'),
          );
        } else {
          repository.transition.complete({
            'id': 'step',
            'status': 'in_progress',
          });
          await tester.pump();
          expect(find.byType(PomgtLoading), findsOneWidget);
          repository.reload.complete(repository.data('in_progress'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(PomgtLoading), findsNothing);
        if (fail) expect(find.text('Iniciar producción'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      },
    );
  }
}
