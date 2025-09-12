import 'package:equatable/equatable.dart';

/// Review for a completed ruck session
class SessionReview extends Equatable {
  /// Unique identifier for the review
  final String? id;

  /// The related ruck session ID
  final String sessionId;

  /// User rating from 1-5
  final int rating;

  /// User's perceived exertion level (1-10)
  final int? perceivedExertion;

  /// Notes about the session
  final String? notes;

  /// Tags for categorizing the session
  final List<String> tags;

  /// Creates a new session review
  const SessionReview({
    this.id,
    required this.sessionId,
    required this.rating,
    this.perceivedExertion,
    this.notes,
    this.tags = const <String>[],
  });

  /// Create a copy of this review with some values changed
  SessionReview copyWith({
    String? id,
    String? sessionId,
    int? rating,
    int? perceivedExertion,
    String? notes,
    List<String>? tags,
  }) {
    return SessionReview(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      rating: rating ?? this.rating,
      perceivedExertion: perceivedExertion ?? this.perceivedExertion,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
    );
  }

  /// Create a SessionReview from JSON
  factory SessionReview.fromJson(Map<String, dynamic> json) {
    return SessionReview(
      id: json['id'] as String?,
      sessionId: json['session_id'] as String,
      rating: json['rating'] as int,
      perceivedExertion: json['perceived_exertion'] as int?,
      notes: json['notes'] as String?,
      tags: json['tags'] != null
          ? (json['tags'] as List<dynamic>).map((e) => e as String).toList()
          : const <String>[],
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'session_id': sessionId,
      'rating': rating,
    };

    if (id != null) result['id'] = id;
    if (perceivedExertion != null)
      result['perceived_exertion'] = perceivedExertion;
    if (notes != null) result['notes'] = notes;
    if (tags.isNotEmpty) result['tags'] = tags;

    return result;
  }

  @override
  List<Object?> get props =>
      [id, sessionId, rating, perceivedExertion, notes, tags];
}
