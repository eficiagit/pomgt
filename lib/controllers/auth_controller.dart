import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/services/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.service) {
    _session = service.client.auth.currentSession;
    _subscription = service.authChanges.listen((event) {
      _session = event.session;
      notifyListeners();
    });
  }

  final AuthService service;
  late final StreamSubscription<AuthState> _subscription;
  Session? _session;
  bool busy = false;
  String? error;
  String? info;

  Session? get session => _session;
  User? get user => _session?.user;
  bool get authenticated => user != null;

  Future<void> signIn(String email, String password) async {
    busy = true;
    error = null;
    info = null;
    notifyListeners();
    try {
      await service.signIn(email, password);
    } catch (e) {
      error = _friendly(e);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signUp(String name, String email, String password) async {
    busy = true;
    error = null;
    info = null;
    notifyListeners();
    try {
      await service.signUp(email, password, name);
      if (service.client.auth.currentSession == null) {
        info = 'Cuenta creada. Revisa tu correo para confirmar el acceso.';
      }
    } catch (e) {
      error = _friendly(e);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await service.signOut();
  }

  String _friendly(Object error) {
    final t = error.toString();
    if (t.toLowerCase().contains('invalid login credentials'))
      return 'Correo o contraseña incorrectos.';
    if (t.toLowerCase().contains('email not confirmed'))
      return 'Confirma tu correo antes de iniciar sesión.';
    if (t.toLowerCase().contains('user already registered'))
      return 'Ya existe una cuenta con este correo.';
    return 'No fue posible completar el acceso. Verifica tus datos e inténtalo de nuevo.';
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
