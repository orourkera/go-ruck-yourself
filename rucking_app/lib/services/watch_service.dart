import 'dart:async';
import 'package:flutter/services.dart';

class WatchService {
  static const MethodChannel _methodChannel = MethodChannel('com.yourcompany.ruckingapp/watch');
  static const EventChannel _eventChannel = EventChannel('com.yourcompany.ruckingapp/heartRateStream');
  
  Stream<double>? _heartRateStream;
  
  /// Start a workout session on the Watch
  Future<bool> startWorkout() async {
    try {
      final result = await _methodChannel.invokeMethod('startWorkout');
      return result as bool;
    } catch (e) {
      print('Error starting workout on Watch: $e');
      return false;
    }
  }
  
  /// Stop a workout session on the Watch
  Future<bool> stopWorkout() async {
    try {
      final result = await _methodChannel.invokeMethod('stopWorkout');
      return result as bool;
    } catch (e) {
      print('Error stopping workout on Watch: $e');
      return false;
    }
  }
  
  /// Update metrics on the Watch
  Future<bool> updateMetrics({
    required double heartRate,
    required double distance,
    required double calories,
    required double pace,
    required double elevation,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod('updateMetrics', {
        'heartRate': heartRate,
        'distance': distance,
        'calories': calories,
        'pace': pace,
        'elevation': elevation,
      });
      return result as bool;
    } catch (e) {
      print('Error updating metrics on Watch: $e');
      return false;
    }
  }
  
  /// Stream to listen for heart rate updates from the Watch
  Stream<double> get heartRateStream {
    _heartRateStream ??= _eventChannel.receiveBroadcastStream().map<double>((value) => value as double);
    return _heartRateStream!;
  }
}
