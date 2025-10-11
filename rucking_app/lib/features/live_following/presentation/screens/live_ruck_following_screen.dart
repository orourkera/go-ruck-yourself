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
import 'package:rucking_app/features/ai_cheerleader/services/elevenlabs_service.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/features/ruck_buddies/presentation/pages/ruck_buddy_detail_screen.dart';
import 'package:rucking_app/shared/widgets/styled_snackbar.dart';

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
  String _selectedDelay = 'now';
  bool _sessionCompleted = false;  // Track if session has ended

  // Live session data
  double _currentDistance = 0.0;
  int _currentDuration = 0;
  double _currentPace = 0.0;
  LatLng? _currentLocation;
  List<LatLng> _route = [];
  DateTime? _lastUpdate;

  // Voice options (matching AI cheerleader personalities)
  final List<Map<String, String>> _voiceOptions = [
    {'id': 'supportive_friend', 'name': '🤗 Supportive Friend', 'desc': 'Warm & encouraging'},
    {'id': 'drill_sergeant', 'name': '🎖️ Drill Sergeant', 'desc': 'Intense & motivating'},
    {'id': 'southern_redneck', 'name': '🤠 Southern Redneck', 'desc': 'Y\'all got this!'},
    {'id': 'yoga_instructor', 'name': '🧘 Yoga Instructor', 'desc': 'Calm & mindful'},
    {'id': 'british_butler', 'name': '🎩 British Butler', 'desc': 'Proper & refined'},
    {'id': 'sports_commentator', 'name': '📢 Sports Commentator', 'desc': 'Energetic play-by-play'},
    {'id': 'cowboy', 'name': '🤠 Cowboy/Cowgirl', 'desc': 'Giddy up partner!'},
    {'id': 'nature_lover', 'name': '🌲 Nature Lover', 'desc': 'Peaceful & connected'},
    {'id': 'burt_reynolds', 'name': '😎 Burt Reynolds', 'desc': 'Smooth & confident'},
    {'id': 'tom_selleck', 'name': '🥸 Tom Selleck', 'desc': 'Charming & steady'},
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
        // Check if session is no longer active
        final isActive = data['is_active'] ?? true;
        final status = data['status']?.toString().toLowerCase();

        // Check if this is a stale session (no updates for over 1 hour)
        bool isStale = false;
        if (data['last_location_update'] != null) {
          final lastUpdate = DateTime.parse(data['last_location_update']);
          final hoursSinceUpdate = DateTime.now().difference(lastUpdate).inHours;
          if (hoursSinceUpdate >= 1) {
            isStale = true;
          }
        } else if (data['started_at'] != null) {
          // Fallback to started_at if no location updates
          final startedAt = DateTime.parse(data['started_at']);
          final hoursSinceStart = DateTime.now().difference(startedAt).inHours;
          if (hoursSinceStart >= 12) {  // Consider stale after 12 hours from start
            isStale = true;
          }
        }

        if (!isActive || status == 'completed' || status == 'stopped' || isStale) {
          // Stop refreshing
          _refreshTimer?.cancel();

          // If it's stale, redirect to completed ruck view
          if (isStale && mounted) {
            StyledSnackBar.show(
              context: context,
              message: 'This ruck session appears to be inactive',
              type: SnackBarType.normal,
              duration: const Duration(seconds: 2),
            );

            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => RuckBuddyDetailScreen.fromRuckId(
                      widget.ruckId,
                    ),
                  ),
                );
              }
            });
            return;
          }

          // Mark session as completed and update UI
          if (mounted) {
            setState(() {
              _sessionCompleted = true;
              _isLoading = false;
            });
          }
          return;
        }

        setState(() {
          // Handle null values from API - session might be new
          _currentDistance = (data['distance_km'] as num?)?.toDouble() ?? _currentDistance;
          _currentDuration = data['duration_seconds'] as int? ?? _currentDuration;
          _currentPace = (data['average_pace'] as num?)?.toDouble() ?? _currentPace;
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

        final errorString = e.toString().toLowerCase();

        // For BadRequestException (400), the ruck is likely completed
        bool isCompleted = false;
        if (errorString.contains('badrequestexception') ||
            errorString.contains('bad request') ||
            errorString.contains('400')) {
          isCompleted = true;
        }

        // Check different error scenarios
        if (errorString.contains('403')) {
          // Permission denied - either live following disabled or not following user
          _refreshTimer?.cancel();

          String message = 'Unable to view live ruck';
          if (errorString.contains('must follow')) {
            message = 'You must follow ${widget.ruckerName} to view their live ruck';
          } else if (errorString.contains('disabled')) {
            message = '${widget.ruckerName} has disabled live following for this ruck';
          }

          StyledSnackBar.show(
            context: context,
            message: message,
            type: SnackBarType.error,
            duration: const Duration(seconds: 3),
          );

          // Go back to previous screen
          Navigator.of(context).pop();

        } else if (isCompleted ||
                   errorString.contains('not currently active') ||
                   errorString.contains('404') ||
                   errorString.contains('not found')) {
          // Session ended - stop refreshing and redirect to completed ruck
          _refreshTimer?.cancel();

          if (mounted) {
            // Show a message that the session has ended first
            StyledSnackBar.showSuccess(
              context: context,
              message: '${widget.ruckerName}\'s ruck has completed',
              duration: const Duration(seconds: 2),
            );

            // Then navigate to the completed ruck detail screen
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => RuckBuddyDetailScreen.fromRuckId(
                      widget.ruckId,
                    ),
                  ),
                );
              }
            });
          }
        } else {
          // Generic error
          StyledSnackBar.showError(
            context: context,
            message: 'Unable to load live ruck data',
            duration: const Duration(seconds: 3),
          );
        }
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
      // Get ElevenLabs API key from storage
      final storageService = GetIt.I<StorageService>();
      final apiKey = await storageService.getString('elevenlabs_api_key');

      String? audioUrl;

      if (apiKey != null && apiKey.isNotEmpty) {
        // Generate audio client-side using existing ElevenLabs service
        final elevenlabs = ElevenLabsService(apiKey);
        final audioBytes = await elevenlabs.synthesizeSpeech(
          text: message,
          personality: _selectedVoice,
        );

        if (audioBytes != null) {
          // Upload audio to backend (backend will store in Supabase)
          // For now, send without audio - TODO: implement audio upload
          AppLogger.info('[LIVE_FOLLOWING] Generated ${audioBytes.length} bytes of audio');
        }
      }

      // Send message (with or without audio)
      final Map<String, dynamic> payload = {
        'message': message,
        'voice_id': _selectedVoice,
      };

      // Add delay if selected
      if (_selectedDelay != 'now') {
        payload['delay_minutes'] = int.parse(_selectedDelay);
      }

      await _apiClient.post('/rucks/${widget.ruckId}/messages', payload);

      _messageController.clear();

      if (mounted) {
        StyledSnackBar.showSuccess(
          context: context,
          message: 'Message sent to ${widget.ruckerName}! 🎤',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      AppLogger.error('[LIVE_FOLLOWING] Error sending message: $e');
      if (mounted) {
        StyledSnackBar.showError(
          context: context,
          message: 'Failed to send message',
          duration: const Duration(seconds: 3),
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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Column(
          children: [
            Text('${widget.ruckerName}\'s Ruck'),
            Text(
              _sessionCompleted ? 'COMPLETED' : 'LIVE',
              style: TextStyle(
                fontSize: 12,
                color: _sessionCompleted ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Show completion banner if session ended
                  if (_sessionCompleted)
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.green.shade50,
                      child: Column(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.ruckerName} has completed their ruck!',
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Live tracking has ended.',
                            style: AppTextStyles.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => RuckBuddyDetailScreen.fromRuckId(widget.ruckId),
                                ),
                              );
                            },
                            icon: const Icon(Icons.visibility),
                            label: const Text('View Completed Ruck Details'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Map showing live location (reduced height)
                  SizedBox(
                    height: 200,
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

                  // Message input section (disabled if session completed)
                  if (!_sessionCompleted)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Voice selector (compact)
                          Row(
                          children: [
                            const Icon(Icons.record_voice_over, size: 16),
                            const SizedBox(width: 8),
                            const Text('Voice:', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _selectedVoice,
                                isExpanded: true,
                                isDense: true,
                                items: _voiceOptions.map((voice) {
                                  return DropdownMenuItem(
                                    value: voice['id'],
                                    child: Text(voice['name']!, style: const TextStyle(fontSize: 13)),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedVoice = value;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Delay selector (compact)
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 16),
                            const SizedBox(width: 8),
                            const Text('Send:', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _selectedDelay,
                                isExpanded: true,
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(value: 'now', child: Text('Now')),
                                  DropdownMenuItem(value: '5', child: Text('In 5 min')),
                                  DropdownMenuItem(value: '15', child: Text('In 15 min')),
                                  DropdownMenuItem(value: '30', child: Text('In 30 min')),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedDelay = value;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

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

                        // Add padding at the bottom to account for keyboard
                        SizedBox(
                          height: MediaQuery.of(context).viewInsets.bottom,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
        // Current location marker (matching active session style)
        MarkerLayer(
          markers: [
            Marker(
              point: _currentLocation!,
              width: 30,
              height: 30,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 16,
                ),
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
