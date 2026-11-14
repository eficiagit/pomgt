import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/core/theme/pomgt_theme.dart';
import 'package:pomgt/core/utils/app_notice.dart';
import 'package:pomgt/core/widgets/motion.dart';
import 'package:pomgt/core/widgets/pomgt_button.dart';
import 'package:pomgt/core/widgets/status_pill.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: buildPomgtTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('list entrances preserve form keys, text and validation focus', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    final focus = FocusNode();
    final controller = TextEditingController();
    addTearDown(focus.dispose);
    addTearDown(controller.dispose);
    late StateSetter rebuild;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return PomgtListView(
              children: [
                Form(
                  key: form,
                  child: TextFormField(
                    controller: controller,
                    focusNode: focus,
                    errorBuilder: pomgtValidationMessage,
                    validator: (value) =>
                        value!.length < 4 ? 'Escribe al menos 4 letras' : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'abc');
    form.currentState!.validate();
    await tester.pumpAndSettle();
    expect(find.text('Escribe al menos 4 letras'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(controller.text, 'abc');
    expect(focus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextFormField), 'Cliente');
    expect(form.currentState!.validate(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Escribe al menos 4 letras'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animated dialog preserves barrier rules and result', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            child: const Text('Abrir'),
            onPressed: () async {
              result = await showPomgtDialog<String>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  content: const Text('Confirmación'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, 'ok'),
                      child: const Text('Aceptar'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Confirmación'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(result, 'ok');
    expect(find.text('Confirmación'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy transition cannot submit twice and enables again', (
    tester,
  ) async {
    var busy = false;
    var calls = 0;
    late StateSetter update;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Center(
              child: PomgtButton(
                label: 'Guardar',
                icon: Icons.check,
                busy: busy,
                onPressed: () {
                  calls++;
                  setState(() => busy = true);
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Guardar'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Guardar'));
    expect(calls, 1);
    update(() => busy = false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('notice exits on close or timeout without leaving its overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            child: const Text('Aviso'),
            onPressed: () => showPomgtNotice(context, title: 'Guardado'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aviso'));
    await tester.pumpAndSettle();
    expect(find.text('Guardado'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Guardado'), findsNothing);
    await tester.tap(find.text('Aviso'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Guardado'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps tabs, lists and changing states usable', (
    tester,
  ) async {
    var status = 'draft';
    late StateSetter update;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PomgtTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Datos'),
                      Tab(text: 'Documentos'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        PomgtListView(children: [StatusPill(status)]),
                        const Text('Archivos'),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Borrador'), findsOneWidget);
    update(() => status = 'completed');
    await tester.pumpAndSettle();
    expect(find.text('Completado'), findsOneWidget);
    expect(find.text('Borrador'), findsNothing);
    await tester.tap(find.text('Documentos'));
    await tester.pumpAndSettle();
    expect(find.text('Archivos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('changing motion preference keeps an edited field mounted', (
    tester,
  ) async {
    var disabled = false;
    late StateSetter update;
    final fieldKey = GlobalKey();
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disabled),
              child: PomgtAnimatedSize(
                duration: PomgtMotion.medium,
                child: TextField(key: fieldKey),
              ),
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Pedido escrito');
    final original = tester.state(find.byKey(fieldKey));
    update(() => disabled = true);
    await tester.pumpAndSettle();
    expect(tester.state(find.byKey(fieldKey)), same(original));
    expect(find.text('Pedido escrito'), findsOneWidget);
    update(() => disabled = false);
    await tester.pumpAndSettle();
    expect(tester.state(find.byKey(fieldKey)), same(original));
    expect(tester.takeException(), isNull);
  });

  testWidgets('production style tab motion retains cached form pages', (
    tester,
  ) async {
    var index = 0;
    late StateSetter update;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return PomgtChangeMotion(
              value: index,
              child: IndexedStack(
                index: index,
                children: const [TextField(), Text('Documentos')],
              ),
            );
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Material capturado');
    update(() => index = 1);
    await tester.pumpAndSettle();
    expect(find.text('Documentos'), findsOneWidget);
    update(() => index = 0);
    await tester.pumpAndSettle();
    expect(find.text('Material capturado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
