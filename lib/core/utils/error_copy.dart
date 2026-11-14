import 'dart:convert';

import 'action_exception.dart';

class ErrorCopy {
  const ErrorCopy._();

  static String message(
    Object error, {
    String fallback = 'No fue posible completar la operación.',
  }) {
    if (error is ActionException) return error.message;
    final text = error.toString();
    final lower = text.toLowerCase();

    final payload = _jsonPayload(text);
    final code = payload?['code']?.toString();
    final serverMessage = payload?['message']?.toString();
    if (code == '22P02' && lower.contains('routing:')) {
      return 'La ruta todavía no está guardada como operaciones de esta orden. Actualiza la orden e inténtalo de nuevo.';
    }
    if (code == 'P0001' && serverMessage != null) return serverMessage;

    if (text.contains('PGRST106') || lower.contains('invalid schema: pomgt')) {
      return 'El esquema de POMGT todavía no está habilitado en la API de datos de Supabase.';
    }
    if (text.contains('42501') || lower.contains('permission denied')) {
      return 'No tienes permiso para realizar esta acción. Revisa las políticas de seguridad por registro y tu organización.';
    }
    if (lower.contains('value too long for type character(2)')) {
      return 'El país debe seleccionarse como México o Estados Unidos. El sistema guardará automáticamente MX o US.';
    }
    if (text.contains('22001')) {
      return 'Uno de los valores capturados es más largo de lo permitido para ese campo.';
    }
    if (text.contains('23505') || lower.contains('duplicate key')) {
      return 'Ya existe un registro con esos datos únicos.';
    }
    if (text.contains('23503') || lower.contains('foreign key')) {
      if (lower.contains('material_type_id_fkey')) {
        return 'Este tipo de material todavía tiene productos, pasos de fabricación o atributos relacionados. Revisa esos vínculos antes de eliminarlo.';
      }
      if (lower.contains('units_of_measure_category_id_fkey')) {
        return 'Esta categoría tiene unidades de medida asociadas. Reasígnalas a otra categoría compatible desde Datos maestros → Unidades de medida antes de eliminarla.';
      }
      return 'Este registro está relacionado con otra información y la operación no puede realizarse de esa forma.';
    }
    if (lower.contains('row-level security') ||
        lower.contains('violates row level security')) {
      return 'La política de seguridad por registro no permite esta operación.';
    }
    if (lower.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Confirma tu correo antes de iniciar sesión.';
    }
    if (lower.contains('user already registered')) {
      return 'Ya existe una cuenta con este correo.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('failed host lookup')) {
      return 'No fue posible conectarse al servidor. Revisa tu conexión e inténtalo de nuevo.';
    }
    if (lower.contains('postgrestexception')) {
      final message = _postgrestPart(text, 'message') ?? text;
      final details = _postgrestPart(text, 'details');
      final hint = _postgrestPart(text, 'hint');
      return [
        fallback,
        message,
        if (details != null && details != 'null') details,
        if (hint != null && hint != 'null') hint,
      ].join('\n');
    }
    if (serverMessage != null && serverMessage.trim().isNotEmpty) {
      return serverMessage;
    }
    return fallback;
  }

  static Map<String, dynamic>? _jsonPayload(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _postgrestPart(String text, String key) {
    final marker = '$key: ';
    final start = text.indexOf(marker);
    if (start == -1) return null;
    final valueStart = start + marker.length;
    final terminators = switch (key) {
      'message' => const [', code:'],
      'code' => const [', details:'],
      'details' => const [', hint:'],
      'hint' => const [')'],
      _ => const [','],
    };
    var end = text.length;
    for (final terminator in terminators) {
      final candidate = text.indexOf(terminator, valueStart);
      if (candidate != -1 && candidate < end) end = candidate;
    }
    final value = text.substring(valueStart, end).trim();
    return value.isEmpty ? null : value;
  }
}
