import 'package:equatable/equatable.dart';

class UserInfo extends Equatable {
  final String id;
  final String displayName;
  final String? photoUrl;
  
  const UserInfo({
    required this.id,
    required this.displayName,
    this.photoUrl,
  });
  
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id']?.toString() ?? '',
      displayName: json['display_name'] ?? 'Unknown User',
      photoUrl: json['photo_url'],
    );
  }
  
  @override
  List<Object?> get props => [id, displayName, photoUrl];
}
