import 'package:equatable/equatable.dart';

/// Model representing a photo attached to a ruck session
class RuckPhoto extends Equatable {
  final String id;
  final String ruckId;
  final String userId;
  final String filename;
  final String? originalFilename;
  final String? contentType;
  final int? size;
  final DateTime createdAt;
  final String? url;
  final String? thumbnailUrl;

  const RuckPhoto({
    required this.id,
    required this.ruckId,
    required this.userId,
    required this.filename,
    this.originalFilename,
    this.contentType,
    this.size,
    required this.createdAt,
    this.url,
    this.thumbnailUrl,
  });

  /// Create a RuckPhoto from JSON
  factory RuckPhoto.fromJson(Map<String, dynamic> json) {
    try {
      // Extract the primary data fields from backend response
      final String id = json['id']?.toString() ?? '';
      final String url = json['url']?.toString() ?? json['photo_url']?.toString() ?? '';
      final String thumbnailUrl = json['thumbnail_url']?.toString() ?? '';
      final String ruckId = json['ruck_id']?.toString() ?? json['ruck_session_id']?.toString() ?? '';
      final String userId = json['user_id']?.toString() ?? '';
      final String filename = json['filename']?.toString() ?? json['file_name']?.toString() ?? '';
      final String? originalFilename = json['original_filename']?.toString();
      final String? contentType = json['content_type']?.toString();
      final int? size = json['size'] is int ? json['size'] : (json['file_size'] is int ? json['file_size'] : null);
      
      // Handle the timestamp parsing with enhanced fallback options
      DateTime parsedAt;
      try {
        final dynamic timestamp = json['created_at'] ?? json['taken_at'] ?? json['uploaded_at'] ?? json['timestamp'];
        
        if (timestamp is String) {
          // Handle ISO format timestamps like "2023-XX-XXTXX:XX:XX.XXXXXXZ"
          parsedAt = DateTime.parse(timestamp);
        } else if (timestamp is int) {
          // Handle Unix timestamps (seconds)
          parsedAt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        } else if (timestamp is double) {
          // Handle Unix timestamps (milliseconds as double)
          parsedAt = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
        } else {
          // If all else fails, use current time
          parsedAt = DateTime.now();
        }
      } catch (e) {
        parsedAt = DateTime.now();
      }
      
      // Create and return the RuckPhoto object
      final photo = RuckPhoto(
        id: id,
        ruckId: ruckId,
        userId: userId,
        filename: filename,
        originalFilename: originalFilename,
        contentType: contentType,
        size: size,
        createdAt: parsedAt,
        url: url,
        thumbnailUrl: thumbnailUrl,
      );
      
      return photo;
      
    } catch (e, stack) {
      
      // Attempt to create a minimal RuckPhoto with fallback values
      try {
        final fallbackPhoto = RuckPhoto(
          id: json['id']?.toString() ?? '',
          ruckId: json['ruck_id']?.toString() ?? json['ruck_session_id']?.toString() ?? '',
          userId: json['user_id']?.toString() ?? '',
          filename: json['filename']?.toString() ?? json['file_name']?.toString() ?? '',
          createdAt: DateTime.now(),
          url: json['url']?.toString() ?? json['photo_url']?.toString() ?? '',
          thumbnailUrl: json['thumbnail_url']?.toString() ?? '',
        );
        return fallbackPhoto;
      } catch (fallbackError) {
        
        // Return an empty photo object as the absolute last resort
        return RuckPhoto(
          id: '',
          ruckId: '',
          userId: '',
          filename: '',
          createdAt: DateTime.now(),
          url: '',
          thumbnailUrl: '',
        );
      }
    }
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ruck_id': ruckId,
      'user_id': userId,
      'filename': filename,
      'original_filename': originalFilename,
      'content_type': contentType,
      'size': size,
      'created_at': createdAt.toIso8601String(),
      'url': url,
      'thumbnail_url': thumbnailUrl,
    };
  }

  @override
  List<Object?> get props => [
    id,
    ruckId,
    userId,
    filename,
    originalFilename,
    contentType,
    size,
    createdAt,
    url,
    thumbnailUrl,
  ];
  
  @override
  String toString() => 'RuckPhoto(id: $id, ruckId: $ruckId, filename: $filename)';
}
