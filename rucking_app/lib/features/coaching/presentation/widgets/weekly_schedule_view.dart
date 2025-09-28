import 'package:flutter/material.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class WeeklyScheduleView extends StatelessWidget {
  final Map<String, dynamic> planData;
  final int currentWeek;

  const WeeklyScheduleView({
    Key? key,
    required this.planData,
    required this.currentWeek,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Get actual plan sessions to determine real structure
    final planSessions = planData['plan_sessions'] as List? ?? [];

    // Don't show anything if we don't have real data
    if (planSessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'No plan sessions found',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress indicator
        _buildProgressIndicator(context),
        const SizedBox(height: 20),

        // Session list view
        _buildSessionsList(context),
      ],
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    final planSessions = planData['plan_sessions'] as List? ?? [];
    final completedCount = planSessions.where((s) => s['completion_status'] == 'completed').length;
    final totalCount = planSessions.length;
    final progressPercent = totalCount > 0 ? (completedCount / totalCount * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$completedCount of $totalCount sessions completed',
                style: AppTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              Text(
                '${progressPercent.toStringAsFixed(0)}%',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progressPercent / 100,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsList(BuildContext context) {
    final planSessions = planData['plan_sessions'] as List? ?? [];
    final today = DateTime.now();
    final dateFormat = DateFormat('EEE, MMM d');

    // Sort sessions by scheduled_date
    final sortedSessions = List.from(planSessions)
      ..sort((a, b) => DateTime.parse(a['scheduled_date'])
          .compareTo(DateTime.parse(b['scheduled_date'])));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: sortedSessions.asMap().entries.map((entry) {
          final index = entry.key;
          final session = entry.value;
          final sessionDate = DateTime.parse(session['scheduled_date']);
          final isToday = DateUtils.isSameDay(sessionDate, today);
          final isPast = sessionDate.isBefore(today) && !isToday;
          final isCompleted = session['completion_status'] == 'completed';

          // Parse coaching points
          Map<String, dynamic> coachingPoints = {};
          if (session['coaching_points'] is String) {
            try {
              coachingPoints = jsonDecode(session['coaching_points']);
            } catch (e) {}
          }

          return Container(
            decoration: BoxDecoration(
              color: isToday ? AppColors.primary.withOpacity(0.05) :
                     isCompleted ? Colors.green.withOpacity(0.05) : null,
              border: index < sortedSessions.length - 1
                ? Border(bottom: BorderSide(color: Colors.grey.shade300))
                : null,
            ),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green :
                         isToday ? AppColors.primary :
                         isPast ? Colors.grey.shade400 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isCompleted
                  ? Icon(Icons.check, color: Colors.white)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          sessionDate.day.toString(),
                          style: AppTextStyles.titleMedium.copyWith(
                            color: (isToday || isPast) ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('MMM').format(sessionDate),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: (isToday || isPast) ? Colors.white : Colors.grey[600],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
              ),
              title: Text(
                session['planned_session_type'] ?? 'Session',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateFormat.format(sessionDate),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  if (coachingPoints['target_weight_kg'] != null ||
                      coachingPoints['target_duration_minutes'] != null)
                    Text(
                      _buildSessionDetails(coachingPoints),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
              trailing: _buildTrailingMetrics(coachingPoints),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget? _buildTrailingMetrics(Map<String, dynamic> coachingPoints) {
    final duration = coachingPoints['target_duration_minutes'];
    final distance = coachingPoints['target_distance_km'] ?? coachingPoints['distance_km'];
    if (duration == null && distance == null) return null;

    final chips = <Widget>[];
    if (duration != null) {
      chips.add(_metricChip('${duration} min'));
    }
    if (distance != null) {
      final distanceValue = (distance is num) ? distance.toStringAsFixed(distance % 1 == 0 ? 0 : 1) : distance.toString();
      chips.add(_metricChip('$distanceValue km'));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: chips,
    );
  }

  Widget _metricChip(String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _buildSessionDetails(Map<String, dynamic> coachingPoints) {
    final parts = <String>[];
    final duration = coachingPoints['target_duration_minutes'];
    final distance = coachingPoints['target_distance_km'] ?? coachingPoints['distance_km'];
    final weight = coachingPoints['target_weight_kg'];

    if (duration != null) {
      parts.add('${duration} min');
    }
    if (distance != null) {
      final distanceValue = (distance is num) ? distance.toStringAsFixed(distance % 1 == 0 ? 0 : 1) : distance.toString();
      parts.add('$distanceValue km');
    }
    if (weight != null) {
      final weightValue = (weight is num) ? weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1) : weight.toString();
      parts.add('$weightValue kg');
    }
    return parts.join(' • ');
  }

  Widget _buildUpcomingSessions(BuildContext context) {
    // Get sessions for the current week from plan_sessions
    final planSessions = planData['plan_sessions'] as List? ?? [];

    // Filter sessions for the current week
    final currentWeekSessions = planSessions.where((session) {
      return session['week'] == currentWeek;
    }).toList();

    if (currentWeekSessions.isEmpty) return const SizedBox.shrink();

    // Find the next upcoming session
    final now = DateTime.now();
    Map<String, dynamic>? nextSession;

    for (var session in currentWeekSessions) {
      if (session['scheduled_date'] != null) {
        final sessionDate = DateTime.parse(session['scheduled_date']);
        if (sessionDate.isAfter(now) || DateUtils.isSameDay(sessionDate, now)) {
          nextSession = session;
          break;
        }
      }
    }

    if (nextSession == null && currentWeekSessions.isNotEmpty) {
      nextSession = currentWeekSessions.first;
    }

    if (nextSession == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.secondary.withOpacity(0.1),
            AppColors.secondary.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.secondary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag,
                size: 20,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'NEXT SESSION',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            nextSession['description'] ?? 'Training Session',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (nextSession['distance_km'] != null)
                _buildMetric(
                  Icons.straighten,
                  '${nextSession['distance_km']} km',
                ),
              if (nextSession['duration_minutes'] != null)
                _buildMetric(
                  Icons.timer,
                  '${nextSession['duration_minutes']} min',
                ),
              if (nextSession['weight_kg'] != null)
                _buildMetric(
                  Icons.fitness_center,
                  '${nextSession['weight_kg']} kg',
                ),
              if (nextSession['pace_per_km'] != null)
                _buildMetric(
                  Icons.speed,
                  nextSession['pace_per_km'],
                ),
            ],
          ),
          if (nextSession['notes'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppColors.textDarkSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      nextSession['notes'],
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textDarkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetric(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: AppColors.textDarkSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _getCurrentWeekSessions() {
    final planSessions = planData['plan_sessions'] ?? [];
    final weekSessions = <String, dynamic>{};
    final dayMapping = {
      1: 'mon', 2: 'tue', 3: 'wed',
      4: 'thu', 5: 'fri', 6: 'sat', 7: 'sun'
    };

    // Get current week's Monday and Sunday
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(Duration(days: 6));

    for (var session in planSessions) {
      final scheduledDate = session['scheduled_date'];
      if (scheduledDate != null) {
        final sessionDate = DateTime.parse(scheduledDate);

        // Check if this session falls within the current week
        if (sessionDate.isAfter(startOfWeek.subtract(Duration(days: 1))) &&
            sessionDate.isBefore(endOfWeek.add(Duration(days: 1)))) {

          final dayName = dayMapping[sessionDate.weekday];

          if (dayName != null) {
            // Parse coaching points for duration/distance
            Map<String, dynamic> coachingPoints = {};
            if (session['coaching_points'] is String) {
              try {
                coachingPoints = jsonDecode(session['coaching_points']);
              } catch (e) {
                // Ignore JSON parse errors
              }
            } else if (session['coaching_points'] is Map) {
              coachingPoints = Map<String, dynamic>.from(session['coaching_points']);
            }

            weekSessions[dayName] = {
              'type': session['planned_session_type']?.toString().toLowerCase().replaceAll(' ', '_'),
              'session_type': session['planned_session_type'],
              'duration': coachingPoints['target_duration_minutes'] ?? session['duration_minutes'],
              'distance': coachingPoints['distance_km'] ?? session['distance_km'],
              'weight_kg': coachingPoints['target_weight_kg'] ?? session['weight_kg'],
              'completion_status': session['completion_status'],
              'scheduled_date': scheduledDate,
              'description': session['description'],
              'notes': session['notes'],
              'id': session['id']
            };
          }
        }
      }
    }

    return weekSessions;
  }

  Map<String, dynamic> _getWeekSessions(int week) {
    final planSessions = planData['plan_sessions'] ?? [];
    final weekSessions = <String, dynamic>{};
    final dayMapping = {
      1: 'mon', 2: 'tue', 3: 'wed',
      4: 'thu', 5: 'fri', 6: 'sat', 7: 'sun'
    };

    // Calculate the start and end of the target week
    final planStartDate = DateTime.parse(planData['start_date']);
    final targetWeekStart = planStartDate.add(Duration(days: (week - 1) * 7));
    final targetWeekEnd = targetWeekStart.add(Duration(days: 6));

    for (var session in planSessions) {
      final scheduledDate = session['scheduled_date'];
      if (scheduledDate != null) {
        final sessionDate = DateTime.parse(scheduledDate);

        // Check if this session falls within the target week
        if (sessionDate.isAfter(targetWeekStart.subtract(Duration(days: 1))) &&
            sessionDate.isBefore(targetWeekEnd.add(Duration(days: 1)))) {

          final dayName = dayMapping[sessionDate.weekday];

          if (dayName != null) {
            // Parse coaching points for duration/distance
            Map<String, dynamic> coachingPoints = {};
            if (session['coaching_points'] is String) {
              try {
                coachingPoints = jsonDecode(session['coaching_points']);
              } catch (e) {
                // Ignore JSON parse errors
              }
            } else if (session['coaching_points'] is Map) {
              coachingPoints = Map<String, dynamic>.from(session['coaching_points']);
            }

            weekSessions[dayName] = {
              'type': session['planned_session_type']?.toString().toLowerCase().replaceAll(' ', '_'),
              'session_type': session['planned_session_type'],
              'duration': coachingPoints['target_duration_minutes'] ?? session['duration_minutes'],
              'distance': coachingPoints['distance_km'] ?? session['distance_km'],
              'weight_kg': coachingPoints['target_weight_kg'] ?? session['weight_kg'],
              'completion_status': session['completion_status'],
              'scheduled_date': scheduledDate,
              'description': session['description'],
              'notes': session['notes'],
              'id': session['id']
            };
          }
        }
      }
    }

    return weekSessions;
  }

  String _getSessionTitle(Map<String, dynamic> session) {
    final sessionType = session['session_type'] ?? session['type'];
    return sessionType?.toString() ?? '';
  }

  String _getSessionDescription(Map<String, dynamic> session) {
    final parts = <String>[];

    if (session['distance'] != null && session['distance'] > 0) {
      parts.add('${session['distance'].toStringAsFixed(1)} km');
    }

    if (session['weight_kg'] != null && session['weight_kg'] > 0) {
      parts.add('${session['weight_kg'].toStringAsFixed(0)} kg');
    }

    return parts.isNotEmpty ? parts.join(' • ') : 'Training session';
  }

  String _getSessionDuration(Map<String, dynamic> session) {
    final duration = session['duration'];
    return duration != null ? '$duration min' : '';
  }

  String _getIntensityDescription(String? type) {
    return type ?? '';
  }

  Color _getSessionColor(String? type) {
    return Colors.blue;
  }
}