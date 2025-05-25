import 'package:rucking_app/features/notifications/domain/entities/app_notification.dart';

/// Data model for notifications
class NotificationModel extends AppNotification {
  const NotificationModel({
    required String id,
    required String type,
    required String message,
    required DateTime createdAt,
    required bool isRead,
    Map<String, dynamic>? data,
  }) : super(
          id: id,
          type: type,
          message: message,
          createdAt: createdAt,
          isRead: isRead,
          data: data,
        );

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'].toString(),
      type: json['type']?.toString() ?? 'unknown',
      message: json['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      isRead: json['is_read'] == true || json['read'] == true,
      data: json['data'] is Map<String, dynamic> ? Map<String, dynamic>.from(json['data']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'message': message,
        'created_at': createdAt.toIso8601String(),
        'is_read': isRead,
        'data': data,
      };

  /// Create a new NotificationModel with updated fields
  NotificationModel copyWith({
    String? id,
    String? type,
    String? message,
    DateTime? createdAt,
    bool? isRead,
    Map<String, dynamic>? data,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      data: data ?? this.data,
    );
  }
}
