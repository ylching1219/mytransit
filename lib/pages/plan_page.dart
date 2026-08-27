import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'auth_page.dart';
import '../providers/app_state.dart';
import '../services/transit_data_service.dart';
import '../widgets/smart_move_widgets.dart';

class PlanPage extends StatefulWidget {
  final ValueChanged<String> onMessage;

  const PlanPage({required this.onMessage, super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fromController;
  late final TextEditingController _toController;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController(text: 'Current location');
    _toController = TextEditingController(text: 'Pasar Seni');
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Enter a location' : null;
  }

  Future<void> _findRoutes() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final state = context.read<AppState>();
    final found = await state.planJourney(
      from: _fromController.text,
      to: _toController.text,
    );
    if (!mounted) return;
    if (!found) {
      widget.onMessage(
        state.transitError ?? 'No direct route was found for these stops.',
      );
      return;
    }
    final route = state.lastRoute;
    widget.onMessage(
      route == null
          ? 'Official route found and journey saved'
          : '${route.serviceName} route found and journey saved',
    );
  }

  Future<void> _saveFavoriteRoute() async {
    final state = context.read<AppState>();
    if (state.isGuest) {
      widget.onMessage('Please sign in to save favourite routes');
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }

    final saved = await state.saveFavoriteRoute(
      from: _fromController.text,
      to: _toController.text,
    );
    if (mounted && saved) widget.onMessage('Favourite route saved');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(7, 0, 7, 18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppHeader(
              title: 'Plan',
              avatarLabel: avatarInitials(state.profileName),
              avatarImagePath: state.profileImagePath,
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => widget.onMessage('Back to home'),
                  child: const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 17,
                      color: kMutedDark,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: PageTitle(
                    kicker: 'PLAN A JOURNEY',
                    title: 'Find your best route',
                    trailing: Text(
                      '1 of 2',
                      style: TextStyle(
                        fontSize: 9,
                        color: kMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            RouteField(
              label: 'STARTING FROM',
              controller: _fromController,
              validator: _required,
              icon: Icons.my_location_rounded,
              iconColor: kTeal,
              iconBackground: kTealSoft,
              subtitle: 'KL Sentral · GPS location',
            ),
            const SizedBox(height: 7),
            RouteField(
              label: 'GOING TO',
              controller: _toController,
              validator: _required,
              icon: Icons.location_on_outlined,
              iconColor: const Color(0xFFD46C68),
              iconBackground: kPeach,
              trailingIcon: Icons.search_rounded,
            ),
            const SizedBox(height: 13),
            const Row(
              children: [
                Icon(Icons.map_outlined, size: 14, color: kPurple),
                SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose on map',
                        style: TextStyle(
                          fontSize: 9,
                          color: kInk,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pick a bus stop or railway station',
                        style: TextStyle(fontSize: 8.5, color: kMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: kMuted),
              ],
            ),
            const SizedBox(height: 8),
            RouteMap(route: state.lastRoute),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 11, color: kTeal),
                const SizedBox(width: 3),
                Text(
                  state.lastRoute == null
                      ? '2 nearby stations'
                      : '${state.lastRoute!.stopsBetween} stops on official timetable',
                  style: const TextStyle(fontSize: 8.5, color: kMuted),
                ),
                const Spacer(),
                const Text(
                  'Walking limit: 800 m',
                  style: TextStyle(fontSize: 8.5, color: kMuted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: FilledButton.icon(
                onPressed: state.isSearching ? null : _findRoutes,
                icon: Icon(
                  state.isSearching
                      ? Icons.hourglass_top_rounded
                      : Icons.alt_route_rounded,
                  size: 15,
                ),
                label: Text(
                  state.isSearching
                      ? 'Finding routes...'
                      : 'Find available routes',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: kPurple,
                  disabledBackgroundColor: const Color(0xFF9A8BC9),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: OutlinedButton.icon(
                onPressed: _saveFavoriteRoute,
                icon: const Icon(Icons.bookmark_border_rounded, size: 15),
                label: Text(
                  state.isGuest
                      ? 'Sign in to save route'
                      : 'Save as favourite route',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPurple,
                  side: const BorderSide(color: kPurple),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                if (!state.permissionGranted) {
                  await state.requestLocationPermission();
                }
                if (!state.gpsEnabled) await state.requestGps();
              },
              child: const Center(
                child: Text(
                  'Location access helps us estimate walking time.',
                  style: TextStyle(fontSize: 8.5, color: kMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RouteField extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final IconData? trailingIcon;
  final TextEditingController controller;
  final String? Function(String?)? validator;

  const RouteField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    this.subtitle,
    this.trailingIcon,
    this.validator,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: Row(
        children: [
          Container(
            width: 29,
            height: 29,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: KickerStyle.small),
                TextFormField(
                  controller: controller,
                  validator: validator,
                  style: const TextStyle(
                    fontSize: 10,
                    color: kInk,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    errorStyle: TextStyle(fontSize: 8.5),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 8.5, color: kMuted),
                  ),
              ],
            ),
          ),
          if (trailingIcon != null)
            Icon(trailingIcon, size: 16, color: kMutedDark),
        ],
      ),
    );
  }
}

class RouteMap extends StatelessWidget {
  const RouteMap({this.route, super.key});

  final TransitRouteResult? route;

  static const klSentral = LatLng(3.1339, 101.6869);
  static const pasarSeni = LatLng(3.1426, 101.6958);

  @override
  Widget build(BuildContext context) {
    final fromPoint = route == null
        ? klSentral
        : LatLng(route!.fromLatitude, route!.fromLongitude);
    final toPoint = route == null
        ? pasarSeni
        : LatLng(route!.toLatitude, route!.toLongitude);
    final center = LatLng(
      (fromPoint.latitude + toPoint.latitude) / 2,
      (fromPoint.longitude + toPoint.longitude) / 2,
    );
    final fromLabel = route?.fromStopName ?? 'KL Sentral';
    final toLabel = route?.toStopName ?? 'Pasar Seni';

    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        height: 144,
        width: double.infinity,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13.7,
            interactionOptions: InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.mytransit',
              maxZoom: 19,
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [fromPoint, toPoint],
                  color: kTeal,
                  strokeWidth: 3,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: fromPoint,
                  width: 90,
                  height: 34,
                  child: MapPin(
                    label: fromLabel,
                    color: kTeal,
                    alignRight: false,
                  ),
                ),
                Marker(
                  point: toPoint,
                  width: 90,
                  height: 34,
                  child: MapPin(
                    label: toLabel,
                    color: Color(0xFFD46C68),
                    alignRight: true,
                  ),
                ),
              ],
            ),
            RichAttributionWidget(
              attributions: [TextSourceAttribution('OpenStreetMap')],
            ),
          ],
        ),
      ),
    );
  }
}

class MapPin extends StatelessWidget {
  final String label;
  final Color color;
  final bool alignRight;

  const MapPin({
    required this.label,
    required this.color,
    required this.alignRight,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!alignRight)
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
          ),

        if (!alignRight) const SizedBox(width: 4),

        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8,
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),

        if (alignRight) const SizedBox(width: 4),

        if (alignRight)
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
          ),
      ],
    );
  }
}
