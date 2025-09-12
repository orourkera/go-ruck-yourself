import 'package:equatable/equatable.dart';

abstract class PremiumEvent extends Equatable {
  const PremiumEvent();

  @override
  List<Object> get props => [];
}

class InitializePremiumStatus extends PremiumEvent {}

class CheckPremiumStatus extends PremiumEvent {}

class UpdatePremiumStatus extends PremiumEvent {
  final bool isPremium;

  const UpdatePremiumStatus(this.isPremium);

  @override
  List<Object> get props => [isPremium];
}

class PurchasePremium extends PremiumEvent {}

class RestorePurchases extends PremiumEvent {}
