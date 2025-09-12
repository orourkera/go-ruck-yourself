import 'package:pigeon/pigeon.dart';

/// API for communicating between Flutter and native platforms for rucking app
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/core/api/rucking_api.dart',
  dartOptions: DartOptions(),
  objcHeaderOut: 'ios/Runner/rucking_api.h',
  objcSourceOut: 'ios/Runner/rucking_api.m',
  objcOptions: ObjcOptions(),
  swiftOut: 'ios/Runner/RuckingApi.swift',
))

/// Messages from native (Watch) to Flutter
@FlutterApi()
abstract class RuckingApi {
  /// Start a new session from the watch
  @async
  bool startSessionFromWatch(double ruckWeight);

  /// Start a session on the watch (Flutter -> native)
  @async
  bool startSessionOnWatch(double ruckWeight);

  /// Update session metrics on the watch (Flutter -> native)
  @async
  bool updateSessionOnWatch(
      double distance,
      double duration,
      double pace,
      bool isPaused,
      double calories,
      double elevationGain,
      double elevationLoss);

  /// Pause an active session from the watch
  @async
  bool pauseSessionFromWatch();

  /// Resume a paused session from the watch
  @async
  bool resumeSessionFromWatch();

  /// End the current session from the watch
  @async
  bool endSessionFromWatch(int duration, double distance, double calories);

  /// Update heart rate from the watch
  @async
  bool updateHeartRateFromWatch(double heartRate);
}

/// Messages from Flutter to native (Watch)
@HostApi()
abstract class FlutterRuckingApi {
  /// Update session metrics on the watch
  void updateSessionOnWatch(
      double distance,
      double duration,
      double pace,
      bool isPaused,
      double calories,
      double elevationGain,
      double elevationLoss);

  /// Start a session on the watch
  void startSessionOnWatch(double ruckWeight);

  /// Pause a session on the watch
  void pauseSessionOnWatch();

  /// Resume a session on the watch
  void resumeSessionOnWatch();

  /// End a session on the watch
  void endSessionOnWatch();
}
