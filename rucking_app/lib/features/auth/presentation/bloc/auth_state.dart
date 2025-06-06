part of 'auth_bloc.dart';

/// Base class for all authentication states
abstract class AuthState extends Equatable {
  const AuthState();
  
  @override
  List<Object?> get props => [];
}

/// Initial state before authentication status is determined
class AuthInitial extends AuthState {}

/// Loading state during authentication operations
class AuthLoading extends AuthState {}

/// Authenticated state when user is logged in
class Authenticated extends AuthState {
  final User user;
  
  const Authenticated(this.user);
  
  @override
  List<Object> get props => [user];
}

/// Unauthenticated state when no user is logged in
class Unauthenticated extends AuthState {}

/// Error state for authentication failures
class AuthError extends AuthState {
  final String message;
  
  const AuthError(this.message);
  
  @override
  List<Object> get props => [message];
}

/// Error state for when a user tries to register with an email that already exists
class AuthUserAlreadyExists extends AuthState {
  final String message;
  
  const AuthUserAlreadyExists(this.message);
  
  @override
  List<Object> get props => [message];
}

/// State when Google user needs to complete registration
class GoogleUserNeedsRegistration extends AuthState {
  final String email;
  final String? displayName;
  
  const GoogleUserNeedsRegistration({
    required this.email,
    this.displayName,
  });
  
  @override
  List<Object?> get props => [email, displayName];
}