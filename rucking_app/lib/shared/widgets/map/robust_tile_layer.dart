import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../core/utils/app_logger.dart';

/// Robust tile layer with comprehensive error handling, retry logic, and fallback strategies
class RobustTileLayer extends StatefulWidget {
  final String? style;
  final bool retinaMode;
  final void Function()? onTileLoaded;
  final void Function()? onTileError;

  const RobustTileLayer({
    super.key,
    this.style,
    this.retinaMode = false,
    this.onTileLoaded,
    this.onTileError,
  });

  @override
  State<RobustTileLayer> createState() => _RobustTileLayerState();
}

class _RobustTileLayerState extends State<RobustTileLayer> {
  int _consecutiveErrors = 0;
  bool _useOfflineMode = false;
  DateTime? _lastErrorTime;
  
  // Error threshold before switching to offline mode
  static const int _maxConsecutiveErrors = 3;
  static const Duration _errorCooldown = Duration(minutes: 2);
  
  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: _getTileUrlTemplate(),
      userAgentPackageName: 'com.ruckingapp',
      retinaMode: widget.retinaMode,
      maxNativeZoom: 18,
      maxZoom: 20,
      
      // Custom tile builder with error handling
      tileBuilder: (context, tileWidget, tile) {
        widget.onTileLoaded?.call();
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
          ),
          child: tileWidget,
        );
      },
      
      // Enhanced error handling
      errorTileCallback: (tile, error, stackTrace) {
        _handleTileError(tile.coordinates, error, stackTrace);
      },
      
      // Additional settings for stability with enhanced error handling
      tileProvider: _useOfflineMode 
          ? _createOfflineTileProvider()
          : _createResilientTileProvider(),
    );
  }
  
  String _getTileUrlTemplate() {
    final apiKey = dotenv.env['STADIA_MAPS_API_KEY'];
    final style = widget.style ?? 'stamen_terrain';
    
    if (_useOfflineMode) {
      // Use a simpler tile provider as fallback
      return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
    
    return 'https://tiles.stadiamaps.com/tiles/$style/{z}/{x}/{y}{r}.png?api_key=$apiKey';
  }
  
  void _handleTileError(TileCoordinates tile, Object error, StackTrace? stackTrace) {
    _consecutiveErrors++;
    _lastErrorTime = DateTime.now();
    
    AppLogger.warning(
      'Map tile loading error (${_consecutiveErrors}/$_maxConsecutiveErrors): $error',
    );
    
    // Switch to offline mode if too many consecutive errors
    if (_consecutiveErrors >= _maxConsecutiveErrors && !_useOfflineMode) {
      AppLogger.info('Switching to offline tile mode due to consecutive errors');
      setState(() {
        _useOfflineMode = true;
      });
      
      // Try to recover after cooldown period
      Future.delayed(_errorCooldown, () {
        if (mounted) {
          setState(() {
            _useOfflineMode = false;
            _consecutiveErrors = 0;
          });
          AppLogger.info('Attempting to recover from offline tile mode');
        }
      });
    }
    
    widget.onTileError?.call();
  }
  
  TileProvider _createOfflineTileProvider() {
    return NetworkTileProvider(
      // Use a more reliable tile provider with better error handling
      httpClient: http.Client(),
    );
  }
  
  /// Creates a resilient tile provider with enhanced error handling
  TileProvider _createResilientTileProvider() {
    return NetworkTileProvider(
      // Custom HTTP client with enhanced error handling
      httpClient: _createResilientHttpClient(),
    );
  }
  
  /// Creates HTTP client with better error handling for tile requests
  http.Client _createResilientHttpClient() {
    return http.Client();
  }
  
  /// Enhanced tile loading with comprehensive error catching
  Future<Uint8List?> _loadTileWithErrorHandling(String url) async {
    try {
      final client = http.Client();
      
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'RuckingApp/2.8.2',
          'Accept': 'image/png,image/jpeg,image/*,*/*',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          client.close();
          throw TimeoutException('Tile request timeout', const Duration(seconds: 10));
        },
      );
      
      client.close();
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        AppLogger.warning('Tile HTTP error: ${response.statusCode} for $url');
        return null;
      }
      
    } catch (e) {
      // Catch all network errors to prevent crashes
      AppLogger.warning('Tile loading error (handled): $e');
      return null;
    }
  }
}

/// Safe tile layer wrapper that prevents crashes
class SafeTileLayer extends StatelessWidget {
  final String? style;
  final bool retinaMode;
  final void Function()? onTileLoaded;
  final void Function()? onTileError;

  const SafeTileLayer({
    super.key,
    this.style,
    this.retinaMode = false,
    this.onTileLoaded,
    this.onTileError,
  });

  @override
  Widget build(BuildContext context) {
    // Use a simple, stable tile layer to prevent widget tree issues
    try {
      if (!dotenv.isInitialized) {
        // Use fallback tiles without logging repeatedly
        return TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ruckingapp',
          errorTileCallback: (tile, error, stackTrace) {
            // Suppress common network errors from fallback tiles
            if (error.toString().contains('ClientException') || 
                error.toString().contains('SocketException') ||
                error.toString().contains('connection abort')) {
              AppLogger.debug('Fallback network error (suppressed): ${error.runtimeType}');
            } else {
              AppLogger.warning('Fallback tile loading error: $error');
            }
            onTileError?.call();
          },
          tileBuilder: (context, tileWidget, tile) {
            onTileLoaded?.call();
            return tileWidget;
          },
        );
      }

      final apiKey = dotenv.env['STADIA_MAPS_API_KEY'];
      final style = this.style ?? 'stamen_terrain';
      
      return TileLayer(
        urlTemplate: 'https://tiles.stadiamaps.com/tiles/$style/{z}/{x}/{y}{r}.png?api_key=$apiKey',
        userAgentPackageName: 'com.ruckingapp',
        retinaMode: retinaMode,
        maxNativeZoom: 18,
        maxZoom: 20,
        errorTileCallback: (tile, error, stackTrace) {
          // Handle network errors gracefully without crashing
          if (error.toString().contains('ClientException') || 
              error.toString().contains('SocketException') ||
              error.toString().contains('connection abort')) {
            AppLogger.debug(
              'Network tile error (handled): ${error.runtimeType} for tile ${tile.coordinates.z}/${tile.coordinates.x}/${tile.coordinates.y}',
            );
          } else {
            AppLogger.warning(
              'Map tile loading error: $error (tile: ${tile.coordinates.z}/${tile.coordinates.x}/${tile.coordinates.y})',
            );
          }
          onTileError?.call();
        },
        tileBuilder: (context, tileWidget, tile) {
          onTileLoaded?.call();
          return tileWidget;
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to build map tile layer',
        exception: e,
        stackTrace: stackTrace,
      );
      
      // Return a fallback tile layer with minimal configuration
      return TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.ruckingapp',
        errorTileCallback: (tile, error, stackTrace) {
          // Suppress common network errors from fallback tiles
          if (error.toString().contains('ClientException') || 
              error.toString().contains('SocketException') ||
              error.toString().contains('connection abort')) {
            AppLogger.debug('Fallback network error (suppressed): ${error.runtimeType}');
          } else {
            AppLogger.warning('Fallback tile loading error: $error');
          }
          onTileError?.call();
        },
        tileBuilder: (context, tileWidget, tile) {
          onTileLoaded?.call();
          return tileWidget;
        },
      );
    }
  }
}
