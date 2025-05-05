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
}
