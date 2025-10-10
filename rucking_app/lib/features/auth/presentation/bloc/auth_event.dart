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

/// Event to request Apple login
class AuthAppleLoginRequested extends AuthEvent {}

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
  List<Object?> get props => [
        username,
        email,
        password,
        weightKg,
        heightCm,
        dateOfBirth,
        preferMetric,
        gender
      ];
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
  List<Object?> get props => [
        username,
        email,
        displayName,
        weightKg,
        heightCm,
        dateOfBirth,
        preferMetric,
        gender
      ];
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
  final String? dateOfBirth;
  final int? restingHr;
  final int? maxHr;
  final String? calorieMethod;
  final bool? calorieActiveOnly;
  final bool? stravaAutoExport;

  const AuthUpdateProfileRequested({
    this.username,
    this.weightKg,
    this.heightCm,
    this.preferMetric,
    this.allowRuckSharing,
    this.gender,
    this.avatarUrl,
    this.dateOfBirth,
    this.restingHr,
    this.maxHr,
    this.calorieMethod,
    this.calorieActiveOnly,
    this.stravaAutoExport,
  });

  @override
  List<Object?> get props => [
        username,
        weightKg,
        heightCm,
        preferMetric,
        allowRuckSharing,
        gender,
        avatarUrl,
        dateOfBirth,
        restingHr,
        maxHr,
        calorieMethod,
        calorieActiveOnly,
        stravaAutoExport
      ];
}

/// Event to update user notification preferences
class AuthUpdateNotificationPreferences extends AuthEvent {
  final Map<String, bool> preferences;

  const AuthUpdateNotificationPreferences(this.preferences);

  @override
  List<Object> get props => [preferences];
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
  final String? refreshToken;

  const AuthPasswordResetConfirmed({
    required this.token,
    required this.newPassword,
    this.refreshToken,
  });

  @override
  List<Object?> get props => [token, newPassword, refreshToken];
}

/// Event to verify OTP code for password reset
class AuthOtpVerified extends AuthEvent {
  final String email;
  final String otpCode;

  const AuthOtpVerified({
    required this.email,
    required this.otpCode,
  });

  @override
  List<Object> get props => [email, otpCode];
}
