import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

/// Model for barometric pressure readings
class BarometricReading {
  final double pressurePa;
  final double? relativeAltitudeM;
  final DateTime timestamp;
  
  const BarometricReading({
    required this.pressurePa,
    this.relativeAltitudeM,
    required this.timestamp,
  });
  
  factory BarometricReading.fromMap(Map<String, dynamic> data) {
    return BarometricReading(
      pressurePa: (data['pressure'] as num).toDouble(),
      relativeAltitudeM: data['relativeAltitude'] != null 
          ? (data['relativeAltitude'] as num).toDouble() 
          : null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (data['timestamp'] as num).toInt(),
      ),
    );
  }
}

/// Service for accessing barometric pressure sensor data and computing altitude
class BarometerService {
  static String get _channelName => Platform.isIOS 
      ? 'com.getrucky.gfy/barometerStream'
      : 'com.ruck.app/barometerStream';
  
  static EventChannel get _eventChannel => EventChannel(_channelName);
  
  StreamSubscription<dynamic>? _subscription;
  final StreamController<BarometricReading> _controller = StreamController<BarometricReading>.broadcast();
  
  // Calibration variables for absolute altitude conversion
  double? _seaLevelPressurePa = 101325.0; // Standard sea level pressure in Pascals
  double? _referenceAltitudeM; // GPS reference altitude for calibration
  double? _referencePressurePa; // Pressure at reference altitude
  
  // Smoothing variables
  double? _smoothedPressure;
  static const double _pressureSmoothingAlpha = 0.15; // EMA smoothing factor
  
  /// Stream of barometric pressure readings
  Stream<BarometricReading> get readings => _controller.stream;
  
  /// Start streaming barometric pressure data
  Future<void> startStreaming() async {
    if (_subscription != null) {
      AppLogger.debug('[BAROMETER] Already streaming barometric data');
      return;
    }
    
    try {
      AppLogger.info('[BAROMETER] Starting barometric pressure streaming');
      
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic data) {
          try {
            if (data is Map<String, dynamic>) {
              final reading = BarometricReading.fromMap(data);
              _processBarometricReading(reading);
            } else {
              AppLogger.warning('[BAROMETER] Received invalid data format: ${data.runtimeType}');
            }
          } catch (e) {
            AppLogger.error('[BAROMETER] Error processing barometric reading: $e');
          }
        },
        onError: (dynamic error) {
          AppLogger.error('[BAROMETER] Stream error: $error');
          if (error is PlatformException) {
            if (error.code == 'UNAVAILABLE') {
              AppLogger.warning('[BAROMETER] Barometric sensor not available on this device');
            } else {
              AppLogger.error('[BAROMETER] Platform error: ${error.message}');
            }
          }
        },
        onDone: () {
          AppLogger.info('[BAROMETER] Stream closed');
        },
      );
      
      AppLogger.info('[BAROMETER] Barometric pressure streaming started successfully');
    } catch (e) {
      AppLogger.error('[BAROMETER] Failed to start barometric streaming: $e');
      rethrow;
    }
  }
  
  /// Stop streaming barometric pressure data
  Future<void> stopStreaming() async {
    await _subscription?.cancel();
    _subscription = null;
    AppLogger.info('[BAROMETER] Barometric pressure streaming stopped');
  }
  
  /// Calibrate barometric altitude using GPS reference
  void calibrateWithGPS({
    required double gpsAltitudeM,
    required double pressurePa,
  }) {
    _referenceAltitudeM = gpsAltitudeM;
    _referencePressurePa = pressurePa;
    
    AppLogger.info('[BAROMETER] Calibrated with GPS - altitude: ${gpsAltitudeM.toStringAsFixed(1)}m, pressure: ${pressurePa.toStringAsFixed(0)}Pa');
  }
  
  /// Convert pressure to altitude using barometric formula
  double pressureToAltitude(double pressurePa) {
    // Use iOS relative altitude if available (more accurate)
    if (Platform.isIOS) {
      // iOS provides relative altitude directly from CMAltimeter
      // We'll handle this in the reading processing
      return 0.0; // Placeholder, actual value comes from iOS
    }
    
    // Android: Use barometric formula
    if (_referencePressurePa != null && _referenceAltitudeM != null) {
      // Use calibrated reference for better accuracy
      final altitudeDelta = (44330 * (1 - math.pow(pressurePa / _referencePressurePa!, 0.1903))).toDouble();
      return _referenceAltitudeM! + altitudeDelta;
    } else {
      // Fallback to standard sea level pressure
      return (44330 * (1 - math.pow(pressurePa / _seaLevelPressurePa!, 0.1903))).toDouble();
    }
  }
  
  /// Get smoothed barometric altitude
  double? getSmoothedAltitude() {
    if (_smoothedPressure == null) return null;
    
    if (Platform.isIOS) {
      // iOS relative altitude handling will be done differently
      return null; // Will be handled in fusion logic
    }
    
    return pressureToAltitude(_smoothedPressure!);
  }
  
  /// Check if barometric sensor is available
  static Future<bool> isAvailable() async {
    try {
      // Try to start streaming briefly to test availability
      final testSubscription = _eventChannel.receiveBroadcastStream().listen(null);
      await testSubscription.cancel();
      return true;
    } catch (e) {
      if (e is PlatformException && e.code == 'UNAVAILABLE') {
        return false;
      }
      return false;
    }
  }
  
  void _processBarometricReading(BarometricReading reading) {
    // Apply EMA smoothing to pressure
    if (_smoothedPressure == null) {
      _smoothedPressure = reading.pressurePa;
    } else {
      _smoothedPressure = (_pressureSmoothingAlpha * reading.pressurePa) + 
                         ((1 - _pressureSmoothingAlpha) * _smoothedPressure!);
    }
    
    // Broadcast the reading
    if (!_controller.isClosed) {
      _controller.add(reading);
    }
    
    AppLogger.debug('[BAROMETER] Pressure: ${reading.pressurePa.toStringAsFixed(0)}Pa, '
        'Smoothed: ${_smoothedPressure!.toStringAsFixed(0)}Pa'
        '${reading.relativeAltitudeM != null ? ', RelAlt: ${reading.relativeAltitudeM!.toStringAsFixed(1)}m' : ''}');
  }
  
  /// Dispose of resources
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
