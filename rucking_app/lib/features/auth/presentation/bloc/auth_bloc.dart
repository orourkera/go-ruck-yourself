import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rucking_app/core/models/user.dart';
import 'package:rucking_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

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
    on<AuthUpdateProfileRequested>(_onAuthUpdateProfileRequested);
    on<AuthDeleteAccountRequested>(_onAuthDeleteAccountRequested);
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
        try {
          final user = await _authRepository.getCurrentUser();
          if (user != null) {
            emit(Authenticated(user));
          } else {
            // If we can't get a user despite being "authenticated", stay authenticated
            // but log the issue - don't force logout
            AppLogger.warning('[AuthBloc] Could not get user data but staying authenticated');
            emit(AuthLoading()); // Keep in loading state rather than logout
          }
        } catch (e) {
          // If we get an error while trying to get the current user,
          // stay authenticated but log the issue - don't force logout
          AppLogger.warning('[AuthBloc] Error getting current user but staying authenticated: $e');
          emit(AuthLoading()); // Keep in loading state rather than logout
        }
      } else {
        emit(Unauthenticated());
      }
    } catch (e) {
      AppLogger.error('[AuthBloc] Auth check error: $e');
      // Stay authenticated on auth check errors - don't force logout
      AppLogger.warning('[AuthBloc] Auth check failed but staying authenticated');
      emit(AuthLoading()); // Keep in loading state rather than logout
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
        username: event.username, // This is the display name
        email: event.email,
        password: event.password,
        preferMetric: event.preferMetric,
        weightKg: event.weightKg,
        heightCm: event.heightCm,
        dateOfBirth: event.dateOfBirth,
        gender: event.gender,
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
  Future<void> _onAuthUpdateProfileRequested(
    AuthUpdateProfileRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Get current state to maintain user ID if needed
    final currentState = state;
    if (currentState is Authenticated) {
      emit(AuthLoading()); // Indicate loading state
      try {
        // Call updateProfile with the fields from the event
        final updatedUser = await _authRepository.updateProfile(
          username: event.username,
          weightKg: event.weightKg,
          heightCm: event.heightCm,
          preferMetric: event.preferMetric,
          allowRuckSharing: event.allowRuckSharing,
          gender: event.gender,
        );
        emit(Authenticated(updatedUser)); // Emit new state with updated user
      } catch (e) {
        emit(AuthError('Profile update failed: $e'));
        // Re-emit the previous Authenticated state on error
        // to avoid losing the user's session in the UI
        emit(currentState); 
      }
    } else {
      // Cannot update profile if not authenticated
      emit(AuthError('Cannot update profile: User not authenticated.'));
    }
  }

  /// Handle delete account request
  Future<void> _onAuthDeleteAccountRequested(
    AuthDeleteAccountRequested event,
    Emitter<AuthState> emit,
  ) async {
    final currentState = state;
    if (currentState is Authenticated) {
      emit(AuthLoading()); // Indicate processing
      try {
        final userId = currentState.user.userId;
        AppLogger.info('AuthBloc: Deleting account for user $userId');
        await _authRepository.deleteAccount(userId: userId);
        AppLogger.info('AuthBloc: Account deleted successfully, emitting Unauthenticated.');
        emit(Unauthenticated()); // Transition to Unauthenticated on successful deletion
      } catch (e) {
        AppLogger.error('AuthBloc: Failed to delete account: $e');
        emit(AuthError('Failed to delete account: ${e.toString()}'));
        // Re-emit the Authenticated state so the user isn't logged out if deletion failed
        // The UI should handle showing the error message.
        emit(currentState); 
      }
    } else {
      // Should not happen if the delete option is only shown when authenticated
      AppLogger.warning('AuthBloc: Delete account requested while not authenticated.');
      emit(AuthError('Cannot delete account. User not authenticated.'));
      if (currentState is! Authenticated) {
           emit(Unauthenticated()); // Ensure state is Unauthenticated if it wasn't already
      }
    }
  }
}