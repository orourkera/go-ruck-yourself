import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:rucking_app/core/services/auth_service.dart';
import 'package:rucking_app/core/services/api_client.dart';
import 'package:rucking_app/core/services/storage_service.dart';
import 'package:rucking_app/core/services/watch_service.dart';
import 'package:rucking_app/features/ruck_session/data/repositories/session_repository.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/managers/session_lifecycle_manager.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/models/manager_states.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/events/session_events.dart';

import 'session_lifecycle_manager_test.mocks.dart';

@GenerateMocks([
  SessionRepository,
  AuthService,
  WatchService,
  StorageService,
  ApiClient,
])
void main() {
  late SessionLifecycleManager manager;
  late MockSessionRepository mockRepository;
  late MockAuthService mockAuthService;
  late MockWatchService mockWatchService;
  late MockStorageService mockStorageService;
  late MockApiClient mockApiClient;

  setUp(() {
    mockRepository = MockSessionRepository();
    mockAuthService = MockAuthService();
    mockWatchService = MockWatchService();
    mockStorageService = MockStorageService();
    mockApiClient = MockApiClient();

    manager = SessionLifecycleManager(
      sessionRepository: mockRepository,
      authService: mockAuthService,
      watchService: mockWatchService,
      storageService: mockStorageService,
      apiClient: mockApiClient,
    );

    // Default mocks
    when(mockAuthService.isAuthenticated()).thenAnswer((_) async => true);
    when(mockStorageService.getObject(any)).thenAnswer((_) async => null);
    when(mockWatchService.startSessionOnWatch(any, isMetric: anyNamed('isMetric')))
        .thenAnswer((_) async {});
    when(mockWatchService.sendSessionIdToWatch(any)).thenAnswer((_) async {});
  });

  tearDown(() {
    manager.dispose();
  });

  group('SessionLifecycleManager', () {
    test('initial state is correct', () {
      expect(manager.currentState.isActive, false);
      expect(manager.currentState.sessionId, null);
      expect(manager.currentState.startTime, null);
      expect(manager.currentState.duration, Duration.zero);
      expect(manager.currentState.errorMessage, null);
      expect(manager.currentState.isSaving, false);
      expect(manager.currentState.isLoading, false);
    });

    test('handles SessionStartRequested successfully', () async {
      const ruckWeight = 20.0;
      const userWeight = 75.0;
      final event = SessionStartRequested(
        ruckWeightKg: ruckWeight,
        userWeightKg: userWeight,
      );

      final stateStream = manager.stateStream;
      final states = <SessionLifecycleState>[];
      final subscription = stateStream.listen(states.add);

      await manager.handleEvent(event);

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify state changes
      expect(states.length, greaterThanOrEqualTo(2));
      expect(states.first.isLoading, true); // Loading state
      expect(states.last.isActive, true); // Active state
      expect(states.last.sessionId, isNotNull);
      expect(states.last.startTime, isNotNull);
      expect(states.last.errorMessage, null);

      // Verify watch service calls
      verify(mockWatchService.startSessionOnWatch(ruckWeight, isMetric: false)).called(1);
      verify(mockWatchService.sendSessionIdToWatch(any)).called(1);

      // Verify API call
      verify(mockRepository.createSession(any)).called(1);

      subscription.cancel();
    });

    test('handles SessionStartRequested with error', () async {
      // Setup mock to throw error
      when(mockRepository.createSession(any)).thenThrow(Exception('Network error'));

      final event = SessionStartRequested(
        ruckWeightKg: 20.0,
        userWeightKg: 75.0,
      );

      final stateStream = manager.stateStream;
      final states = <SessionLifecycleState>[];
      final subscription = stateStream.listen(states.add);

      await manager.handleEvent(event);

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify error state
      expect(states.last.errorMessage, isNotNull);
      expect(states.last.isLoading, false);

      subscription.cancel();
    });

    test('handles SessionStopRequested', () async {
      // First start a session
      await manager.handleEvent(SessionStartRequested(
        ruckWeightKg: 20.0,
        userWeightKg: 75.0,
      ));

      // Wait for session to start
      await Future.delayed(const Duration(milliseconds: 100));

      // Now stop the session
      final stateStream = manager.stateStream;
      final states = <SessionLifecycleState>[];
      final subscription = stateStream.listen(states.add);

      await manager.handleEvent(const SessionStopRequested());

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify state is reset
      expect(states.last.isActive, false);
      expect(states.last.sessionId, null);
      expect(states.last.startTime, null);

      // Verify watch service call
      verify(mockWatchService.stopSessionOnWatch()).called(1);

      subscription.cancel();
    });

    test('handles SessionPaused', () async {
      // First start a session
      await manager.handleEvent(SessionStartRequested(
        ruckWeightKg: 20.0,
        userWeightKg: 75.0,
      ));

      // Wait for session to start
      await Future.delayed(const Duration(milliseconds: 100));

      // Pause the session
      final stateStream = manager.stateStream;
      final states = <SessionLifecycleState>[];
      final subscription = stateStream.listen(states.add);

      await manager.handleEvent(const SessionPaused());

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify state shows paused (isActive = false)
      expect(states.last.isActive, false);

      // Verify watch service call
      verify(mockWatchService.pauseSessionOnWatch()).called(1);

      subscription.cancel();
    });

    test('handles SessionResumed', () async {
      // First start and pause a session
      await manager.handleEvent(SessionStartRequested(
        ruckWeightKg: 20.0,
        userWeightKg: 75.0,
      ));
      await Future.delayed(const Duration(milliseconds: 100));
      await manager.handleEvent(const SessionPaused());
      await Future.delayed(const Duration(milliseconds: 100));

      // Resume the session
      final stateStream = manager.stateStream;
      final states = <SessionLifecycleState>[];
      final subscription = stateStream.listen(states.add);

      await manager.handleEvent(const SessionResumed());

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify state shows resumed (isActive = true)
      expect(states.last.isActive, true);

      // Verify watch service call
      verify(mockWatchService.resumeSessionOnWatch()).called(1);

      subscription.cancel();
    });

    test('handles Tick events to update duration', () async {
      // Start a session
      await manager.handleEvent(SessionStartRequested(
        ruckWeightKg: 20.0,
        userWeightKg: 75.0,
      ));

      // Wait for session to start
      await Future.delayed(const Duration(milliseconds: 100));

      final initialDuration = manager.currentState.duration;

      // Send tick events
      await manager.handleEvent(const Tick());
      await Future.delayed(const Duration(seconds: 1));
      await manager.handleEvent(const Tick());

      // Verify duration increases
      expect(manager.currentState.duration, greaterThan(initialDuration));
    });

    test('getUserMetricPreference defaults to imperial', () async {
      // Test when storage returns null
      when(mockStorageService.getObject(any)).thenAnswer((_) async => null);

      await manager.handleEvent(SessionStartRequested(
        ruckWeightKg: 20.0,
        userWeightKg: 75.0,
      ));

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify imperial (false) was used
      verify(mockWatchService.startSessionOnWatch(any, isMetric: false)).called(1);
    });

    test('getUserMetricPreference reads from storage', () async {
      // Test when storage returns metric preference
      when(mockStorageService.getObject(any))
          .thenAnswer((_) async => {'preferMetric': true});

      await manager.handleEvent(SessionStartRequested(
        ruckWeightKg: 20.0,
        userWeightKg: 75.0,
      ));

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify metric (true) was used
      verify(mockWatchService.startSessionOnWatch(any, isMetric: true)).called(1);
    });

    test('getters return correct values', () async {
      // Initially no active session
      expect(manager.activeSessionId, null);
      expect(manager.sessionStartTime, null);
      expect(manager.isSessionActive, false);

      // Start a session
      await manager.handleEvent(SessionStartRequested(
        ruckWeightKg: 20.0,
        userWeightKg: 75.0,
      ));

      // Wait for session to start
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify getters
      expect(manager.activeSessionId, isNotNull);
      expect(manager.sessionStartTime, isNotNull);
      expect(manager.isSessionActive, true);
    });
  });
}
