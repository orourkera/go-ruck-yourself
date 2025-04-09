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

/// Event to request user registration
class AuthRegisterRequested extends AuthEvent {
  final String displayName;
  final String name;
  final String email;
  final String password;
  final double? weightKg;
  final double? heightCm;
  final String? dateOfBirth;
  final bool preferMetric;

  const AuthRegisterRequested({
    required this.displayName,
    required this.name,
    required this.email,
    required this.password,
    this.weightKg,
    this.heightCm,
    this.dateOfBirth,
    required this.preferMetric,
  });

  @override
  List<Object?> get props => [displayName, name, email, password, weightKg, heightCm, dateOfBirth, preferMetric];
}

/// Event to request user logout
class AuthLogoutRequested extends AuthEvent {}

/// Event to request profile update
class AuthProfileUpdateRequested extends AuthEvent {
  final String? displayName;
  final String? name;
  final double? weightKg;
  final double? heightCm;

  const AuthProfileUpdateRequested({
    this.displayName,
    this.name,
    this.weightKg,
    this.heightCm,
  });

  @override
  List<Object?> get props => [displayName, name, weightKg, heightCm];
} 