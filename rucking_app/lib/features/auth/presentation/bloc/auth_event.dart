part of 'auth_bloc.dart';

/// Base class for all authentication events
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Event to check if the user is already authenticated
class AuthCheckRequested extends AuthEvent {}

/// Event to request user login
class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object> get props => [email, password];
}

/// Event to request Google login
class AuthGoogleLoginRequested extends AuthEvent {}

/// Event to request user registration
class AuthRegisterRequested extends AuthEvent {
  final String username;
  final String email;
  final String password;
  final double? weightKg;
  final double? heightCm;
  final String? dateOfBirth;
  final bool preferMetric;
  final String? gender;

  const AuthRegisterRequested({
    required this.username,
    required this.email,
    required this.password,
    this.weightKg,
    this.heightCm,
    this.dateOfBirth,
    required this.preferMetric,
    this.gender,
  });

  @override
  List<Object?> get props => [username, email, password, weightKg, heightCm, dateOfBirth, preferMetric, gender];
}

/// Event to complete Google user registration
class AuthGoogleRegisterRequested extends AuthEvent {
  final String username;
  final String email;
  final String? displayName;
  final double? weightKg;
  final double? heightCm;
  final String? dateOfBirth;
  final bool preferMetric;
  final String? gender;

  const AuthGoogleRegisterRequested({
    required this.username,
    required this.email,
    this.displayName,
    this.weightKg,
    this.heightCm,
    this.dateOfBirth,
    required this.preferMetric,
    this.gender,
  });

  @override
  List<Object?> get props => [username, email, displayName, weightKg, heightCm, dateOfBirth, preferMetric, gender];
}

/// Event to request user logout
class AuthLogoutRequested extends AuthEvent {}

/// Event to update user profile
class AuthUpdateProfileRequested extends AuthEvent {
  final String? username;
  final double? weightKg;
  final double? heightCm;
  final bool? preferMetric;
  final bool? allowRuckSharing;
  final String? gender;
  final String? avatarUrl;

  const AuthUpdateProfileRequested({
    this.username,
    this.weightKg,
    this.heightCm,
    this.preferMetric,
    this.allowRuckSharing,
    this.gender,
    this.avatarUrl,
  });

  @override
  List<Object?> get props => [username, weightKg, heightCm, preferMetric, allowRuckSharing, gender, avatarUrl];
}

/// Event triggered when the user requests to delete their account
class AuthDeleteAccountRequested extends AuthEvent {
  const AuthDeleteAccountRequested();
}

/// Event to request password reset email
class AuthPasswordResetRequested extends AuthEvent {
  final String email;

  const AuthPasswordResetRequested({
    required this.email,
  });

  @override
  List<Object> get props => [email];
}

/// Event to confirm password reset with new password
class AuthPasswordResetConfirmed extends AuthEvent {
  final String token;
  final String newPassword;

  const AuthPasswordResetConfirmed({
    required this.token,
    required this.newPassword,
  });

  @override
  List<Object> get props => [token, newPassword];
}