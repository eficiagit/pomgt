import '../../core/widgets/motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/organization_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/error_copy.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/scroll_to_top.dart';

class OrganizationSetupScreen extends StatefulWidget {
  const OrganizationSetupScreen({super.key});
  @override
  State<OrganizationSetupScreen> createState() =>
      _OrganizationSetupScreenState();
}

class _OrganizationSetupScreenState extends State<OrganizationSetupScreen> {
  final code = TextEditingController();
  final legal = TextEditingController();
  final display = TextEditingController();
  final invite = TextEditingController();
  String? error;
  bool _joining = false;

  @override
  void dispose() {
    code.dispose();
    legal.dispose();
    display.dispose();
    invite.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (code.text.trim().isEmpty ||
        legal.text.trim().isEmpty ||
        display.text.trim().isEmpty) {
      setState(() => error = 'Completa los tres campos para continuar.');
      return;
    }
    try {
      await context.read<OrganizationController>().bootstrap(
        code: code.text,
        legalName: legal.text,
        displayName: display.text,
      );
    } catch (e) {
      if (mounted)
        setState(
          () => error = ErrorCopy.message(
            e,
            fallback: 'No fue posible crear la organización.',
          ),
        );
    }
  }

  Future<void> _join() async {
    if (invite.text.trim().isEmpty) {
      setState(() => error = 'Ingresa el código de invitación.');
      return;
    }
    try {
      await context.read<OrganizationController>().acceptInvite(invite.text);
    } catch (e) {
      if (mounted)
        setState(
          () => error = ErrorCopy.message(
            e,
            fallback: 'No fue posible unirte a la organización.',
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrganizationController>();
    return Scaffold(
      backgroundColor: PomgtColors.appBg,
      body: Center(
        child: ScrollToTopArea(
          padding: const EdgeInsets.all(16),
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Configura POMGT',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const InfoTip(
                        'Crea la organización principal. El asistente también prepara secuencias, unidades de medida y condiciones de pago iniciales.',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _joining
                        ? 'Pega el código de invitación que te compartió un administrador.'
                        : 'Esta configuración se realiza una sola vez para tu organización.',
                    style: const TextStyle(
                      color: PomgtColors.muted,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Crear organización'),
                        selected: !_joining,
                        onSelected: (_) => setState(() {
                          _joining = false;
                          error = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Unirme con invitación'),
                        selected: _joining,
                        onSelected: (_) => setState(() {
                          _joining = true;
                          error = null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_joining) ...[
                    TextField(
                      controller: invite,
                      decoration: const InputDecoration(
                        labelText: 'Código de invitación *',
                        hintText: 'Pega el código recibido',
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: display,
                      decoration: const InputDecoration(
                        labelText: 'Nombre comercial *',
                        hintText: 'Ej. Manufactura Delta',
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: legal,
                      decoration: const InputDecoration(
                        labelText: 'Razón social *',
                        hintText: 'Ej. Manufactura Delta, S.A. de C.V.',
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Código corto *',
                        hintText: 'DELTA',
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Semantics(
                      liveRegion: true,
                      child: PomgtReveal(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: PomgtColors.danger,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 30),
                  SizedBox(
                    height: PomgtButtonStyle.height,
                    child: FilledButton.icon(
                      onPressed: org.loading
                          ? null
                          : (_joining ? _join : _create),
                      icon: org.loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.plus, size: 18),
                      label: Text(_joining ? 'Unirme' : 'Crear organización'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.read<AuthController>().signOut(),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
