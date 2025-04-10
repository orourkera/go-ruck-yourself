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
      // First, perform the login
      final loginUser = await _authRepository.login(
        email: event.email,
        password: event.password,
      );
      
      // After successful login, fetch the full user profile
      // This ensures we have profile data like name, weight, etc.
      final fullUser = await _authRepository.getCurrentUser();
      
      if (fullUser != null) {
         emit(Authenticated(fullUser));
      } else {
         // Should not happen if login succeeded, but handle defensively
         // Maybe emit Authenticated with just loginUser? Or an error?
         // For now, emit Authenticated with potentially incomplete loginUser data
         emit(Authenticated(loginUser)); 
         emit(AuthError('Login succeeded but failed to fetch full user profile afterward.'));
      }

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
      // Optionally show loading state, or update optimistically
      // emit(AuthLoading()); 
      
      try {
        // Create a map of only the non-null fields to update
        final Map<String, dynamic> updateData = {};
        if (event.name != null) updateData['name'] = event.name;
        if (event.weightKg != null) updateData['weight_kg'] = event.weightKg;
        if (event.heightCm != null) updateData['height_cm'] = event.heightCm;
        if (event.preferMetric != null) updateData['preferMetric'] = event.preferMetric;

        // Only call update if there's something to update
        if (updateData.isNotEmpty) {
            final updatedUser = await _authRepository.updateProfile(
              name: event.name,
              weightKg: event.weightKg,
              heightCm: event.heightCm,
              preferMetric: event.preferMetric, // Pass preferMetric
            );
            
            emit(Authenticated(updatedUser));
        } else {
             // No actual changes requested, revert to current state if loading was shown
             emit(currentState);
        }
      } catch (e) {
        emit(AuthError('Profile update failed: $e'));
        // Revert to previous authenticated state if loading was shown
        emit(currentState);
      }
    }
  }
} 