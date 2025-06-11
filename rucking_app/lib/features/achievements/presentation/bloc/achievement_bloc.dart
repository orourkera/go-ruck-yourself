import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/achievements/data/models/achievement_model.dart';
import 'package:rucking_app/features/achievements/domain/repositories/achievement_repository.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_event.dart';
import 'package:rucking_app/features/achievements/presentation/bloc/achievement_state.dart';
import 'package:rucking_app/core/utils/app_logger.dart';

class AchievementBloc extends Bloc<AchievementEvent, AchievementState> {
  final AchievementRepository _achievementRepository;
  
  AchievementBloc({
    required AchievementRepository achievementRepository,
  })  : _achievementRepository = achievementRepository,
        super(AchievementsInitial()) {
    
    on<LoadAchievements>(_onLoadAchievements);
    on<LoadAchievementCategories>(_onLoadAchievementCategories);
    on<LoadUserAchievements>(_onLoadUserAchievements);
    on<LoadUserAchievementProgress>(_onLoadUserAchievementProgress);
    on<CheckSessionAchievements>(_onCheckSessionAchievements);
    on<LoadAchievementStats>(_onLoadAchievementStats);
    on<LoadRecentAchievements>(_onLoadRecentAchievements);
    on<RefreshAchievementData>(_onRefreshAchievementData);
  }

