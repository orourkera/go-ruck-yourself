import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:http/io_client.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
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
    try {
      return TileLayer(
        urlTemplate: _getTileUrlTemplate(),
        userAgentPackageName: 'com.ruckingapp',
        retinaMode: widget.retinaMode,
        maxNativeZoom: 18,
        maxZoom: 20,
        
        // Custom tile builder with error handling
        tileBuilder: (context, tileWidget, tile) {
          try {
            widget.onTileLoaded?.call();
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
              ),
              child: tileWidget,
            );
          } catch (e) {
            // Return a placeholder if tile building fails
            return Container(
              color: Colors.grey[300],
              child: Icon(Icons.map, color: Colors.grey[500]),
            );
          }
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
    } catch (e, stackTrace) {
      // If entire tile layer fails, show a fallback
      AppLogger.error('RobustTileLayer build failed: $e', exception: e, stackTrace: stackTrace);
      return Container(
        color: Colors.grey[300],
        child: const Center(
          child: Icon(Icons.map_outlined, size: 48, color: Colors.grey),
        ),
      );
    }
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
    final baseClient = http.Client();
    
    return RetryClient(
      baseClient,
      retries: 3,
      when: (response) => response.statusCode >= 500 || response.statusCode == 429,
      whenError: (error, stackTrace) {
                 // Log error but don't crash - handle connection drops gracefully
         AppLogger.warning('Tile request error (will retry): $error');
        
        // Handle specific connection errors
        if (error.toString().contains('Connection closed') ||
            error.toString().contains('ClientException') ||
            error.toString().contains('SocketException') ||
            error.toString().contains('TimeoutException') ||
            error.toString().contains('HttpException')) {
          return true; // Retry these network errors
        }
        
        return true; // Retry all errors for now
      },
      delay: (retryCount) => Duration(milliseconds: 300 * retryCount),
    );
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
        const Duration(seconds: 15), // Increased from 10s for better tile loading
        onTimeout: () {
          client.close();
          throw TimeoutException('Tile request timeout', const Duration(seconds: 15));
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
    // Use ultra-safe tile layer that prevents ALL crashes
    try {
      if (!dotenv.isInitialized) {
        AppLogger.error('DotEnv not initialized - using fallback tiles');
        return _buildFallbackTileLayer();
      }

      final apiKey = dotenv.env['STADIA_MAPS_API_KEY'];
      final style = this.style ?? 'stamen_terrain';
      
      return TileLayer(
        urlTemplate: 'https://tiles.stadiamaps.com/tiles/$style/{z}/{x}/{y}{r}.png?api_key=$apiKey',
        userAgentPackageName: 'com.ruckingapp',
        retinaMode: retinaMode,
        maxNativeZoom: 18,
        maxZoom: 20,
        // Use custom resilient tile provider
        tileProvider: _UltraResilientTileProvider(),
        errorTileCallback: (tile, error, stackTrace) {
          // Handle ALL network errors gracefully without crashing
          AppLogger.debug(
            'Tile error handled gracefully: ${error.runtimeType} for ${tile.coordinates.z}/${tile.coordinates.x}/${tile.coordinates.y}',
          );
          onTileError?.call();
        },
        tileBuilder: (context, tileWidget, tile) {
          try {
            onTileLoaded?.call();
            return tileWidget;
          } catch (e) {
            // If tile building fails, return empty container
            AppLogger.debug('Tile building failed, using placeholder');
            return Container(
              width: 256,
              height: 256,
              color: Colors.grey[200],
            );
          }
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to build SafeTileLayer, using fallback',
        exception: e,
        stackTrace: stackTrace,
      );
      
      return _buildFallbackTileLayer();
    }
  }

  Widget _buildFallbackTileLayer() {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.ruckingapp',
      tileProvider: _UltraResilientTileProvider(),
      errorTileCallback: (tile, error, stackTrace) {
        // Suppress ALL errors from fallback tiles
        AppLogger.debug('Fallback tile error suppressed: ${error.runtimeType}');
        onTileError?.call();
      },
      tileBuilder: (context, tileWidget, tile) {
        try {
          onTileLoaded?.call();
          return tileWidget;
        } catch (e) {
          return Container(
            width: 256,
            height: 256,
            color: Colors.grey[300],
            child: const Icon(Icons.map, color: Colors.grey),
          );
        }
      },
    );
  }
}

