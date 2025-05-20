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
    // Add debug logging for every photo parsing
    print('[PHOTO_DEBUG] Parsing RuckPhoto from JSON keys: ${json.keys.join(', ')}');
    
    try {
      // Check all available keys for id
      final id = json['id']?.toString() ?? 
                 json['photo_id']?.toString() ?? 
                 json['_id']?.toString() ?? 
                 '';
      
      // Check all common variations of ruckId
      final ruckId = json['ruck_id']?.toString() ?? 
                     json['ruckId']?.toString() ?? 
                     json['session_id']?.toString() ?? 
                     '';
      
      // Check all common variations of userId
      final userId = json['user_id']?.toString() ?? 
                     json['userId']?.toString() ?? 
                     '';
      
      // Get filename or extract from URL if available
      String filename = json['filename'] ?? '';
      final url = json['url'] ?? json['photo_url'] ?? json['image_url'] ?? '';
      
      // If no filename but URL exists, extract filename from URL
      if (filename.isEmpty && url.isNotEmpty) {
        final uriObj = Uri.tryParse(url);
        if (uriObj != null) {
          final pathSegments = uriObj.pathSegments;
          if (pathSegments.isNotEmpty) {
            filename = pathSegments.last;
          }
        }
      }
      
      // Try multiple date formats for created_at
      DateTime createdAt;
      final createdAtStr = json['created_at'] ?? json['createdAt'] ?? json['timestamp'];
      if (createdAtStr != null) {
        try {
          createdAt = DateTime.parse(createdAtStr.toString());
        } catch (e) {
          print('[PHOTO_DEBUG] Error parsing date: $e, using current time instead');
          createdAt = DateTime.now();
        }
      } else {
        createdAt = DateTime.now();
      }
      
      // Look for thumbnail URL with various key names
      final thumbnailUrl = json['thumbnail_url'] ?? 
                           json['thumbnailUrl'] ?? 
                           json['thumb'] ?? 
                           json['thumbnail'] ?? 
                           url; // Fallback to main URL
      
      // Create the photo object
      final photo = RuckPhoto(
        id: id,
        ruckId: ruckId,
        userId: userId,
        filename: filename,
        originalFilename: json['original_filename'] ?? json['originalFilename'],
        contentType: json['content_type'] ?? json['contentType'] ?? json['mime_type'],
        size: json['size'] is int 
              ? json['size'] 
              : json['size'] is String 
                ? int.tryParse(json['size']) 
                : null,
        createdAt: createdAt,
        url: url,
        thumbnailUrl: thumbnailUrl,
      );
      
      print('[PHOTO_DEBUG] Successfully parsed photo: $photo');
      return photo;
    } catch (e, stack) {
      print('[PHOTO_DEBUG] Error parsing RuckPhoto: $e');
      print('[PHOTO_DEBUG] Stack trace: $stack');
      print('[PHOTO_DEBUG] JSON that caused the error: $json');
      
      // Return a fallback/default model instead of crashing
      try {
        return RuckPhoto(
          id: json['id']?.toString() ?? 'error-${DateTime.now().millisecondsSinceEpoch}',
          ruckId: json['ruck_id']?.toString() ?? '',
          userId: json['user_id']?.toString() ?? '',
          filename: json['filename'] ?? 'error.jpg',
          createdAt: DateTime.now(),
          url: json['url'] ?? '',
        );
      } catch (fallbackError) {
        print('[PHOTO_DEBUG] Even fallback creation failed: $fallbackError');
        // Absolute last resort fallback
        return RuckPhoto(
          id: 'error-${DateTime.now().millisecondsSinceEpoch}',
          ruckId: '',
          userId: '',
          filename: 'error.jpg',
          createdAt: DateTime.now(),
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