  Future<void> _onLoadAchievements(
    LoadAchievements event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      debugPrint('🏆 [AchievementBloc] LoadAchievements event received with unitPreference: ${event.unitPreference}');
      emit(AchievementsLoading());
      
      debugPrint('🏆 [AchievementBloc] Fetching all achievements...');
      final achievements = await _achievementRepository.getAllAchievements(unitPreference: event.unitPreference);
      debugPrint('🏆 [AchievementBloc] Fetched ${achievements.length} achievements');
      
      // If we already have some state, preserve it and just update achievements
      if (state is AchievementsLoaded) {
        final currentState = state as AchievementsLoaded;
        emit(currentState.copyWith(allAchievements: achievements));
        debugPrint('🏆 [AchievementBloc] Emitted AchievementsLoaded state');
      } else {
        emit(AchievementsLoaded(
          allAchievements: achievements,
          categories: [],
          userAchievements: [],
          userProgress: [],
          recentAchievements: [],
        ));
        debugPrint('🏆 [AchievementBloc] Emitted basic AchievementsLoaded state');
      }
    } catch (e) {
      debugPrint('🏆 [AchievementBloc] Error loading achievements: $e');
      AppLogger.error('Failed to load achievements', exception: e);
      emit(AchievementsError(message: 'Failed to load achievements: ${e.toString()}'));
    }
  }

  Future<void> _onLoadAchievementCategories(
    LoadAchievementCategories event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      final categories = await _achievementRepository.getAchievementCategories();
      
      if (state is AchievementsLoaded) {
        final currentState = state as AchievementsLoaded;
        emit(currentState.copyWith(categories: categories));
      } else {
        emit(AchievementsLoaded(
          allAchievements: [],
          categories: categories,
          userAchievements: [],
          userProgress: [],
          recentAchievements: [],
        ));
      }
    } catch (e) {
      AppLogger.error('Failed to load achievement categories', exception: e);
      emit(AchievementsError(message: 'Failed to load categories: ${e.toString()}'));
    }
  }

  Future<void> _onLoadUserAchievements(
    LoadUserAchievements event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      // Validate userId before making API call to prevent 500 errors
      if (event.userId.isEmpty) {
        AppLogger.error('Cannot load achievements: User ID is empty');
        emit(const AchievementsError(message: 'User profile not found. Please sign in again.'));
        return;
      }
      
      final userAchievements = await _achievementRepository.getUserAchievements(event.userId);
      
      if (state is AchievementsLoaded) {
        final currentState = state as AchievementsLoaded;
        emit(currentState.copyWith(userAchievements: userAchievements));
      } else {
        emit(AchievementsLoaded(
          allAchievements: [],
          categories: [],
          userAchievements: userAchievements,
          userProgress: [],
          recentAchievements: [],
        ));
      }
    } catch (e) {
      AppLogger.error('Failed to load user achievements', exception: e);
      emit(AchievementsError(message: 'Failed to load your achievements: ${e.toString()}'));
    }
  }

  Future<void> _onLoadUserAchievementProgress(
    LoadUserAchievementProgress event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      // Validate userId before making API call to prevent 500 errors
      if (event.userId.isEmpty) {
        AppLogger.error('Cannot load achievement progress: User ID is empty');
        emit(const AchievementsError(message: 'User profile not found. Please sign in again.'));
        return;
      }
      
      final userProgress = await _achievementRepository.getUserAchievementProgress(event.userId);
      
      if (state is AchievementsLoaded) {
        final currentState = state as AchievementsLoaded;
        emit(currentState.copyWith(userProgress: userProgress));
      } else {
        emit(AchievementsLoaded(
          allAchievements: [],
          categories: [],
          userAchievements: [],
          userProgress: userProgress,
          recentAchievements: [],
        ));
      }
    } catch (e) {
      AppLogger.error('Failed to load user achievement progress', exception: e);
      emit(AchievementsError(message: 'Failed to load achievement progress: ${e.toString()}'));
    }
  }

  Future<void> _onCheckSessionAchievements(
    CheckSessionAchievements event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      print('[DEBUG] AchievementBloc: Checking achievements for session ${event.sessionId}');
      final newAchievements = await _achievementRepository.checkSessionAchievements(event.sessionId);
           if (newAchievements.isNotEmpty) {
        print('[DEBUG] AchievementBloc: ${newAchievements.length} new achievements earned!');
        
        // Clear cache when new achievements are found so data will be refreshed
        await _achievementRepository.clearCache();
        print('[DEBUG] AchievementBloc: Cleared achievement cache due to new achievements');
        
        if (state is AchievementsLoaded) {
          final currentState = state as AchievementsLoaded;
          
          print('[DEBUG] AchievementBloc: Emitting AchievementsSessionChecked with new achievements');
          // Update the newly earned list and emit session checked state
          emit(AchievementsSessionChecked(
            newAchievements: newAchievements,
            previousState: currentState.copyWith(newlyEarned: newAchievements),
          ));
        } else {
          emit(AchievementsSessionChecked(
            newAchievements: newAchievements,
            previousState: AchievementsLoaded(
              allAchievements: [],
              categories: [],
              userAchievements: [],
              userProgress: [],
              recentAchievements: [],
              newlyEarned: newAchievements,
            ),
          ));
        }
      } else {
        print('[DEBUG] AchievementBloc: No new achievements earned');
      }
    } catch (e) {
      print('[DEBUG] AchievementBloc: Error checking session achievements: $e');
      AppLogger.error('Failed to check session achievements', exception: e);
      emit(AchievementsError(message: 'Failed to check session achievements: ${e.toString()}'));
    }
  }

  Future<void> _onLoadAchievementStats(
    LoadAchievementStats event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      // Validate userId before making API call to prevent 500 errors
      if (event.userId.isEmpty) {
        AppLogger.error('Cannot load achievement stats: User ID is empty');
        emit(const AchievementsError(message: 'User profile not found. Please sign in again.'));
        return;
      }
      
      final stats = await _achievementRepository.getAchievementStats(event.userId, unitPreference: event.unitPreference);
      
      if (state is AchievementsLoaded) {
        final currentState = state as AchievementsLoaded;
        emit(currentState.copyWith(stats: stats));
      } else {
        emit(AchievementsLoaded(
          allAchievements: [],
          categories: [],
          userAchievements: [],
          userProgress: [],
          stats: stats,
          recentAchievements: [],
        ));
      }
    } catch (e) {
      AppLogger.error('Failed to load achievement stats', exception: e);
      emit(AchievementsError(message: 'Failed to load achievement stats: ${e.toString()}'));
    }
  }

  Future<void> _onLoadRecentAchievements(
    LoadRecentAchievements event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      final recentAchievements = await _achievementRepository.getRecentAchievements();
      
      if (state is AchievementsLoaded) {
        final currentState = state as AchievementsLoaded;
        emit(currentState.copyWith(recentAchievements: recentAchievements));
      } else {
        emit(AchievementsLoaded(
          allAchievements: [],
          categories: [],
          userAchievements: [],
          userProgress: [],
          recentAchievements: recentAchievements,
        ));
      }
    } catch (e) {
      AppLogger.error('Failed to load recent achievements', exception: e);
      emit(AchievementsError(message: 'Failed to load recent achievements: ${e.toString()}'));
    }
  }

  Future<void> _onRefreshAchievementData(
    RefreshAchievementData event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      // Validate userId before making API call to prevent 500 errors
      if (event.userId.isEmpty) {
        AppLogger.error('Cannot refresh achievement data: User ID is empty');
        emit(const AchievementsError(message: 'User profile not found. Please sign in again.'));
        return;
      }
      
      emit(AchievementsLoading());
      
      // Clear cache first to force fresh data fetch
      debugPrint('🏆 [AchievementBloc] Clearing achievement cache for refresh');
      await _achievementRepository.clearCache();
      
      // Load all data in parallel for better performance
      final results = await Future.wait([
        _achievementRepository.getAllAchievements(unitPreference: event.unitPreference),
        _achievementRepository.getAchievementCategories(),
        _achievementRepository.getUserAchievements(event.userId),
        _achievementRepository.getUserAchievementProgress(event.userId),
        _achievementRepository.getAchievementStats(event.userId, unitPreference: event.unitPreference),
        _achievementRepository.getRecentAchievements(),
      ]);

      final achievements = results[0] as List<Achievement>;
      final categories = results[1] as List<String>;
      final userAchievements = results[2] as List<UserAchievement>;
      final userProgress = results[3] as List<AchievementProgress>;
      final stats = results[4] as AchievementStats;
      final recentAchievements = results[5] as List<UserAchievement>;

      emit(AchievementsLoaded(
        allAchievements: achievements,
        categories: categories,
        userAchievements: userAchievements,
        userProgress: userProgress,
        stats: stats,
        recentAchievements: recentAchievements,
      ));
    } catch (e) {
      AppLogger.error('Failed to refresh achievement data', exception: e);
      emit(AchievementsError(message: 'Failed to refresh achievement data: ${e.toString()}'));
    }
  }
}
