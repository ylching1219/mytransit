import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/transit_models.dart';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://mftvrcdhezhznsjddhrt.supabase.co',
);
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_AFtfn29nZlcTARh-WNTjoQ_qS2TldnL',
);

class SupabaseService {
  bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }

  Future<void> syncProfile({
    required String name,
    required String email,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Pass SUPABASE_URL and '
        'SUPABASE_ANON_KEY with --dart-define.',
      );
    }
    final user = _client.auth.currentUser;
    final signedInEmail = user?.email?.trim().toLowerCase();
    if (signedInEmail == null || signedInEmail.isEmpty) {
      throw const FormatException(
        'Verify your email and sign in again before updating your profile.',
      );
    }
    final cleanName = name.trim();
    await _client.from('profiles').upsert({
      'name': cleanName,
      'email': signedInEmail,
    });
    await _client.auth.updateUser(UserAttributes(data: {'name': cleanName}));
  }

  User _requireUser() {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Pass SUPABASE_URL and '
        'SUPABASE_ANON_KEY with --dart-define.',
      );
    }
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const FormatException(
        'Verify your email and sign in before syncing your data.',
      );
    }
    return user;
  }

  Future<List<SavedPlace>> loadSavedPlaces() async {
    final user = _requireUser();
    final rows = await _client
        .from('saved_routes')
        .select('id, title, subtitle')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return rows
        .map((row) => SavedPlace.fromMap(Map<String, Object?>.from(row as Map)))
        .toList();
  }

  Future<void> saveSavedPlaces(List<SavedPlace> places) async {
    final user = _requireUser();
    if (places.isEmpty) {
      await _client.from('saved_routes').delete().eq('user_id', user.id);
      return;
    }
    await _client
        .from('saved_routes')
        .upsert(
          places
              .map(
                (place) => {
                  'id': place.id,
                  'user_id': user.id,
                  'title': place.title,
                  'subtitle': place.subtitle,
                },
              )
              .toList(),
          onConflict: 'id',
        );
  }

  Future<List<JourneyRecord>> loadJourneys() async {
    final user = _requireUser();
    final rows = await _client
        .from('journeys')
        .select(
          'id, from_location, to_location, service, duration_minutes, created_at',
        )
        .eq('user_id', user.id)
        .order('created_at', ascending: false);
    return rows
        .map(
          (row) => JourneyRecord.fromMap(Map<String, Object?>.from(row as Map)),
        )
        .toList();
  }

  Future<void> saveJourneys(List<JourneyRecord> journeys) async {
    final user = _requireUser();
    if (journeys.isEmpty) {
      await _client.from('journeys').delete().eq('user_id', user.id);
      return;
    }
    final existingRows = await _client
        .from('journeys')
        .select('id')
        .eq('user_id', user.id);
    final existingIds = existingRows
        .map((row) => (row as Map)['id']?.toString())
        .whereType<String>()
        .toSet();
    final currentIds = journeys.map((journey) => journey.id).toSet();

    await _client
        .from('journeys')
        .upsert(
          journeys
              .map(
                (journey) => {
                  'id': journey.id,
                  'user_id': user.id,
                  'from_location': journey.from,
                  'to_location': journey.to,
                  'service': journey.service,
                  'duration_minutes': journey.durationMinutes,
                  'created_at': journey.createdAt.toIso8601String(),
                },
              )
              .toList(),
          onConflict: 'id',
        );

    for (final staleId in existingIds.difference(currentIds)) {
      await _client
          .from('journeys')
          .delete()
          .eq('user_id', user.id)
          .eq('id', staleId);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    if (!isConfigured) return;
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    if (!isConfigured) return true;
    late final AuthResponse response;
    try {
      response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('already') || message.contains('registered')) {
        throw const FormatException(
          'This email is already registered. Please log in instead.',
        );
      }
      rethrow;
    }
    if (response.user == null) {
      throw const FormatException('Supabase could not create this account.');
    }
    return response.session != null;
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    await _client.auth.signOut();
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _requireUser();
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw const FormatException('Your account email is unavailable.');
    }

    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException {
      throw const FormatException('Current password is incorrect.');
    }

    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
