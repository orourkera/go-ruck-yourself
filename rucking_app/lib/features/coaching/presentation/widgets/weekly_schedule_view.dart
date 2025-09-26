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
    final weeklyTemplate = planData['modifications']?['weekly_template'] ??
                          planData['template']?['base_structure']?['weekly_template'] ??
                          planData['plan_structure']?['weekly_template'] ?? [];
    final totalWeeks = planData['template']?['duration_weeks'] ??
                      planData['duration_weeks'];

    // Don't show anything if we don't have real data
    if (totalWeeks == null || totalWeeks == 0 ||
        planData['plan_sessions'] == null ||
        (planData['plan_sessions'] as List?)?.isEmpty == true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'No plan data found',
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
        // Week selector
        _buildWeekSelector(context, totalWeeks),
        const SizedBox(height: 20),

        // Weekly calendar view
        _buildWeekCalendar(context, weeklyTemplate),
        const SizedBox(height: 20),

        // Session details
        _buildUpcomingSessions(context),
      ],
    );
  }

  Widget _buildWeekSelector(BuildContext context, int totalWeeks) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Week $currentWeek of $totalWeeks',
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, color: AppColors.primary),
                onPressed: currentWeek > 1 ? () {} : null,
              ),
              IconButton(
                icon: Icon(Icons.chevron_right, color: AppColors.primary),
                onPressed: currentWeek < totalWeeks ? () {} : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekCalendar(BuildContext context, List<dynamic> weeklyTemplate) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));

    // Get the week's sessions from template or generate default
    final weekSessions = _getWeekSessions(currentWeek);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(7, (index) {
          final dayDate = startOfWeek.add(Duration(days: index));
          final dayName = days[index];
          final isToday = DateUtils.isSameDay(dayDate, today);
          final daySession = weekSessions[dayName.toLowerCase()];

          return Container(
            decoration: BoxDecoration(
              color: isToday ? AppColors.primary.withOpacity(0.05) : null,
              border: index < 6
                ? Border(bottom: BorderSide(color: Colors.grey.shade300))
                : null,
            ),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isToday ? AppColors.primary : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayName,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isToday ? Colors.white : Colors.grey[600],
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      dayDate.day.toString(),
                      style: AppTextStyles.titleMedium.copyWith(
                        color: isToday ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              title: daySession != null
                ? Text(
                    _getSessionTitle(daySession),
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Text(
                    'Rest Day',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              subtitle: daySession != null
                ? Text(
                    _getSessionDescription(daySession),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.grey[600],
                    ),
                  )
                : null,
              trailing: daySession != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getSessionColor(daySession['type']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _getSessionDuration(daySession),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: _getSessionColor(daySession['type']),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildUpcomingSessions(BuildContext context) {
    final nextSession = planData['recent_sessions']?.isNotEmpty == true
        ? planData['recent_sessions'][0]
        : planData['next_session'] ?? {};

    if (nextSession == null || nextSession.isEmpty) return const SizedBox.shrink();

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

  Map<String, dynamic> _getWeekSessions(int week) {
    final planSessions = planData['plan_sessions'] ?? [];
    final weekSessions = <String, dynamic>{};
    final dayMapping = {
      1: 'monday', 2: 'tuesday', 3: 'wednesday',
      4: 'thursday', 5: 'friday', 6: 'saturday', 0: 'sunday'
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

          final dayName = dayMapping[sessionDate.weekday % 7];
          final shortDay = dayName?.substring(0, 3);

          if (shortDay != null) {
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

            weekSessions[shortDay] = {
              'type': session['planned_session_type']?.toString().toLowerCase().replaceAll(' ', '_'),
              'session_type': session['planned_session_type'],
              'duration': coachingPoints['target_duration_minutes'],
              'distance': coachingPoints['distance_km'],
              'weight_kg': coachingPoints['target_weight_kg'],
              'completion_status': session['completion_status'],
              'scheduled_date': scheduledDate,
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
    final distance = session['distance'] ?? 0;
    final sessionType = session['session_type'] ?? session['type'] ?? '';
    return '${distance.toStringAsFixed(1)} km • ${sessionType.toString()}';
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