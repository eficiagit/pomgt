import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/data/repositories/production_repository.dart';
import 'package:pomgt/data/services/supabase_database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <Uri>[];
  String? failTable;
  String failCode = 'PGRST205';
  setUp(() async {
    requests.clear();
    failTable = null;
    failCode = 'PGRST205';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'test');
    server.listen((request) async {
      requests.add(request.uri);
      final table = request.uri.pathSegments.last;
      request.response.headers.contentType = ContentType.json;
      if (table == failTable) {
        request.response.statusCode = failCode == '42501' ? 403 : 404;
        request.response.write(
          jsonEncode({'code': failCode, 'message': 'Error de prueba'}),
        );
      } else {
        final offset =
            int.tryParse(request.uri.queryParameters['offset'] ?? '0') ?? 0;
        final limit =
            int.tryParse(request.uri.queryParameters['limit'] ?? '500') ?? 500;
        final count = table == 'machines' ? 1203 : 1;
        final rows = <Map<String, dynamic>>[];
        for (var i = offset; i < count && i < offset + limit; i++) {
          rows.add({
            'id': '$table-${i.toString().padLeft(5, '0')}',
            'organization_id': 'org',
          });
        }
        request.response.write(jsonEncode(rows));
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test(
    'pagination reads 1203 machines with stable ordering and tenant filtering',
    () async {
      final rows = await SupabaseDatabaseService(client)
          .listAll('machines', equals: {'organization_id': 'org'});
      expect(rows.length, 1203);
      expect(rows.map((r) => r['id']).toSet().length, 1203);
      expect(requests.length, 3);
      for (final uri in requests) {
        expect(uri.queryParameters['organization_id'], 'eq.org');
        expect(uri.queryParameters['order'], startsWith('id.asc'));
      }
    },
  );
  test(
    'floor snapshot does not truncate machines and scopes inventory reads',
    () async {
      final repository = ProductionRepository(
        SupabaseDatabaseService(client),
        client,
      )..setOrganization('org');
      final data = await repository.floorSnapshot();
      expect((data['machines'] as List).length, 1203);
      expect(data['inventory_available'], true);
      for (final uri in requests.where(
        (uri) => uri.pathSegments.last != 'units_of_measure',
      )) {
        expect(uri.queryParameters['organization_id'], 'eq.org');
      }
    },
  );
  test('missing inventory migration leaves production map available', () async {
    failTable = 'floor_zones';
    final repository = ProductionRepository(
      SupabaseDatabaseService(client),
      client,
    )..setOrganization('org');
    final data = await repository.floorSnapshot();
    expect((data['machines'] as List).length, 1203);
    expect(data['inventory_available'], false);
  });
  test(
    'permission errors are surfaced instead of disguised as missing migrations',
    () async {
      failTable = 'inventory_stock';
      failCode = '42501';
      final repository = ProductionRepository(
        SupabaseDatabaseService(client),
        client,
      )..setOrganization('org');
      await expectLater(
        repository.floorSnapshot(),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    },
  );
}
