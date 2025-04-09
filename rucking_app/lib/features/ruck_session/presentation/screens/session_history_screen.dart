import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:intl/intl.dart';

/// Screen for viewing ruck session history
class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({Key? key}) : super(key: key);

  @override
  _SessionHistoryScreenState createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  final ApiClient _apiClient = GetIt.instance<ApiClient>();
  bool _isLoading = true;
  List<dynamic> _sessions = [];
  String _activeFilter = 'All';

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  /// Fetches sessions from the API
  Future<void> _fetchSessions() async {
    try {
      // Build endpoint based on active filter
      String endpoint = '/api/rucks';
      
      if (_activeFilter == 'This Week') {
        final now = DateTime.now();
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final startDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        endpoint = '/api/rucks?start_date=${startDate.toIso8601String()}';
      } else if (_activeFilter == 'This Month') {
        final now = DateTime.now();
        final startOfMonth = DateTime(now.year, now.month, 1);
        endpoint = '/api/rucks?start_date=${startOfMonth.toIso8601String()}';
      } else if (_activeFilter == 'Last Month') {
        final now = DateTime.now();
        final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
        final endOfLastMonth = DateTime(now.year, now.month, 0);
        endpoint = '/api/rucks?start_date=${startOfLastMonth.toIso8601String()}&end_date=${endOfLastMonth.toIso8601String()}';
      }
      
      final response = await _apiClient.get(endpoint);
      
      setState(() {
        if (response == null) {
          _sessions = [];
        } else if (response is List) {
          _sessions = response;
        } else if (response is Map && response.containsKey('data') && response['data'] is List) {
          _sessions = response['data'] as List;
        } else {
          _sessions = [];
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
      setState(() {
        _sessions = [];
        _isLoading = false;
      });
    }
  }

  /// Apply a filter and fetch sessions again
  void _applyFilter(String filter) {
    setState(() {
      _activeFilter = filter;
      _isLoading = true;
    });
    _fetchSessions();
  }

  @override
  Widget build(BuildContext context) {
    // Get user's metric preference
    bool preferMetric = true;
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      preferMetric = authState.user.preferMetric;
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // Show filter options in bottom sheet
              showModalBottomSheet(
                context: context,
                builder: (context) => _buildFilterBottomSheet(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', _activeFilter == 'All'),
                  _buildFilterChip('This Week', _activeFilter == 'This Week'),
                  _buildFilterChip('This Month', _activeFilter == 'This Month'),
                  _buildFilterChip('Last Month', _activeFilter == 'Last Month'),
                  _buildFilterChip('Custom', _activeFilter == 'Custom'),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          
          // Sessions list or loading indicator
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _sessions.isEmpty
                ? // Empty state message
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_outlined,
                          size: 64,
                          color: AppColors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No sessions found',
                          style: AppTextStyles.subtitle1.copyWith(
                            color: AppColors.textDarkSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _activeFilter == 'All'
                              ? 'Your ruck session history will appear here'
                              : 'No sessions found for this time period',
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.textDarkSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : // Session list
                  ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      
                      // Format date
                      final dateString = session['created_at'] ?? '';
                      final date = DateTime.tryParse(dateString) ?? DateTime.now();
                      final formattedDate = DateFormat('MMMM d, yyyy • h:mm a').format(date);
                      
                      // Get duration
                      final durationSecs = session['duration_seconds'] ?? 0;
                      final duration = Duration(seconds: durationSecs);
                      final hours = duration.inHours;
                      final minutes = duration.inMinutes % 60;
                      final durationText = hours > 0 
                          ? '${hours}h ${minutes}m' 
                          : '${minutes}m';
                      
                      // Get distance
                      final distanceKm = session['distance_km'] ?? 0.0;
                      final distanceValue = preferMetric 
                          ? distanceKm.toStringAsFixed(2) 
                          : (distanceKm * 0.621371).toStringAsFixed(2);
                      final distanceUnit = preferMetric ? 'km' : 'mi';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () {
                            // TODO: Navigate to session details
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formattedDate,
                                  style: AppTextStyles.subtitle2.copyWith(
                                    color: AppColors.textDarkSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSessionStat(
                                        Icons.timer,
                                        'Duration',
                                        durationText,
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildSessionStat(
                                        Icons.straighten,
                                        'Distance',
                                        '$distanceValue $distanceUnit',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSessionStat(
                                        Icons.local_fire_department,
                                        'Calories',
                                        '${session['calories_burned'] ?? 0}',
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildSessionStat(
                                        Icons.fitness_center,
                                        'Weight',
                                        '${session['ruck_weight_kg'] ?? 0} kg',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Builds a filter chip for the filter bar
  Widget _buildFilterChip(String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          if (selected) {
            _applyFilter(label);
          }
        },
        selectedColor: AppColors.primary.withOpacity(0.2),
        checkmarkColor: AppColors.primary,
        labelStyle: AppTextStyles.caption.copyWith(
          color: isSelected ? AppColors.primary : AppColors.textDark,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
  
  /// Builds the filter bottom sheet
  Widget _buildFilterBottomSheet() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter Sessions',
            style: AppTextStyles.headline6,
          ),
          const SizedBox(height: 16),
          _buildFilterOption('All', Icons.list),
          _buildFilterOption('This Week', Icons.date_range),
          _buildFilterOption('This Month', Icons.calendar_today),
          _buildFilterOption('Last Month', Icons.history),
          _buildFilterOption('Custom', Icons.tune),
        ],
      ),
    );
  }
  
  /// Builds a filter option for the bottom sheet
  Widget _buildFilterOption(String label, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: _activeFilter == label ? AppColors.primary : null),
      title: Text(label),
      selected: _activeFilter == label,
      selectedTileColor: AppColors.primary.withOpacity(0.1),
      onTap: () {
        Navigator.pop(context);
        _applyFilter(label);
      },
    );
  }
  
  /// Builds a session statistic item
  Widget _buildSessionStat(IconData icon, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: AppColors.textDarkSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textDarkSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.body1.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
} 