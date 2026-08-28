import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/transit_models.dart';
import '../services/database_adapter.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../services/transit_data_service.dart';

class AppState extends ChangeNotifier {
  final DatabaseAdapter _database = createDatabaseAdapter();
  final SupabaseService _supabaseService = SupabaseService();
  final LocationService _locationService = createLocationService();
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
  String? _transitError;
  TransitRouteResult? _lastRoute;
  TransitRouteResult? _nextRoute;
  String? _journeyAlert;
  int? _journeyRemainingStations;
  bool _journeyArrived = false;
  bool _journeyMonitoring = false;
  int _lastReachedStationIndex = -1;
  bool _journeyLocationRequestInFlight = false;
  Timer? _journeyPollingTimer;
  List<TransitRouteResult> _routeOptions = const [];
  String _profileName = 'Aina Koh';
  String _profileEmail = '';
  String _preferredTransport = 'Bus, rail & walking';
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
  String? get transitError => _transitError;
  TransitRouteResult? get lastRoute => _lastRoute;
  TransitRouteResult? get nextRoute => _nextRoute;
  String? get journeyAlert => _journeyAlert;
  int? get journeyRemainingStations => _journeyRemainingStations;
  bool get journeyArrived => _journeyArrived;
  bool get journeyMonitoring => _journeyMonitoring;
  List<TransitRouteResult> get routeOptions =>
      List.unmodifiable(_routeOptions.where(_matchesPreferredTransport));
  String get profileName => _profileName;
  String get profileEmail => _profileEmail;
  String get preferredTransport => _preferredTransport;
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
    _loadTravelPreferences();
    _notificationsEnabled =
        _preferences!.getBool('notifications_enabled') ?? true;
    _database.setUserScope(
      _isGuest ? 'guest' : _storageScopeForEmail(_profileEmail),
    );
    _savedPlaces = _isGuest ? const [] : await _database.loadSavedPlaces();
    _recentJourneys = _isGuest ? const [] : await _database.loadJourneys();

