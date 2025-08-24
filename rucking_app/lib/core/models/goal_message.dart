class GoalMessage {
  final String id;
  final String goalId;
  final String? channel;
  final String? messageType;
  final String? content;
  final Map<String, dynamic>? metadata;
  final DateTime? sentAt;
  final DateTime? createdAt;

  GoalMessage({
    required this.id,
    required this.goalId,
    this.channel,
    this.messageType,
    this.content,
    this.metadata,
    this.sentAt,
    this.createdAt,
  });

  factory GoalMessage.fromJson(Map<String, dynamic> json) {
    return GoalMessage(
      id: json['id']?.toString() ?? '',
      goalId: json['goal_id']?.toString() ?? json['goalId']?.toString() ?? '',
      channel: json['channel']?.toString(),
      messageType: json['message_type']?.toString() ?? json['messageType']?.toString(),
      content: json['content']?.toString(),
      metadata: _ensureMap(json['metadata_json'] ?? json['metadata']),
      sentAt: _parseDate(json['sent_at'] ?? json['sentAt']),
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'goal_id': goalId,
      if (channel != null) 'channel': channel,
      if (messageType != null) 'message_type': messageType,
      if (content != null) 'content': content,
      if (metadata != null) 'metadata_json': metadata,
      if (sentAt != null) 'sent_at': sentAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
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
