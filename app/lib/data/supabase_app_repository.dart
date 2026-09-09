import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import 'mock_app_repository.dart';

class SupabaseAppRepository extends MockAppRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;

    if (user == null) {
      throw Exception('Login failed.');
    }

    final profile = await _supabase
        .from('profiles')
        .select('full_name, role')
        .eq('id', user.id)
        .single();

    final savedRole = profile['role'] as String;

    if (savedRole != role.name) {
      await _supabase.auth.signOut();

      throw Exception(
        'This account is registered as $savedRole.',
      );
    }

    return AppUser(
      id: user.id,
      displayName: profile['full_name'] as String,
      email: user.email ?? email,
      role: role,
    );
  }
}