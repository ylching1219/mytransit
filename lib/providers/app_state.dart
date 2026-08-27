import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/forecast.dart';
import '../models/transit_models.dart';
import '../services/database_adapter.dart';
import '../services/location_service.dart';
import '../services/profile_image_service.dart';
import '../services/supabase_service.dart';
import '../services/transit_data_service.dart';
import '../services/weather_service.dart';

class AppState extends ChangeNotifier {
  final DatabaseAdapter _database = createDatabaseAdapter();
  final WeatherService _weatherService = WeatherService();
  final SupabaseService _supabaseService = SupabaseService();
  final LocationService _locationService = createLocationService();
  final ProfileImageService _profileImageService = createProfileImageService();
  final TransitDataService _transitDataService = TransitDataService();
  final Uuid _uuid = const Uuid();

  SharedPreferences? _preferences;
  int _selectedIndex = 0;
  bool _isGuest = true;
  bool _isSearching = false;
  bool _notificationsEnabled = true;
  bool _gpsEnabled = false;
  bool _permissionGranted = false;
  bool _trackingEnabled = false;
  bool _weatherLoading = false;
  String? _weatherError;
  String? _transitError;
  TransitRouteResult? _lastRoute;
  String _profileName = 'Aina Koh';
  String _profileEmail = '';
  String? _profileImagePath;
  Forecast? _currentForecast;
  List<SavedPlace> _savedPlaces = const [];
  List<JourneyRecord> _recentJourneys = const [];
  List<LocationSnapshot> _locationHistory = const [];

  int get selectedIndex => _selectedIndex;
  bool get isGuest => _isGuest;
  bool get isSearching => _isSearching;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get gpsEnabled => _gpsEnabled;
  bool get permissionGranted => _permissionGranted;
  bool get trackingEnabled => _trackingEnabled;
  bool get weatherLoading => _weatherLoading;
  String? get weatherError => _weatherError;
  String? get transitError => _transitError;
  TransitRouteResult? get lastRoute => _lastRoute;
  String get profileName => _profileName;
  String get profileEmail => _profileEmail;
  String? get profileImagePath => _profileImagePath;
  Forecast? get currentForecast => _currentForecast;
  List<SavedPlace> get savedPlaces => List.unmodifiable(_savedPlaces);
  List<JourneyRecord> get recentJourneys => List.unmodifiable(_recentJourneys);
  List<LocationSnapshot> get locationHistory =>
      List.unmodifiable(_locationHistory);
  bool get supabaseConfigured => _supabaseService.isConfigured;

