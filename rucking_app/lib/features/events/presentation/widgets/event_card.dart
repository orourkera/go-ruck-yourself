import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rucking_app/features/events/domain/models/event.dart';
import 'package:rucking_app/shared/theme/app_colors.dart';
import 'package:rucking_app/shared/theme/app_text_styles.dart';

class EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback? onTap;
  final VoidCallback? onJoinTap;

  const EventCard({
    Key? key,
    required this.event,
    this.onTap,
    this.onJoinTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: isDarkMode ? AppColors.primary : Colors.grey.shade300,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          color: isDarkMode ? Colors.black : null,
          child: Column(
            children: [
              // Club info and location above image
              if (event.hostingClub != null || event.locationName != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Club info row
                      if (event.hostingClub != null)
                        Row(
                          children: [
                            // Club logo
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: event.hostingClub!.logoUrl != null && event.hostingClub!.logoUrl!.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        event.hostingClub!.logoUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).primaryColor,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Center(
                                              child: Text(
                                                event.hostingClub!.name.isNotEmpty 
                                                    ? event.hostingClub!.name[0].toUpperCase() 
                                                    : 'C',
                                                style: AppTextStyles.bodySmall.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        event.hostingClub!.name.isNotEmpty 
                                            ? event.hostingClub!.name[0].toUpperCase() 
                                            : 'C',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            // Club name
                            Expanded(
                              child: Text(
                                event.hostingClub!.name,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: isDarkMode ? Colors.white : AppColors.textDark,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      
                      // Location below club info
                      if (event.locationName != null && event.locationName!.isNotEmpty) ...[
                        if (event.hostingClub != null) const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.locationName!,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

              // Banner image (taller like ruck buddy card)
              if (event.bannerImageUrl != null)
                ClipRRect(
                  borderRadius: event.hostingClub != null || event.locationName != null
                      ? BorderRadius.zero // No top radius if content above
                      : const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                  child: Image.network(
                    event.bannerImageUrl!,
                    height: 200, // Same height as ruck buddy card
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 200,
                        width: double.infinity,
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        child: Icon(
                          Icons.event,
                          size: 60,
                          color: Theme.of(context).primaryColor,
                        ),
                      );
                    },
                  ),
                ),
              
              // Event details below image (no location repetition)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Event title (no icon)
                    Text(
                      event.title,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: isDarkMode ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Date and time
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDateTime(event.scheduledStartTime),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    
                    // Description if available
                    if (event.description != null && event.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        event.description!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    
                    const SizedBox(height: 12),
                    
                    // Bottom row with participants and action
                    Row(
                      children: [
                        // Status badge
                        _buildStatusBadge(context),
                        
                        const SizedBox(width: 12),
                        
                        // Participants count
                        if (event.participantCount > 0 || event.maxParticipants != null)
                          Row(
                            children: [
                              Icon(
                                Icons.people,
                                size: 14,
                                color: Theme.of(context).primaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${event.participantCount}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (event.maxParticipants != null)
                                Text(
                                  '/${event.maxParticipants}',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        
                        const Spacer(),
                        
                        // Action buttons
                        _buildActionButtons(context),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    if (event.userParticipationStatus != null) {
      Color badgeColor;
      String badgeText;
      
      switch (event.userParticipationStatus) {
        case 'approved':
          badgeColor = Colors.green;
          badgeText = 'Joined';
          break;
        case 'pending':
          badgeColor = Colors.orange;
          badgeText = 'Pending';
          break;
        case 'rejected':
          badgeColor = Colors.red;
          badgeText = 'Rejected';
          break;
        default:
          return const SizedBox.shrink();
      }
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          badgeText,
          style: AppTextStyles.bodySmall.copyWith(
            color: badgeColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildActionButtons(BuildContext context) {
    final isUpcoming = event.isUpcoming;
    final canJoin = event.canJoin;
    
    if (event.isPast || event.isCancelled) {
      return const SizedBox.shrink();
    }
    
    if (canJoin && onJoinTap != null) {
      return ElevatedButton(
        onPressed: event.isFull ? null : onJoinTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(event.isFull ? 'Full' : 'Join'),
      );
    }
    
    return const SizedBox.shrink();
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = dateTime.difference(now);
    
    if (difference.inDays > 7) {
      return DateFormat('MMM d, y').format(dateTime);
    } else if (difference.inDays > 0) {
      return DateFormat('E, MMM d').format(dateTime);
    } else if (difference.inDays == 0) {
      return 'Today ${DateFormat('h:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }
}
