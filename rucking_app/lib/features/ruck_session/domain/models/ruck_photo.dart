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
      // Extract the primary data fields
      final String id = json['id']?.toString() ?? '';
      final String url = json['photo_url']?.toString() ?? json['url']?.toString() ?? '';
      final String thumbnailUrl = json['thumbnail_url']?.toString() ?? '';
      final String ruckSessionId = json['ruck_session_id']?.toString() ?? '';
      
      // Handle the timestamp parsing with enhanced fallback options
      DateTime parsedAt;
      try {
        final dynamic timestamp = json['taken_at'] ?? json['created_at'] ?? json['timestamp'];
        
        if (timestamp is String) {
          // Handle ISO format timestamps like "2023-XX-XXTXX:XX:XX.XXXXXXZ"
          final cleanedTimestamp = timestamp.replaceAll('T', ' ').replaceAll('Z', '');
          parsedAt = DateTime.parse(cleanedTimestamp);
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
      
      // Extract optional metadata with safe parsing
      final Map<String, dynamic> metadata = {};
      if (json.containsKey('metadata') && json['metadata'] is Map) {
        metadata.addAll(Map<String, dynamic>.from(json['metadata']));
      }
      
      // Add location info to metadata if present in the root JSON object
      if (json.containsKey('latitude') && json.containsKey('longitude')) {
        final dynamic lat = json['latitude'];
        final dynamic lng = json['longitude'];
        
        if (lat != null && lng != null) {
          metadata['latitude'] = lat is String ? double.tryParse(lat) ?? 0.0 : lat.toDouble();
          metadata['longitude'] = lng is String ? double.tryParse(lng) ?? 0.0 : lng.toDouble();
        }
      }
      
      // Create and return the RuckPhoto object
      final photo = RuckPhoto(
        id: id,
        ruckId: ruckSessionId,
        userId: '',
        filename: '',
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
          ruckId: json['ruck_session_id']?.toString() ?? '',
          userId: '',
          filename: '',
          createdAt: DateTime.now(),
          url: json['photo_url']?.toString() ?? json['url']?.toString() ?? '',
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