    final status = await _locationService.checkStatus();
    _gpsEnabled = status.gpsEnabled;
    _permissionGranted = status.permissionGranted;
    notifyListeners();
  }

  void selectTab(int index) {
    if (index == _selectedIndex) return;
    _selectedIndex = index;
    notifyListeners();
  }

  void markNextRoute(TransitRouteResult route) {
    _nextRoute = route;
    _journeyAlert = null;
    _journeyRemainingStations = null;
    _journeyArrived = false;
    _lastReachedStationIndex = -1;
    notifyListeners();
    if (_notificationsEnabled) unawaited(_restartJourneyMonitoring());
  }

  void clearNextRoute() {
    if (_nextRoute == null) return;
    _nextRoute = null;
    _journeyAlert = null;
    _journeyRemainingStations = null;
    _journeyArrived = false;
    _lastReachedStationIndex = -1;
    unawaited(stopJourneyMonitoring());
    notifyListeners();
  }

  bool isNextRoute(TransitRouteResult route) {
    final selected = _nextRoute;
    if (selected == null) return false;
    return selected.fromStopId == route.fromStopId &&
        selected.toStopId == route.toStopId &&
        selected.serviceName == route.serviceName &&
        selected.departureTime == route.departureTime;
  }

  Future<bool> planJourney({
    required String from,
    required String to,
    int? departureAfterSeconds,
    int? departureBeforeSeconds,
    bool recordRecent = true,
  }) async {
    if (from.trim().isEmpty || to.trim().isEmpty) return false;
    _isSearching = true;
    _transitError = null;
    _lastRoute = null;
    _routeOptions = const [];
    notifyListeners();
    try {
      final allRoutes = await _transitDataService.findRoutes(
        from: from,
        to: to,
        departureAfterSeconds: departureAfterSeconds,
        departureBeforeSeconds: departureBeforeSeconds,
      );
      if (allRoutes.isEmpty) {
        _transitError = 'No direct route was found for these stops.';
        return false;
      }

      final routes = allRoutes
          .where(_matchesPreferredTransport)
          .toList(growable: false);
      if (routes.isEmpty) {
        _transitError =
            'No ${_preferredTransport.toLowerCase()} route was found for this journey.';
        return false;
      }

      _routeOptions = routes;
      final route = routes.first;
      _lastRoute = route;
      if (recordRecent) {
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
      }
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

  Future<bool> removeFavoriteRoute(String id) async {
    if (_isGuest) return false;
    final updated = _savedPlaces.where((place) => place.id != id).toList();
    if (updated.length == _savedPlaces.length) return false;
    _savedPlaces = updated;
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
    _loadTravelPreferences();
    _database.setUserScope(_storageScopeForEmail(email));
    _savedPlaces = await _database.loadSavedPlaces();
    _recentJourneys = await _database.loadJourneys();
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
    _loadTravelPreferences();
    _savedPlaces = const [];
    _recentJourneys = const [];
    _lastRoute = null;
    _routeOptions = const [];
    _database.setUserScope('guest');
    _nextRoute = null;
    _journeyAlert = null;
    _journeyRemainingStations = null;
    _journeyArrived = false;
    _lastReachedStationIndex = -1;
    await stopJourneyMonitoring();
    await _preferences?.setBool('auth_signed_in', false);
    notifyListeners();
  }

  String _storageScopeForEmail(String email) {
    return email.trim().toLowerCase();
  }

  void _loadTravelPreferences() {
    final scope = _isGuest ? 'guest' : _storageScopeForEmail(_profileEmail);
    const defaultTransport = 'Bus, rail & walking';
    const supportedTransports = {
      defaultTransport,
      'Rail + walking',
      'Bus + walking',
    };
    final storedTransport = _preferences?.getString('travel_transport_$scope');
    _preferredTransport = supportedTransports.contains(storedTransport)
        ? storedTransport!
        : defaultTransport;
  }

  Future<void> updatePreferredTransport(String preferredTransport) async {
    _preferredTransport = preferredTransport;
    final scope = _isGuest ? 'guest' : _storageScopeForEmail(_profileEmail);
    await _preferences?.setString(
      'travel_transport_$scope',
      _preferredTransport,
    );
    notifyListeners();
  }

  bool _matchesPreferredTransport(TransitRouteResult route) {
    if (_preferredTransport == 'Bus, rail & walking') return true;

    final modeNames = [
      route.mode,
      ...route.legs.map((leg) => leg.mode),
    ].join(' ').toLowerCase();
    final hasBus = modeNames.contains('bus');
    final hasRail = RegExp(r'\b(lrt|mrt|rail|train)\b').hasMatch(modeNames);

    switch (_preferredTransport) {
      case 'Rail + walking':
        return hasRail && !hasBus;
      case 'Bus + walking':
        return hasBus && !hasRail;
      default:
        return true;
    }
  }

  Future<void> setNotifications(bool enabled) async {
    _notificationsEnabled = enabled;
    await _preferences?.setBool('notifications_enabled', enabled);
    if (!enabled) {
      await stopJourneyMonitoring();
      _journeyAlert = null;
      _journeyRemainingStations = null;
      _journeyArrived = false;
      _lastReachedStationIndex = -1;
    } else if (_nextRoute != null) {
      unawaited(_restartJourneyMonitoring());
    }
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

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_isGuest) {
      throw const FormatException('Sign in before changing your password.');
    }
    if (currentPassword.isEmpty) {
      throw const FormatException('Enter your current password.');
    }
    if (newPassword.length < 6) {
      throw const FormatException('Use at least 6 characters.');
    }
    if (_supabaseService.isConfigured) {
      await _supabaseService.updatePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return;
    }
    final storedPassword = _preferences?.getString('account_password');
    if (storedPassword != currentPassword) {
      throw const FormatException('Current password is incorrect.');
    }
    await _preferences?.setString('account_password', newPassword);
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

  Future<LocationSnapshot?> getCurrentLocation() async {
    if (!_permissionGranted) await requestLocationPermission();
    if (!_gpsEnabled) await requestGps();
    if (!_permissionGranted || !_gpsEnabled) return null;

    final snapshot = await _locationService.getCurrentLocation();
    if (snapshot.latitude == null || snapshot.longitude == null) return null;
    _locationHistory = [snapshot, ..._locationHistory].take(20).toList();
    notifyListeners();
    return snapshot;
  }

  Future<List<NearbyTransitStop>> findNearbyTransitStops({
    required double latitude,
    required double longitude,
    double maxDistanceMeters = 1500,
    int limit = 8,
  }) {
    return _transitDataService.findNearbyStops(
      latitude: latitude,
      longitude: longitude,
      maxDistanceMeters: maxDistanceMeters,
      limit: limit,
    );
  }

  Future<List<TransitPlaceSuggestion>> searchTransitSuggestions({
    required String query,
  }) {
    return _transitDataService.searchPlaceSuggestions(query: query);
  }

  void clearJourneyAlert() {
    if (_journeyAlert == null) return;
    _journeyAlert = null;
    notifyListeners();
  }

  Future<void> startJourneyMonitoring() async {
    if (_nextRoute == null || !_notificationsEnabled || _journeyMonitoring) {
      return;
    }

    if (!_permissionGranted) {
      _permissionGranted = await _locationService.requestPermission();
    }
    if (!_gpsEnabled) {
      _gpsEnabled = await _locationService.requestGps();
    }
    if (!_permissionGranted || !_gpsEnabled) {
      _journeyAlert =
          'Allow location access to receive station arrival alerts.';
      notifyListeners();
      return;
    }

    try {
      final initialLocation = await _locationService.getCurrentLocation();
      _handleJourneyLocation(initialLocation);
      if (_journeyArrived || _nextRoute == null) return;

      if (kIsWeb) {
        _journeyPollingTimer = Timer.periodic(
          const Duration(seconds: 10),
          (_) => unawaited(_pollJourneyLocation()),
        );
      } else {
        await _locationService.startTracking(_handleJourneyLocation);
      }
      _journeyMonitoring = true;
      notifyListeners();
    } catch (_) {
      _journeyAlert = 'Could not start location alerts for this journey.';
      notifyListeners();
    }
  }

  Future<void> stopJourneyMonitoring() async {
    _journeyPollingTimer?.cancel();
    _journeyPollingTimer = null;
    await _locationService.stopTracking();
    if (!_journeyMonitoring) return;
    _journeyMonitoring = false;
    notifyListeners();
  }

  Future<void> _restartJourneyMonitoring() async {
    await stopJourneyMonitoring();
    if (_nextRoute != null && _notificationsEnabled) {
      await startJourneyMonitoring();
    }
  }

  Future<void> _pollJourneyLocation() async {
    if (_journeyLocationRequestInFlight || _nextRoute == null) return;
    _journeyLocationRequestInFlight = true;
    try {
      final snapshot = await _locationService.getCurrentLocation();
      _handleJourneyLocation(snapshot);
    } catch (_) {
      // Keep the last known progress when a single location read fails.
    } finally {
      _journeyLocationRequestInFlight = false;
    }
  }

  void _handleJourneyLocation(LocationSnapshot snapshot) {
    if (_nextRoute == null ||
        snapshot.latitude == null ||
        snapshot.longitude == null) {
      return;
    }
    _locationHistory = [snapshot, ..._locationHistory].take(20).toList();
    _updateJourneyProgress(snapshot);
    notifyListeners();
  }

  void _updateJourneyProgress(LocationSnapshot snapshot) {
    final route = _nextRoute;
    if (route == null ||
        snapshot.latitude == null ||
        snapshot.longitude == null) {
      return;
    }
    final stations = _stationsForRoute(route);
    if (stations.isEmpty) return;

    var nearestIndex = -1;
    var nearestDistance = double.infinity;
    for (var index = 0; index < stations.length; index++) {
      final station = stations[index];
      final distance = _distanceMeters(
        snapshot.latitude!,
        snapshot.longitude!,
        station.latitude,
        station.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }

    // GPS can drift, so only announce a station when the user is nearby.
    if (nearestIndex < 0 || nearestDistance > 250) return;
    if (nearestIndex <= _lastReachedStationIndex) return;

    _lastReachedStationIndex = nearestIndex;
    final remaining = math.max(0, stations.length - nearestIndex - 1);
    _journeyRemainingStations = remaining;
    final stationName = stations[nearestIndex].name;
    final destinationName = stations.last.name;
    if (remaining == 0) {
      _journeyArrived = true;
      _journeyAlert = 'Arrived at $destinationName.';
      unawaited(stopJourneyMonitoring());
    } else {
      _journeyAlert = remaining == 1
          ? 'Arrived at $stationName. 1 station remaining until $destinationName.'
          : 'Arrived at $stationName. $remaining stations remaining until $destinationName.';
    }
  }

  List<TransitStationPoint> _stationsForRoute(TransitRouteResult route) {
    final stations = <TransitStationPoint>[];
    final seen = <String>{};
    for (final leg in route.legs) {
      if (leg.isWalking) continue;
      for (final station in leg.passingStations) {
        final key = station.name.toLowerCase().trim();
        if (seen.add(key)) stations.add(station);
      }
    }
    if (stations.isNotEmpty) return stations;
    return [
      TransitStationPoint(
        id: route.fromStopId,
        name: route.fromStopName,
        latitude: route.fromLatitude,
        longitude: route.fromLongitude,
      ),
      TransitStationPoint(
        id: route.toStopId,
        name: route.toStopName,
        latitude: route.toLatitude,
        longitude: route.toLongitude,
      ),
    ];
  }

  static double _distanceMeters(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(latitudeB - latitudeA);
    final longitudeDelta = _radians(longitudeB - longitudeA);
    final a =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(_radians(latitudeA)) *
            math.cos(_radians(latitudeB)) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    final clamped = a.clamp(0.0, 1.0).toDouble();
    return earthRadiusMeters * 2 * math.asin(math.sqrt(clamped));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

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
    _journeyPollingTimer?.cancel();
    unawaited(_locationService.stopTracking());
    super.dispose();
  }
}
