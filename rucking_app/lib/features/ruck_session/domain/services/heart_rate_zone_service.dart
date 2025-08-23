import 'package:flutter/material.dart';
import 'package:rucking_app/features/ruck_session/domain/models/heart_rate_sample.dart';

class HeartRateZoneService {
  /// Returns five zones based on HR reserve (Karvonen):
  /// Z1 50-60%, Z2 60-70%, Z3 70-80%, Z4 80-90%, Z5 90-100% of HRR + resting.
  static List<({int min, int max, Color color, String name})> zonesFromProfile({
    required int restingHr,
    required int maxHr,
  }) {
    final int hrr = (maxHr - restingHr).clamp(20, 200);
    int at(double pct) => (restingHr + pct * hrr).round();
    final z1Min = at(0.50), z1Max = at(0.60);
    final z2Min = at(0.60), z2Max = at(0.70);
    final z3Min = at(0.70), z3Max = at(0.80);
    final z4Min = at(0.80), z4Max = at(0.90);
    final z5Min = at(0.90), z5Max = maxHr;
    return [
      (min: z1Min, max: z1Max, color: Colors.blue.shade400, name: 'Z1'),
      (min: z2Min, max: z2Max, color: Colors.green.shade500, name: 'Z2'),
      (min: z3Min, max: z3Max, color: Colors.amber.shade600, name: 'Z3'),
      (min: z4Min, max: z4Max, color: Colors.deepOrange.shade600, name: 'Z4'),
      (min: z5Min, max: z5Max, color: Colors.red.shade600, name: 'Z5'),
    ];
  }

  /// Compute seconds spent in each zone based on consecutive sample intervals.
  /// Returns a map of zone name to seconds.
  static Map<String, int> timeInZonesSeconds({
    required List<HeartRateSample> samples,
    required List<({int min, int max, Color color, String name})> zones,
  }) {
    final Map<String, int> bucket = {for (final z in zones) z.name: 0};
    if (samples.length < 2) return bucket;
    for (int i = 0; i < samples.length - 1; i++) {
      final s = samples[i];
      final sNext = samples[i + 1];
      final dt = sNext.timestamp.difference(s.timestamp).inSeconds.clamp(0, 600);
      if (dt <= 0) continue;
      final bpm = s.bpm;
      final zone = _zoneForBpm(bpm, zones);
      if (zone != null) bucket[zone.name] = (bucket[zone.name] ?? 0) + dt;
    }
    return bucket;
  }

  static ({int min, int max, Color color, String name})? _zoneForBpm(
    int bpm,
    List<({int min, int max, Color color, String name})> zones,
  ) {
    for (final z in zones) {
      if (bpm >= z.min && bpm <= z.max) return z;
    }
    // Below Z1
    if (zones.isNotEmpty && bpm < zones.first.min) return zones.first;
    // Above Z5
    if (zones.isNotEmpty && bpm > zones.last.max) return zones.last;
    return null;
  }
}


