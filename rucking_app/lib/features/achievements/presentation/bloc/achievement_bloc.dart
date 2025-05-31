import 'package:equatable/equatable.dart';
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
      emit(AchievementsLoading());
      
      final achievements = await _achievementRepository.getAchievements();
      
      // If we already have some state, preserve it and just update achievements
      if (state is AchievementsLoaded) {
        final currentState = state as AchievementsLoaded;
        emit(currentState.copyWith(allAchievements: achievements));
      } else {
        emit(AchievementsLoaded(
          allAchievements: achievements,
          categories: [],
          userAchievements: [],
          userProgress: [],
          recentAchievements: [],
        ));
      }
    } catch (e) {
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
      final newAchievements = await _achievementRepository.checkSessionAchievements(event.sessionId);
      
      if (state is AchievementsLoaded) {
        final currentState = state as AchievementsLoaded;
        
        if (newAchievements.isNotEmpty) {
          // Update the newly earned list and emit session checked state
          emit(AchievementsSessionChecked(
            newAchievements: newAchievements,
            previousState: currentState.copyWith(newlyEarned: newAchievements),
          ));
        }
      } else {
        // If no current state, just emit the new achievements
        if (newAchievements.isNotEmpty) {
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
      }
    } catch (e) {
      AppLogger.error('Failed to check session achievements', exception: e);
      emit(AchievementsError(message: 'Failed to check session achievements: ${e.toString()}'));
    }
  }

  Future<void> _onLoadAchievementStats(
    LoadAchievementStats event,
    Emitter<AchievementState> emit,
  ) async {
    try {
      final stats = await _achievementRepository.getAchievementStats(event.userId);
      
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
      emit(AchievementsLoading());
      
      // Load all data in parallel for better performance
      final results = await Future.wait([
        _achievementRepository.getAchievements(),
        _achievementRepository.getAchievementCategories(),
        _achievementRepository.getUserAchievements(event.userId),
        _achievementRepository.getUserAchievementProgress(event.userId),
        _achievementRepository.getAchievementStats(event.userId),
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
