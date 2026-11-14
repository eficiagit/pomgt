import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pomgt/core/theme/component_theme.dart';
import 'package:pomgt/core/widgets/info_tip.dart';
import 'package:pomgt/core/widgets/motion.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/controllers/auth_controller.dart';
import 'package:pomgt/core/theme/pomgt_theme.dart';
import 'package:pomgt/core/widgets/categorized_picker.dart';
import 'package:pomgt/core/widgets/empty_state.dart';
import 'package:pomgt/core/widgets/pomgt_button.dart';
import 'package:pomgt/core/widgets/pomgt_date_picker.dart';
import 'package:pomgt/core/widgets/pomgt_loading.dart';
import 'package:pomgt/core/widgets/status_pill.dart';
import 'package:pomgt/features/auth/login_screen.dart';
import 'package:provider/provider.dart';

Widget host(Widget child, {bool reduceMotion = false, double textScale = 1}) =>
    MaterialApp(
      theme: buildPomgtTheme(),
      locale: const Locale('es', 'MX'),
      supportedLocales: const [Locale('es', 'MX')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: PomgtComponentTheme(child: child!),
      ),
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader(PomgtTypography.body);
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      fonts.addFont(rootBundle.load('assets/fonts/IBMPlexSans-$weight.ttf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await lucide.load();
  });
  testWidgets('loading fits compact and wide surfaces with reduced motion', (
    tester,
  ) async {
    for (final size in [
      const Size(56, 56),
      const Size(320, 240),
      const Size(1200, 800),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(host(const PomgtLoading(), reduceMotion: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Cargando información'), findsOneWidget);
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('themed picker still filters and selects an origin', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      host(
        Padding(
          padding: const EdgeInsets.all(24),
          child: CategorizedSearchPicker(
            label: 'Origen *',
            value: null,
            items: const [
              PickerItem(
                id: 'customer_order',
                label: 'Pedido de cliente',
                category: 'Orígenes',
              ),
              PickerItem(
                id: 'internal_order',
                label: 'Orden interna',
                category: 'Orígenes',
              ),
            ],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'interna');
    await tester.pumpAndSettle();
    expect(find.text('Pedido de cliente'), findsNothing);
    await tester.tap(find.text('Orden interna'));
    await tester.pumpAndSettle();
    expect(selected, 'internal_order');
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar keeps the selected date and confirmation', (
    tester,
  ) async {
    DateTime? selected;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => selected = await showPomgtDatePicker(
              context,
              initialDate: DateTime(2026, 10, 20),
            ),
            child: const Text('Fecha'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fecha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 10, 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('time picker fits a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TimeOfDay? selected;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => selected = await showPomgtTimePicker(
              context,
              initialTime: const TimeOfDay(hour: 14, minute: 30),
            ),
            child: const Text('Hora'),
          ),
        ),
        textScale: 1.5,
      ),
    );
    await tester.tap(find.text('Hora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(selected, const TimeOfDay(hour: 14, minute: 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login and registration fit mobile with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _PreviewAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: host(const LoginScreen(), textScale: 1.5),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Crear una cuenta'));
    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Nombre completo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Forui help appears on hover and long press', (tester) async {
    await tester.pumpWidget(
      host(const Center(child: InfoTip('Ayuda del pedido'))),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(InfoTip)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Ayuda del pedido'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('Ayuda del pedido'), findsNothing);
    await mouse.removePointer();
    await tester.longPress(find.byType(InfoTip));
    await tester.pumpAndSettle();
    expect(find.text('Ayuda del pedido'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shadcn badges preserve parent row taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        Center(
          child: Material(
            child: InkWell(
              onTap: () => taps++,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: StatusPill('draft'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Borrador'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animated content retains form state on parent rebuild', (
    tester,
  ) async {
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return const SoftContentSwitch(
              child: TextField(key: ValueKey('form')),
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Pedido de cliente');
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(find.text('Pedido de cliente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared components fit mobile and desktop', (tester) async {
    final previewKey = GlobalKey();
    for (final width in [375.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: previewKey,
            child: ColoredBox(
              color: PomgtColors.appBg,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    'Pedidos',
                    style: buildPomgtTheme().textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Origen y cliente',
                            style: buildPomgtTheme().textTheme.titleLarge,
                          ),
                          const SizedBox(height: 24),
                          const TextField(
                            decoration: InputDecoration(
                              labelText: 'Origen *',
                              hintText: 'Buscar origen…',
                              prefixIcon: Icon(LucideIcons.search),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Requerido para el origen seleccionado.',
                            style: TextStyle(
                              color: PomgtColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const TextField(
                            decoration: InputDecoration(
                              labelText: 'Cliente *',
                              hintText: 'Buscar cliente…',
                              prefixIcon: Icon(LucideIcons.search),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              StatusPill('draft'),
                              StatusPill('in_progress'),
                              StatusPill('completed'),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              PomgtButton(
                                label: 'Guardar',
                                onPressed: () {},
                                icon: LucideIcons.check,
                              ),
                              PomgtButton(
                                label: 'Cancelar',
                                onPressed: () {},
                                primary: false,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Card(
                    child: EmptyState(
                      title: 'Sin documentos',
                      message: 'Los documentos vinculados aparecerán aquí.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      const previewPath = String.fromEnvironment('POMGT_VISUAL_PREVIEW');
      if (previewPath.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary =
              previewKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$previewPath-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    addTearDown(tester.view.reset);
  });
}

class _PreviewAuth extends ChangeNotifier implements AuthController {
  @override
  bool busy = false;
  @override
  String? error;
  @override
  String? info;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
