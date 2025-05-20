class HeartRateSample {
  final DateTime timestamp;

  final int bpm;

  HeartRateSample({
    required this.timestamp,
    required this.bpm,
  });

  factory HeartRateSample.fromJson(Map<String, dynamic> json) => HeartRateSample(
        timestamp: DateTime.parse(json['timestamp'] as String),
        bpm: json['bpm'] as int,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'bpm': bpm,
      };
      
  /// Formats the heart rate sample for API submission
  Map<String, dynamic> toJsonForApi() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'bpm': bpm,
      };
}
