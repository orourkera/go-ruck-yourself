class Goal {
  final String id;
  final String userId;
  final String? title;
  final String? description;
  final String? targetType;
  final num? targetValue;
  final String? unit;
  final String? status;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? metadata;

  Goal({
    required this.id,
    required this.userId,
    this.title,
    this.description,
    this.targetType,
    this.targetValue,
    this.unit,
    this.status,
    this.startDate,
    this.endDate,
    this.createdAt,
    this.updatedAt,
    this.metadata,
  });

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      targetType:
          json['target_type']?.toString() ?? json['targetType']?.toString(),
      targetValue: json['target_value'] ?? json['targetValue'],
      unit: json['unit']?.toString(),
      status: json['status']?.toString(),
      startDate: _parseDate(json['start_date'] ?? json['startDate']),
      endDate: _parseDate(json['end_date'] ?? json['endDate']),
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: _parseDate(json['updated_at'] ?? json['updatedAt']),
      metadata: _ensureMap(json['metadata_json'] ?? json['metadata']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (targetType != null) 'target_type': targetType,
      if (targetValue != null) 'target_value': targetValue,
      if (unit != null) 'unit': unit,
      if (status != null) 'status': status,
      if (startDate != null) 'start_date': startDate!.toIso8601String(),
      if (endDate != null) 'end_date': endDate!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (metadata != null) 'metadata_json': metadata,
    };
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.tryParse(v.toString());
  }

  static Map<String, dynamic>? _ensureMap(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}
