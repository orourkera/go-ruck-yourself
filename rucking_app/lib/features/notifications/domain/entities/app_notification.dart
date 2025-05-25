import 'package:equatable/equatable.dart';

/// Domain entity representing a user notification.
class AppNotification extends Equatable {
  final String id;
  final String type; // e.g., like, comment, follow
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? data; // extra payload for navigation

  const AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.createdAt,
    required this.isRead,
    this.data,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        message: message,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        data: data,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'].toString(),
        type: json['type']?.toString() ?? 'unknown',
        message: json['message']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
        isRead: json['is_read'] == true || json['read'] == true,
        data: json['data'] is Map<String, dynamic> ? Map<String, dynamic>.from(json['data']) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'message': message,
        'created_at': createdAt.toIso8601String(),
        'is_read': isRead,
        'data': data,
      };

  @override
  List<Object?> get props => [id, type, message, createdAt, isRead, data];
}
