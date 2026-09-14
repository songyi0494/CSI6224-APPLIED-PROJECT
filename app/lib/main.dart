import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'data/app_repository.dart';
import 'data/mock_app_repository.dart';
import 'data/supabase_app_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const defaultMode = kDebugMode ? 'mock' : 'unconfigured';
  const mode = String.fromEnvironment('APP_MODE', defaultValue: defaultMode);
  try {
    final AppRepository repository;
    if (mode == 'mock') {
      repository = MockAppRepository();
    } else if (mode == 'supabase') {
      const url = String.fromEnvironment('SUPABASE_URL');
      const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
      if (url.isEmpty || key.isEmpty)
        throw const AppException('Application configuration is missing.');
      await Supabase.initialize(url: url, publishableKey: key);
      repository = SupabaseAppRepository(Supabase.instance.client);
    } else {
      throw const AppException('Choose an application mode before starting.');
    }
    runApp(OsteoporosisPathwaysApp(repository: repository));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'OsteoCare Pathway could not start. Please check the application configuration and restart.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
