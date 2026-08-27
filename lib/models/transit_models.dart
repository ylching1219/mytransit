class SavedPlace {
  final String id;
  final String title;
  final String subtitle;

  const SavedPlace({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  factory SavedPlace.fromMap(Map<String, Object?> map) {
    return SavedPlace(
      id: map['id'] as String,
      title: map['title'] as String,
      subtitle: map['subtitle'] as String,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
  };
}

class JourneyRecord {
  final String id;
  final String from;
  final String to;
  final String service;
  final int durationMinutes;
  final DateTime createdAt;

  const JourneyRecord({
    required this.id,
    required this.from,
    required this.to,
    required this.service,
    required this.durationMinutes,
    required this.createdAt,
  });

  factory JourneyRecord.fromMap(Map<String, Object?> map) {
    return JourneyRecord(
      id: map['id'] as String,
      from: map['from_location'] as String,
      to: map['to_location'] as String,
      service: map['service'] as String,
      durationMinutes: map['duration_minutes'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'from_location': from,
    'to_location': to,
    'service': service,
    'duration_minutes': durationMinutes,
    'created_at': createdAt.toIso8601String(),
  };
}
