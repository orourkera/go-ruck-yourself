import 'package:share_plus/share_plus.dart';
import 'package:rucking_app/features/clubs/domain/models/club.dart';

class ClubShareService {
  static Future<void> shareClub(ClubDetails clubDetails) async {
    try {
      // Create a beautiful share message with club details
      final String shareText = _buildShareText(clubDetails);

      // Share using the native share sheet
      final result = await Share.share(
        shareText,
        subject: 'Join ${clubDetails.club.name} on Ruck!',
      );

      if (result.status == ShareResultStatus.success) {
        print('Club shared successfully');
      } else if (result.status == ShareResultStatus.dismissed) {
        print('Share dismissed by user');
      }
    } catch (e) {
      print('Error sharing club: $e');
      // Fallback to text-only sharing
      await _shareTextOnly(clubDetails);
    }
  }

  static String _buildShareText(ClubDetails clubDetails) {
    final club = clubDetails.club;

    // Base share text with club details
    String shareText = '''🏃‍♂️ Join ${club.name} on Ruck!

${club.description != null && club.description!.isNotEmpty ? '${club.description}\n\n' : ''}📍 ${club.location}
👥 ${club.memberCount} members
📅 Created ${_formatDate(club.createdAt)}

Join this amazing rucking community and start your fitness journey with us!

Download Ruck and join the club:
https://getrucky.com/clubs/${club.id}

#Ruck #Fitness #Community''';

    return shareText;
  }

  static Future<void> _shareTextOnly(ClubDetails clubDetails) async {
    try {
      final String shareText = '''🏃‍♂️ Join ${clubDetails.club.name} on Ruck!

${clubDetails.club.description != null && clubDetails.club.description!.isNotEmpty ? '${clubDetails.club.description}\n\n' : ''}📍 ${clubDetails.club.location}
👥 ${clubDetails.club.memberCount} members

Download the Ruck app to join this amazing rucking community!

#Ruck #Fitness #Community''';

      await Share.share(shareText);
    } catch (e) {
      print('Error in fallback text sharing: $e');
    }
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks} week${weeks > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '${months} month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '${years} year${years > 1 ? 's' : ''} ago';
    }
  }
}
