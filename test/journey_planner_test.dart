import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mytransit/services/transit_data_service.dart';

void main() {
  test(
    'maps the official journey planner response into route models',
    () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/geocode')) {
          final isDestination = request.url.queryParameters['input'] == 'To';
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'poiname': isDestination ? 'Destination stop' : 'Origin stop',
                  'geometry': {
                    'coordinates': isDestination
                        ? [101.633, 3.201]
                        : [101.621, 3.198],
                  },
                },
              ],
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({
            'status': 'OK',
            'estimated_departure_time': '2026-08-30 11:55:00',
            'routes': [
              {
                'estimated_arrival_time': '2026-08-30 12:25:00',
                'total_duration': 1800,
                'alt_fare_price': {
                  'adult': 1.0,
                  'cash': 1.0,
                  'cashless': 1.0,
                  'consession': 0.5,
                },
                'legs': [
                  {
                    'type': 'pedestrain',
                    'duration': 300,
                    'estimated_departure_time': '2026-08-30 11:55:00',
                    'estimated_end_arrival_time': '2026-08-30 12:00:00',
                  },
                  {
                    'type': 'transit',
                    'duration': 1500,
                    'estimated_departure_time': '2026-08-30 12:00:00',
                    'estimated_end_arrival_time': '2026-08-30 12:25:00',
                    'route_details': {
                      'route_id': '30000134',
                      'route_short_name': 'T108',
                      'route_long_name': 'T108',
                      'category': 'Rapid Bus',
                      'route_type': 3,
                      'headsign':
                          'MRT Sri Damansara Sentral - Bandar Menjalara',
                    },
                    'steps': [
                      {
                        'stop_id': 'A',
                        'stop_name': 'Origin stop',
                        'stop_lat': 3.198,
                        'stop_lon': 101.621,
                      },
                      {
                        'stop_id': 'B',
                        'stop_name': 'Destination stop',
                        'stop_lat': 3.201,
                        'stop_lon': 101.633,
                      },
                    ],
                  },
                ],
              },
            ],
          }),
          200,
        );
      });
      final service = TransitDataService(client: client);

      try {
        final routes = await service.findRoutes(
          from: 'From',
          to: 'To',
          departureAfterSeconds: 11 * 60 * 60 + 55 * 60,
          departureBeforeSeconds: 12 * 60 * 60 + 25 * 60,
        );

        expect(routes, hasLength(1));
        expect(routes.single.mode, 'Bus');
        expect(routes.single.serviceName, 'T108');
        expect(routes.single.routeId, '30000134');
        expect(routes.single.fare?.adult, '1.00');
        expect(routes.single.legs, hasLength(2));
        expect(routes.single.legs.last.passingStops, [
          'Origin stop',
          'Destination stop',
        ]);
      } finally {
        service.dispose();
      }
    },
  );
}
