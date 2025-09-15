import 'package:equatable/equatable.dart';
import 'package:rucking_app/features/social_sharing/models/post_template.dart';

/// Model representing an Instagram post
class InstagramPost extends Equatable {
  final String caption;
  final List<String> hashtags;
  final String cta;
  final List<String> keyStats;
  final String highlight;
  final List<String> photos;
  final PostTemplate template;
  final DateTime? optimalPostTime;

  const InstagramPost({
    required this.caption,
    required this.hashtags,
    required this.cta,
    required this.keyStats,
    required this.highlight,
    required this.photos,
    required this.template,
    this.optimalPostTime,
  });

  /// Get the full formatted post text
  String get fullText {
    final buffer = StringBuffer();

    // Add caption
    buffer.writeln(caption);

    // Add CTA if present
    if (cta.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(cta);
    }

    // Add hashtags
    if (hashtags.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(hashtagString);
    }

    return buffer.toString();
  }

  /// Get hashtags as a formatted string
  String get hashtagString {
    return hashtags.map((tag) => '#${tag.replaceAll('#', '')}').join(' ');
  }

  /// Check if post is within Instagram limits
  bool get isValidLength {
    return fullText.length <= 2200;
  }

  /// Get character count
  int get characterCount {
    return fullText.length;
  }

  /// Get remaining characters
  int get remainingCharacters {
    return 2200 - characterCount;
  }

  /// Create a copy with updated fields
  InstagramPost copyWith({
    String? caption,
    List<String>? hashtags,
    String? cta,
    List<String>? keyStats,
    String? highlight,
    List<String>? photos,
    PostTemplate? template,
    DateTime? optimalPostTime,
  }) {
    return InstagramPost(
      caption: caption ?? this.caption,
      hashtags: hashtags ?? this.hashtags,
      cta: cta ?? this.cta,
      keyStats: keyStats ?? this.keyStats,
      highlight: highlight ?? this.highlight,
      photos: photos ?? this.photos,
      template: template ?? this.template,
      optimalPostTime: optimalPostTime ?? this.optimalPostTime,
    );
  }

  @override
  List<Object?> get props => [
        caption,
        hashtags,
        cta,
        keyStats,
        highlight,
        photos,
        template,
        optimalPostTime,
      ];
}