import 'package:equatable/equatable.dart';

class UserInfo extends Equatable {
  final String id;
  final String username;
  final String? photoUrl;
  
  const UserInfo({
    required this.id,
    required this.username,
    this.photoUrl,
  });
  
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? 'Unknown User',
      photoUrl: json['avatar_url'],
    );
  }
  
  @override
  List<Object?> get props => [id, username, photoUrl];
}