  Future<void> initialize() async {
    await _database.init();
    _preferences = await SharedPreferences.getInstance();
    _isGuest = !(_preferences!.getBool('auth_signed_in') ?? false);
    _profileName = _isGuest
        ? 'Guest'
        : _preferences!.getString('profile_name') ?? 'Aina Koh';
    _profileEmail = _isGuest
        ? ''
        : _preferences!.getString('profile_email') ?? '';
    _profileImagePath = _preferences!.getString('profile_image_path');
    _notificationsEnabled =
        _preferences!.getBool('notifications_enabled') ?? true;
    _savedPlaces = _isGuest ? const [] : await _database.loadSavedPlaces();
    _recentJourneys = await _database.loadJourneys();

    if (_recentJourneys.isEmpty) {
      _recentJourneys = [
        JourneyRecord(
          id: 'journey-1',
          from: 'KL Sentral',
          to: 'Pasar Seni',
          service: 'KL Kelana Jaya',
          durationMinutes: 12,
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        JourneyRecord(
          id: 'journey-2',
          from: 'Campus',
          to: 'KL Sentral',
          service: 'Bus B41',
          durationMinutes: 26,
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];
      await _database.saveJourneys(_recentJourneys);
    }

    final status = await _locationService.checkStatus();
    _gpsEnabled = status.gpsEnabled;
    _permissionGranted = status.permissionGranted;
    notifyListeners();
    unawaited(refreshWeather());
  }

  void selectTab(int index) {
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    notifyListeners();
  }

  Future<bool> planJourney({required String from, required String to}) async {
    if (from.trim().isEmpty || to.trim().isEmpty) return false;
    _isSearching = true;
    _transitError = null;
    notifyListeners();
    try {
      final route = await _transitDataService.findRoute(
        from: from,
        to: to,
      );
      if (route == null) {
        _transitError = 'No direct route was found for these stops.';
        return false;
      }

      _lastRoute = route;
      final journey = JourneyRecord(
        id: _uuid.v4(),
        from: route.fromStopName,
        to: route.toStopName,
        service: route.serviceName,
        durationMinutes: route.durationMinutes,
        createdAt: DateTime.now(),
      );
      _recentJourneys = [journey, ..._recentJourneys].take(10).toList();
      await _database.saveJourneys(_recentJourneys);
      await _syncJourneysToCloud();
      return true;
    } catch (error) {
      _transitError = error is TransitDataException
          ? error.message
          : 'Could not load government transit data.';
      return false;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<bool> saveFavoriteRoute({
    required String from,
    required String to,
  }) async {
    if (_isGuest || from.trim().isEmpty || to.trim().isEmpty) return false;
    final place = SavedPlace(
      id: _uuid.v4(),
      title: '${from.trim()} → ${to.trim()}',
      subtitle: 'LRT Kelana Jaya · Saved route',
    );
    _savedPlaces = [place, ..._savedPlaces].take(20).toList();
    await _database.saveSavedPlaces(_savedPlaces);
    await _syncSavedPlacesToCloud();
    notifyListeners();
    return true;
  }

  Future<void> signIn({required String email, required String password}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || password.isEmpty) {
      throw const FormatException('Enter your email and password.');
    }

    if (_supabaseService.isConfigured) {
      await _supabaseService.signIn(email: cleanEmail, password: password);
    } else {
      final storedEmail = _preferences?.getString('account_email');
      final storedPassword = _preferences?.getString('account_password');
      if (storedEmail != cleanEmail || storedPassword != password) {
        throw const FormatException('Email or password is incorrect.');
      }
    }
    await _activateAccount(
      name:
          _preferences?.getString('profile_name') ??
          _preferences?.getString('account_name') ??
          'Aina Koh',
      email: cleanEmail,
    );
    await syncCloudData();
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanName.isEmpty || cleanEmail.isEmpty || password.length < 6) {
      throw const FormatException(
        'Enter a name, a valid email, and a password of at least 6 characters.',
      );
    }

    if (!_supabaseService.isConfigured &&
        _preferences?.getString('account_email') == cleanEmail) {
      throw const FormatException(
        'This email is already registered. Please log in instead.',
      );
    }

    if (_supabaseService.isConfigured) {
      final hasSession = await _supabaseService.signUp(
        name: cleanName,
        email: cleanEmail,
        password: password,
      );
      if (!hasSession) {
        throw const FormatException(
          'Account created. Verify your email, then sign in.',
        );
      }
    } else {
      await _preferences?.setString('account_name', cleanName);
      await _preferences?.setString('account_email', cleanEmail);
      await _preferences?.setString('account_password', password);
    }
    await _activateAccount(name: cleanName, email: cleanEmail);
    await syncCloudData();
  }

  Future<void> _activateAccount({
    required String name,
    required String email,
  }) async {
    _isGuest = false;
    _profileName = name;
    _profileEmail = email;
    _savedPlaces = await _database.loadSavedPlaces();
    await _preferences?.setBool('auth_signed_in', true);
    await _preferences?.setString('profile_name', name);
    await _preferences?.setString('profile_email', email);
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_supabaseService.isConfigured) await _supabaseService.signOut();
    _isGuest = true;
    _profileName = 'Guest';
    _profileEmail = '';
    _savedPlaces = const [];
    await _preferences?.setBool('auth_signed_in', false);
    notifyListeners();
  }

  Future<void> refreshWeather() async {
    _weatherLoading = true;
    _weatherError = null;
    notifyListeners();
    try {
      final results = await _weatherService.fetchForecast('St009');
      _currentForecast = results.isEmpty ? null : results.first;
    } catch (_) {
      _weatherError = 'Weather is unavailable right now.';
    } finally {
      _weatherLoading = false;
      notifyListeners();
    }
  }

  Future<void> setNotifications(bool enabled) async {
    _notificationsEnabled = enabled;
    await _preferences?.setBool('notifications_enabled', enabled);
    notifyListeners();
  }

  Future<void> saveProfile({
    required String name,
    required String email,
  }) async {
    _profileName = name.trim();
    _profileEmail = email.trim();
    await _preferences?.setString('profile_name', _profileName);
    await _preferences?.setString('profile_email', _profileEmail);
    if (!_isGuest) {
      await _preferences?.setString('account_name', _profileName);
    }
    notifyListeners();
  }

  Future<void> syncProfile() async {
    await _supabaseService.syncProfile(
      name: _profileName,
      email: _profileEmail,
    );
  }

  Future<void> syncCloudData() async {
    if (_isGuest || !_supabaseService.isConfigured) return;

    try {
      final remotePlaces = await _supabaseService.loadSavedPlaces();
      if (remotePlaces.isEmpty && _savedPlaces.isNotEmpty) {
        await _supabaseService.saveSavedPlaces(_savedPlaces);
      } else {
        _savedPlaces = remotePlaces;
        await _database.saveSavedPlaces(_savedPlaces);
      }
    } catch (_) {
      // Keep the local cache available when Supabase is offline or not ready.
    }

    try {
      final remoteJourneys = await _supabaseService.loadJourneys();
      if (remoteJourneys.isEmpty && _recentJourneys.isNotEmpty) {
        await _supabaseService.saveJourneys(_recentJourneys);
      } else {
        _recentJourneys = remoteJourneys;
        await _database.saveJourneys(_recentJourneys);
      }
    } catch (_) {
      // Keep the local cache available when Supabase is offline or not ready.
    }
    notifyListeners();
  }

  Future<void> _syncSavedPlacesToCloud() async {
    if (_isGuest || !_supabaseService.isConfigured) return;
    try {
      await _supabaseService.saveSavedPlaces(_savedPlaces);
    } catch (_) {
      // The local database remains the offline source of truth.
    }
  }

  Future<void> _syncJourneysToCloud() async {
    if (_isGuest || !_supabaseService.isConfigured) return;
    try {
      await _supabaseService.saveJourneys(_recentJourneys);
    } catch (_) {
      // The local database remains the offline source of truth.
    }
  }

  Future<void> sendPasswordReset() async {
    if (_isGuest || _profileEmail.isEmpty) {
      throw const FormatException('Sign in with an email address first.');
    }
    if (!_supabaseService.isConfigured) {
      throw const FormatException(
        'Use the local reset form when Supabase is not configured.',
      );
    }
    await _supabaseService.sendPasswordReset(email: _profileEmail);
  }

  Future<void> updatePassword({required String newPassword}) async {
    if (_isGuest) {
      throw const FormatException('Sign in before changing your password.');
    }
    if (newPassword.length < 6) {
      throw const FormatException('Use at least 6 characters.');
    }
    if (_supabaseService.isConfigured) {
      throw const FormatException(
        'Use the password reset link sent to your email.',
      );
    }
    await _preferences?.setString('account_password', newPassword);
  }

  Future<String?> pickProfileImage() async {
    final imagePath = await _profileImageService.pickAndPersist();
    if (imagePath == null) return null;
    _profileImagePath = imagePath;
    await _preferences?.setString('profile_image_path', imagePath);
    notifyListeners();
    return imagePath;
  }

  Future<void> clearJourneys() async {
    _recentJourneys = const [];
    await _database.saveJourneys(_recentJourneys);
    await _syncJourneysToCloud();
    notifyListeners();
  }

  Future<void> requestGps() async {
    _gpsEnabled = await _locationService.requestGps();
    notifyListeners();
  }

  Future<void> requestLocationPermission() async {
    _permissionGranted = await _locationService.requestPermission();
    notifyListeners();
  }

  Future<void> startLocationTracking() async {
    if (!_gpsEnabled || !_permissionGranted) return;
    await _locationService.startTracking((snapshot) {
      _locationHistory = [snapshot, ..._locationHistory].take(20).toList();
      notifyListeners();
    });
    _trackingEnabled = true;
    notifyListeners();
  }

  Future<void> stopLocationTracking() async {
    await _locationService.stopTracking();
    _trackingEnabled = false;
    _locationHistory = const [];
    notifyListeners();
  }

  @override
  void dispose() {
    _transitDataService.dispose();
    unawaited(_locationService.stopTracking());
    super.dispose();
  }
}
