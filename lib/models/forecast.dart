class Forecast {
  final String locationName;
  final String date;
  final String summaryForecast;
  final String summaryWhen;
  final int minTemp;
  final int maxTemp;

  const Forecast({
    required this.locationName,
    required this.date,
    required this.summaryForecast,
    required this.summaryWhen,
    required this.minTemp,
    required this.maxTemp,
  });

  factory Forecast.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    final locationMap = location is Map<String, dynamic>
        ? location
        : const <String, dynamic>{};
    return Forecast(
      locationName: locationMap['location_name'] as String? ?? 'Kuala Lumpur',
      date: json['date'] as String? ?? '',
      summaryForecast: json['summary_forecast'] as String? ?? 'Unavailable',
      summaryWhen: json['summary_when'] as String? ?? '',
      minTemp: (json['min_temp'] as num?)?.toInt() ?? 0,
      maxTemp: (json['max_temp'] as num?)?.toInt() ?? 0,
    );
  }
}
