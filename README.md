# MyTransitAssist

MyTransitAssist is a four-page Kuala Lumpur transit companion app recreated from the original project. It follows the Flutter techniques in the supplied BMIT2073 Mobile Application Development practical PDF.

## Architecture

- `lib/providers/app_state.dart` owns shared state through Provider.
- `lib/services/database_adapter_io.dart` persists saved places and journeys in `MyTransitAssist.db` with SQLite on native platforms. Existing legacy database data is migrated once and the old file is removed.
- `lib/services/supabase_service.dart` synchronizes saved routes and journey history to Supabase for signed-in users; SQLite/browser storage remains the offline cache.
- `lib/services/database_adapter_web.dart` provides a SharedPreferences fallback for web builds.
- `lib/services/weather_service.dart` fetches Malaysian Meteorological Department forecast JSON.
- `lib/services/transit_data_service.dart` downloads the official Malaysian GTFS static feeds for Rapid Rail KL and Rapid Bus KL, reads the timetable ZIP files, and finds a direct route between the entered stops.
- `lib/services/supabase_service.dart` provides optional Supabase profile synchronization.
- `lib/services/location_service_io.dart` handles GPS permission and tracking.
- `lib/pages/plan_page.dart` uses Form validation and OpenStreetMap through `flutter_map`.
- The app starts in Guest mode; guests can browse, view journey history, and plan routes, but favourite-route saving requires an account.
- `lib/pages/auth_page.dart` contains the Login and Sign up screens. Local demo accounts are supported when Supabase is not configured.

Route searches use these official data.gov.my feeds:

- `https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl`
- `https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl`

The first search downloads and caches each feed in memory. The app searches rail first, then Rapid KL bus if no rail match is found. The feed is static timetable data, so it does not provide live vehicle positions.

## Run

```powershell
flutter pub get
flutter run
```

To enable Supabase profile sync:

```powershell
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-publishable-key
```

The app includes the configured MyTransitAssist Supabase project by default. The command above can still override it for another project. Run `supabase/schema.sql` in the Supabase SQL Editor before using profile, route, or journey syncing. Never put a Supabase service-role key in a Flutter app.

Without a working Supabase connection, local profile and journey persistence still works. Android location and internet permissions are included in `android/app/src/main/AndroidManifest.xml`; iOS location and photo usage descriptions are included in `ios/Runner/Info.plist`.

On an Android emulator, the native database is stored at `/data/data/com.example.mytransit/app_flutter/MyTransitAssist.db`. Chrome builds do not create this file; they use browser storage instead.
