import 'package:equatable/equatable.dart';

class UserInfo extends Equatable {
  final String id;
  final String username;
  final String? photoUrl;
  final String gender; // Either 'male' or 'female'

  const UserInfo({
    required this.id,
    required this.username,
    this.photoUrl,
    required this.gender,
  });

  UserInfo copyWith({
    String? id,
    String? username,
    String? photoUrl,
    String? gender,
  }) {
    return UserInfo(
      id: id ?? this.id,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      gender: gender ?? this.gender,
    );
  }

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? 'Unknown User',
      photoUrl: json['avatar_url'],
      gender:
          json['gender'] ?? 'male', // Default to male if gender not specified
    );
  }

  @override
  List<Object?> get props => [id, username, photoUrl, gender];
}
