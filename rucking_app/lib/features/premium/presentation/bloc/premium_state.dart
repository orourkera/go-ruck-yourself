import 'package:equatable/equatable.dart';

abstract class PremiumState extends Equatable {
  const PremiumState();

  @override
  List<Object> get props => [];
}

class PremiumInitial extends PremiumState {}

class PremiumLoading extends PremiumState {}

class PremiumLoaded extends PremiumState {
  final bool isPremium;

  const PremiumLoaded({required this.isPremium});

  @override
  List<Object> get props => [isPremium];
}

class PremiumError extends PremiumState {
  final String message;

  const PremiumError(this.message);

  @override
  List<Object> get props => [message];
}

class PremiumPurchasing extends PremiumState {}

class PremiumPurchased extends PremiumState {}

class PremiumPurchaseError extends PremiumState {
  final String message;

  const PremiumPurchaseError(this.message);

  @override
  List<Object> get props => [message];
}