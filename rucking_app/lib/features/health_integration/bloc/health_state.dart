part of 'health_bloc.dart';

abstract class HealthState extends Equatable {
  const HealthState();

  @override
  List<Object> get props => [];
}

class HealthInitial extends HealthState {}

class HealthLoading extends HealthState {}

class HealthUnavailable extends HealthState {}

class HealthAvailable extends HealthState {
  final bool hasSeenIntro;
  final bool hasAppleWatch;

  const HealthAvailable({
    required this.hasSeenIntro,
    this.hasAppleWatch = true,
  });

  @override
  List<Object> get props => [hasSeenIntro, hasAppleWatch];
}

class HealthAuthorizationStatus extends HealthState {
  final bool authorized;

  const HealthAuthorizationStatus({required this.authorized});

  @override
  List<Object> get props => [authorized];
}

class HealthDataWriteStatus extends HealthState {
  final bool success;

  const HealthDataWriteStatus({required this.success});

  @override
  List<Object> get props => [success];
}

class HealthIntroShown extends HealthState {
  const HealthIntroShown();
}

class HealthDisabled extends HealthState {
  const HealthDisabled();
}

// Data writing states
