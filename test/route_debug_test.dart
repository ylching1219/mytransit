import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

import 'package:mytransit/services/transit_data_service.dart';

void main() {
  test('inspect nearby coordinates for T108 query', () async {
    final service = TransitDataService();
    try {
      final from = await service.findStopsForPlace(
        query: 'MRT Sri Damansara Sentral Pintu A',
        maxDistanceMeters: 2500,
        limit: 12,
      );
      final to = await service.findStopsForPlace(
        query: 'Taman Bukit Maluri',
        maxDistanceMeters: 2500,
        limit: 12,
      );
      debugPrint(
        'FROM: ${from.map((stop) => '${stop.id}|${stop.name}|${stop.latitude},${stop.longitude}|${stop.mode}').toList()}',
      );
      debugPrint(
        'TO: ${to.map((stop) => '${stop.id}|${stop.name}|${stop.latitude},${stop.longitude}|${stop.mode}').toList()}',
      );
    } finally {
      service.dispose();
    }
  });
}
