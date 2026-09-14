import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/organization_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/error_copy.dart';
import '../../core/widgets/info_tip.dart';

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
  String? error;

  @override
  void dispose() {
    code.dispose();
    legal.dispose();
    display.dispose();
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

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrganizationController>();
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Configura POMGT',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(width: 8),
                    const InfoTip(
                      'Crea la organización principal. El asistente también prepara secuencias, unidades de medida y condiciones de pago iniciales.',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Esta configuración se realiza una sola vez para tu organización.',
                  style: TextStyle(color: PomgtColors.muted, fontSize: 15),
                ),
                const SizedBox(height: 36),
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
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: PomgtColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: org.loading ? null : _create,
                    child: org.loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Crear organización'),
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
    );
  }
}
