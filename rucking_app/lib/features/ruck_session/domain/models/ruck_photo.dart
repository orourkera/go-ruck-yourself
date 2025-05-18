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
    return RuckPhoto(
      id: json['id'].toString(),
      ruckId: json['ruck_id'].toString(),
      userId: json['user_id'].toString(),
      filename: json['filename'],
      originalFilename: json['original_filename'],
      contentType: json['content_type'],
      size: json['size'],
      createdAt: DateTime.parse(json['created_at']),
      url: json['url'],
      thumbnailUrl: json['thumbnail_url'],
    );
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
