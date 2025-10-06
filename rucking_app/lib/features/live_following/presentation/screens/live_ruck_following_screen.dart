import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/core/utils/measurement_utils.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/shared/widgets/map/robust_tile_layer.dart';

/// Screen for following someone's live ruck with real-time updates
class LiveRuckFollowingScreen extends StatefulWidget {
  final String ruckId;
  final String ruckerName;

  const LiveRuckFollowingScreen({
    Key? key,
    required this.ruckId,
    required this.ruckerName,
  }) : super(key: key);

  @override
  State<LiveRuckFollowingScreen> createState() => _LiveRuckFollowingScreenState();
}

class _LiveRuckFollowingScreenState extends State<LiveRuckFollowingScreen> {
  final ApiClient _apiClient = GetIt.I<ApiClient>();
  final TextEditingController _messageController = TextEditingController();

  Timer? _refreshTimer;
  bool _isLoading = true;
  bool _isSendingMessage = false;
  String _selectedVoice = 'supportive_friend';

  // Live session data
  double _currentDistance = 0.0;
  int _currentDuration = 0;
  double _currentPace = 0.0;
  LatLng? _currentLocation;
  List<LatLng> _route = [];
  DateTime? _lastUpdate;

  // Voice options
  final List<Map<String, String>> _voiceOptions = [
    {'id': 'drill_sergeant', 'name': '🎖️ Drill Sergeant', 'desc': 'Intense & motivating'},
    {'id': 'supportive_friend', 'name': '🤗 Supportive Friend', 'desc': 'Warm & encouraging'},
    {'id': 'data_nerd', 'name': '📊 Data Nerd', 'desc': 'Analytical & precise'},
    {'id': 'minimalist', 'name': '🧘 Minimalist', 'desc': 'Calm & brief'},
  ];

  @override
  void initState() {
    super.initState();
    _loadLiveData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    // Refresh every 15 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _loadLiveData();
      }
    });
  }

  Future<void> _loadLiveData() async {
    try {
      final data = await _apiClient.get('/rucks/${widget.ruckId}/live');

      if (data != null && mounted) {
        setState(() {
          _currentDistance = (data['distance_km'] as num?)?.toDouble() ?? 0.0;
          _currentDuration = data['duration_seconds'] as int? ?? 0;
          _currentPace = (data['average_pace'] as num?)?.toDouble() ?? 0.0;
          _lastUpdate = data['last_location_update'] != null
              ? DateTime.parse(data['last_location_update'])
              : null;

          // Update current location
          if (data['current_location'] != null) {
            final loc = data['current_location'];
            _currentLocation = LatLng(
              (loc['latitude'] as num).toDouble(),
              (loc['longitude'] as num).toDouble(),
            );
          }

          // Update route
          if (data['route'] != null && data['route'] is List) {
            _route = (data['route'] as List).map((point) {
              return LatLng(
                (point['lat'] as num).toDouble(),
                (point['lng'] as num).toDouble(),
              );
            }).toList();
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error('[LIVE_FOLLOWING] Error loading live data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Show error to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load live data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSendingMessage) return;

    setState(() {
      _isSendingMessage = true;
    });

    try {
      await _apiClient.post('/rucks/${widget.ruckId}/messages', {
        'message': message,
        'voice_id': _selectedVoice,
      });

      _messageController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Message sent to ${widget.ruckerName}! 🎤'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('[LIVE_FOLLOWING] Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingMessage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final preferMetric = authState is Authenticated ? authState.user.preferMetric : true;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text('${widget.ruckerName}\'s Ruck'),
            Text(
              '🔴 LIVE',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Map showing live location
                Expanded(
                  flex: 2,
                  child: _buildMap(),
                ),

                // Stats
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Theme.of(context).cardColor,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat(
                        'Distance',
                        MeasurementUtils.formatDistance(_currentDistance, metric: preferMetric),
                        Icons.straighten,
                      ),
                      _buildStat(
                        'Time',
                        _formatDuration(_currentDuration),
                        Icons.timer,
                      ),
                      _buildStat(
                        'Pace',
                        MeasurementUtils.formatPace(_currentPace, metric: preferMetric),
                        Icons.speed,
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Message input
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Voice selector
                      DropdownButtonFormField<String>(
                        value: _selectedVoice,
                        decoration: const InputDecoration(
                          labelText: 'Voice',
                          prefixIcon: Icon(Icons.record_voice_over),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        ),
                        isExpanded: true,
                        items: _voiceOptions.map((voice) {
                          return DropdownMenuItem(
                            value: voice['id'],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    voice['name']!,
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                  Text(
                                    voice['desc']!,
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedVoice = value;
                            });
                          }
                        },
                        menuMaxHeight: 300,
                      ),
                      const SizedBox(height: 12),

                      // Message input
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              maxLength: 200,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: 'Send encouragement...',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: _isSendingMessage
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            color: AppColors.primary,
                            iconSize: 32,
                            onPressed: _isSendingMessage ? null : _sendMessage,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMap() {
    if (_currentLocation == null) {
      return const Center(child: Text('Waiting for location...'));
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: _currentLocation!,
        initialZoom: 15.0,
        minZoom: 3,
        maxZoom: 18,
      ),
      children: [
        SafeTileLayer(
          style: 'stamen_terrain',
          retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
          onTileError: () {
            AppLogger.warning('Map tile loading error in live following');
          },
        ),
        // Route polyline
        if (_route.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _route,
                color: AppColors.secondary.withOpacity(0.6),
                strokeWidth: 4,
              ),
            ],
          ),
        // Current location marker
        MarkerLayer(
          markers: [
            Marker(
              point: _currentLocation!,
              width: 40,
              height: 40,
              child: Icon(
                Icons.person_pin_circle,
                color: AppColors.primary,
                size: 40,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}
