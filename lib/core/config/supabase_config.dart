class SupabaseConfig {
  const SupabaseConfig._();

  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gqrzayglrkxfacswaiio.supabase.co',
  );

  // The anon/publishable key is intentionally a client-side key. Never put a
  // Supabase service_role key in this Flutter application.
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdxcnpheWdscmt4ZmFjc3dhaWlvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg5NzE0MzIsImV4cCI6MjEwNDU0NzQzMn0.99N9aYH9kXbnInb7yxm_OC8kh9jXNfNXnh5oB75t3Tg',
  );

  static const databaseSchema = 'pomgt';
  static const documentBucket = 'pomgt-documents';
}
