import 'package:flutter/material.dart';
import 'app.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ultjzjusngytlpffngaw.supabase.co',
    publishableKey: 'sb_publishable_REBCKpQz3Oynoh-meioPFg_raht6d0C',
  );

  runApp(const OsteoporosisPathwaysApp());
}

final supabase = Supabase.instance.client;

