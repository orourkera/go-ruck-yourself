import 'package:hive/hive.dart';
import 'heart_rate_sample.dart';

class HeartRateSampleAdapter extends TypeAdapter<HeartRateSample> {
  @override
  final int typeId = 1;

  @override
  HeartRateSample read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return HeartRateSample(
      timestamp: DateTime.parse(fields[0] as String),
      bpm: fields[1] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HeartRateSample obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.timestamp.toIso8601String())
      ..writeByte(1)
      ..write(obj.bpm);
  }
}
