class ErrorCopy {
  const ErrorCopy._();

  static String message(
    Object error, {
    String fallback = 'No fue posible completar la operación.',
  }) {
    final text = error.toString();
    final lower = text.toLowerCase();

    if (text.contains('PGRST106') || lower.contains('invalid schema: pomgt')) {
      return 'El esquema de POMGT todavía no está habilitado en la API de datos de Supabase.';
    }
    if (text.contains('42501') || lower.contains('permission denied')) {
      return 'No tienes permiso para realizar esta acción. Revisa las políticas de seguridad por registro y tu organización.';
    }
    if (text.contains('22001') ||
        lower.contains('value too long for type character(2)')) {
      return 'El país debe seleccionarse como México o Estados Unidos. El sistema guardará automáticamente MX o US.';
    }
    if (text.contains('23505') || lower.contains('duplicate key')) {
      return 'Ya existe un registro con esos datos únicos.';
    }
    if (text.contains('23503') || lower.contains('foreign key')) {
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
    return fallback;
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
