import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/utils/orientation_lock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OrientationLock.appPortraitOnly();
  await Supabase.initialize(
    url: SupabaseConfig.projectUrl,
    anonKey: SupabaseConfig.publishableKey,
  );
  runApp(const PomgtApp());
}
