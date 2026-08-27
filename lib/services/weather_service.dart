import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/forecast.dart';

class WeatherService {
  static const _baseUrl = 'https://api.data.gov.my/weather/forecast';

  Future<List<Forecast>> fetchForecast(String locationId) async {
    if (locationId.isEmpty) return const <Forecast>[];
    final uri = Uri.parse(
      '$_baseUrl?contains=$locationId@location__location_id&sort=date',
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Weather request failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Weather response was not a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Forecast.fromJson)
        .toList();
  }
}
