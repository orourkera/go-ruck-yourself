import 'package:hive/hive.dart';

part 'heart_rate_sample.g.dart';

@HiveType(typeId: 1)
class HeartRateSample {
  @HiveField(0)
  final DateTime timestamp;

  @HiveField(1)
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
