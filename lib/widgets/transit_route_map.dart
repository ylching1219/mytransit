import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/transit_data_service.dart';
import 'smart_move_widgets.dart';

class TransitRouteMap extends StatefulWidget {
  const TransitRouteMap({this.route, super.key});

  final TransitRouteResult? route;

  static const klSentral = LatLng(3.1339, 101.6869);
  static const pasarSeni = LatLng(3.1426, 101.6958);

  @override
  State<TransitRouteMap> createState() => _TransitRouteMapState();
}

class _TransitRouteMapState extends State<TransitRouteMap> {
  static const _initialZoom = 13.7;
  static const _minZoom = 10.0;
  static const _maxZoom = 19.0;

  final _mapController = MapController();

  @override
  void didUpdateWidget(covariant TransitRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route && widget.route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final camera = _mapController.camera;
        _mapController.move(_centerForRoute(widget.route), camera.zoom);
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _zoomBy(double amount) {
    final camera = _mapController.camera;
    final zoom = (camera.zoom + amount).clamp(_minZoom, _maxZoom).toDouble();
    _mapController.move(camera.center, zoom);
  }

  void _resetMap() {
    _mapController.move(_centerForRoute(widget.route), _initialZoom);
  }

  @override
  Widget build(BuildContext context) {
    final fromPoint = widget.route == null
        ? TransitRouteMap.klSentral
        : LatLng(widget.route!.fromLatitude, widget.route!.fromLongitude);
    final toPoint = widget.route == null
        ? TransitRouteMap.pasarSeni
        : LatLng(widget.route!.toLatitude, widget.route!.toLongitude);
    final fromLabel = widget.route?.fromStopName ?? 'KL Sentral';
    final toLabel = widget.route?.toStopName ?? 'Pasar Seni';
    final routeLegs = widget.route?.legs ?? const <TransitJourneyLeg>[];
    final polylines = routeLegs.isEmpty
        ? [
            Polyline(
              points: [fromPoint, toPoint],
              color: kTeal,
              strokeWidth: 3,
            ),
          ]
        : [
            for (final leg in routeLegs)
              Polyline(
                points: [
                  LatLng(leg.fromLatitude, leg.fromLongitude),
                  LatLng(leg.toLatitude, leg.toLongitude),
                ],
                color: leg.isWalking
                    ? kMuted
                    : leg.mode == 'Bus'
                    ? kTeal
                    : kPurple,
                strokeWidth: leg.isWalking ? 2 : 3,
              ),
          ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: SizedBox(
        height: 144,
        width: double.infinity,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: _centerForRoute(widget.route),
            initialZoom: _initialZoom,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          mapController: _mapController,
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.mytransit',
              maxZoom: 19,
            ),
            PolylineLayer(polylines: polylines),
            MarkerLayer(
              markers: [
                Marker(
                  point: fromPoint,
                  width: 90,
                  height: 34,
                  child: _MapPin(
                    label: fromLabel,
                    color: kTeal,
                    alignRight: false,
                  ),
                ),
                Marker(
                  point: toPoint,
                  width: 90,
                  height: 34,
                  child: _MapPin(
                    label: toLabel,
                    color: const Color(0xFFD46C68),
                    alignRight: true,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _MapControls(
                onZoomIn: () => _zoomBy(1),
                onZoomOut: () => _zoomBy(-1),
                onReset: _resetMap,
              ),
            ),
            RichAttributionWidget(
              attributions: [TextSourceAttribution('OpenStreetMap')],
            ),
          ],
        ),
      ),
    );
  }

  static LatLng _centerForRoute(TransitRouteResult? route) {
    final fromPoint = route == null
        ? TransitRouteMap.klSentral
        : LatLng(route.fromLatitude, route.fromLongitude);
    final toPoint = route == null
        ? TransitRouteMap.pasarSeni
        : LatLng(route.toLatitude, route.toLongitude);
    return LatLng(
      (fromPoint.latitude + toPoint.latitude) / 2,
      (fromPoint.longitude + toPoint.longitude) / 2,
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .94),
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapControlButton(icon: Icons.add_rounded, onTap: onZoomIn),
          const Divider(height: 1, thickness: 1),
          _MapControlButton(icon: Icons.remove_rounded, onTap: onZoomOut),
          const Divider(height: 1, thickness: 1),
          _MapControlButton(
            icon: Icons.center_focus_strong_rounded,
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 27,
        child: Icon(icon, size: 16, color: kInk),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  final String label;
  final Color color;
  final bool alignRight;

  const _MapPin({
    required this.label,
    required this.color,
    required this.alignRight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!alignRight) _dot(),
        if (!alignRight) const SizedBox(width: 4),
        Container(
          constraints: const BoxConstraints(maxWidth: 72),
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
        if (alignRight) const SizedBox(width: 4),
        if (alignRight) _dot(),
      ],
    );
  }

  Widget _dot() {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}