/// Ultra-resilient tile provider that prevents ALL network-related crashes
class _UltraResilientTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _UltraResilientImageProvider(
      url: getTileUrl(coordinates, options),
      coordinates: coordinates,
    );
  }
}

/// Ultra-resilient image provider that never crashes on network errors
class _UltraResilientImageProvider extends ImageProvider<_UltraResilientImageProvider> {
  final String url;
  final TileCoordinates coordinates;
  
  const _UltraResilientImageProvider({
    required this.url,
    required this.coordinates,
  });

  @override
  Future<_UltraResilientImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_UltraResilientImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(_UltraResilientImageProvider key, ImageDecoderCallback decode) {
    return _UltraResilientImageStreamCompleter(
      url: key.url,
      coordinates: key.coordinates,
      decode: decode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is _UltraResilientImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}

/// Ultra-resilient image stream completer that never crashes
class _UltraResilientImageStreamCompleter extends ImageStreamCompleter {
  final String url;
  final TileCoordinates coordinates;
  final ImageDecoderCallback decode;
  Timer? _timeoutTimer;
  bool _completed = false;

  _UltraResilientImageStreamCompleter({
    required this.url,
    required this.coordinates,
    required this.decode,
  }) {
    _loadImageSafely();
  }

  void _loadImageSafely() async {
    try {
      // Set a hard timeout to prevent hanging
      _timeoutTimer = Timer(const Duration(seconds: 15), () { // Increased from 10s for better reliability
        if (!_completed) {
          _completed = true;
          AppLogger.debug('Tile load timeout for ${coordinates.z}/${coordinates.x}/${coordinates.y}');
          _completeWithError('Tile load timeout');
        }
      });

      // Try to load the image with aggressive timeout
      final httpClient = http.Client();
      final response = await httpClient.get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              throw TimeoutException('Tile request timeout', const Duration(seconds: 8));
            },
          );
      
      httpClient.close();
      
      if (_completed) return; // Already timed out
      
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final buffer = await ImmutableBuffer.fromUint8List(response.bodyBytes);
      final codec = await decode(buffer);
      final frame = await codec.getNextFrame();
      
      if (!_completed) {
        _completed = true;
        _timeoutTimer?.cancel();
        setImage(ImageInfo(image: frame.image));
      }
      
    } catch (e) {
      if (!_completed) {
        _completed = true;
        _timeoutTimer?.cancel();
        AppLogger.debug('Tile load failed gracefully: ${e.runtimeType} for ${coordinates.z}/${coordinates.x}/${coordinates.y}');
        _completeWithError(e.toString());
      }
    }
  }

  void _completeWithError(String error) {
    // Complete with a transparent placeholder instead of reporting error
    // This prevents the error from bubbling up and causing crashes
    try {
      // Create a 1x1 transparent image as placeholder
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = Colors.transparent;
      canvas.drawRect(const Rect.fromLTWH(0, 0, 256, 256), paint);
      final picture = recorder.endRecording();
      
      picture.toImage(256, 256).then((image) {
        if (!_completed) {
          setImage(ImageInfo(image: image));
        }
      }).catchError((e) {
        // If even creating a placeholder fails, do nothing
        // This prevents any error from escaping
        AppLogger.debug('Failed to create placeholder tile image');
      });
    } catch (e) {
      // Absolute last resort - do nothing to prevent crashes
      AppLogger.debug('Error creating error placeholder: $e');
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    // ImageStreamCompleter doesn't have a dispose method to call
  }
}
