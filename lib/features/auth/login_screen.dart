import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/auth_controller.dart';
import '../../core/theme/pomgt_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool signUp = false;
  bool obscure = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    try {
      if (signUp) {
        await auth.signUp(name.text, email.text, password.text);
      } else {
        await auth.signIn(email.text, password.text);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      backgroundColor: PomgtColors.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 190,
                    height: 66,
                    child: Image(
                      image: AssetImage('assets/POMGT-LOGO.png'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 46),
                Text(
                  signUp ? 'Crear cuenta' : 'Iniciar sesión',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  signUp
                      ? 'Registra tus datos para crear tu acceso a POMGT.'
                      : 'Ingresa tus credenciales para continuar.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 34),
                if (signUp) ...[
                  TextField(
                    controller: name,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: password,
                  obscureText: obscure,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    suffixIcon: IconButton(
                      tooltip: obscure
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      onPressed: () => setState(() => obscure = !obscure),
                      icon: Icon(
                        obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    auth.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PomgtColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (auth.info != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    auth.info!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PomgtColors.success,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: auth.busy ? null : _submit,
                    child: auth.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(signUp ? 'Crear cuenta' : 'Entrar'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: auth.busy
                      ? null
                      : () => setState(() => signUp = !signUp),
                  child: Text(signUp ? 'Ya tengo acceso' : 'Crear una cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
