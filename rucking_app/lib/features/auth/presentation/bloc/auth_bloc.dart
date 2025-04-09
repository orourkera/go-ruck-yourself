import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/features/auth/domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// BLoC for handling authentication logic
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc(this._authRepository) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onAuthLoginRequested);
    on<AuthRegisterRequested>(_onAuthRegisterRequested);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);
    on<AuthProfileUpdateRequested>(_onAuthProfileUpdateRequested);
  }

  /// Verify authentication status on app start
  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final isAuthenticated = await _authRepository.isAuthenticated();
      
      if (isAuthenticated) {
        final user = await _authRepository.getCurrentUser();
        if (user != null) {
          emit(Authenticated(user));
        } else {
          emit(Unauthenticated());
        }
      } else {
        emit(Unauthenticated());
      }
    } catch (e) {
      emit(AuthError('Failed to check authentication status: $e'));
    }
  }

  /// Handle login request
  Future<void> _onAuthLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final user = await _authRepository.login(
        email: event.email,
        password: event.password,
      );
      
      emit(Authenticated(user));
    } catch (e) {
      emit(AuthError('Login failed: $e'));
    }
  }

  /// Handle registration request
  Future<void> _onAuthRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      final user = await _authRepository.register(
        displayName: event.displayName,
        name: event.name,
        email: event.email,
        password: event.password,
        preferMetric: event.preferMetric,
        weightKg: event.weightKg,
        heightCm: event.heightCm,
        dateOfBirth: event.dateOfBirth,
      );
      
      emit(Authenticated(user));
    } catch (e) {
      if (e.toString().contains('ConflictException') || e.toString().contains('already exists')) {
        emit(AuthUserAlreadyExists('An account with this email already exists. Please sign in instead.'));
      } else {
        emit(AuthError('Registration failed: $e'));
      }
    }
  }

  /// Handle logout request
  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    
    try {
      await _authRepository.logout();
      emit(Unauthenticated());
    } catch (e) {
      emit(AuthError('Logout failed: $e'));
    }
  }

  /// Handle profile update request
  Future<void> _onAuthProfileUpdateRequested(
    AuthProfileUpdateRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Keep current state while updating
    final currentState = state;
    if (currentState is Authenticated) {
      emit(AuthLoading());
      
      try {
        final updatedUser = await _authRepository.updateProfile(
          displayName: event.displayName,
          name: event.name,
          weightKg: event.weightKg,
          heightCm: event.heightCm,
        );
        
        emit(Authenticated(updatedUser));
      } catch (e) {
        emit(AuthError('Profile update failed: $e'));
        // Revert to previous authenticated state
        emit(currentState);
      }
    }
  }
} 