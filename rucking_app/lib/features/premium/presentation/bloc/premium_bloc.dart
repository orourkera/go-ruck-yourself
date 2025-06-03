import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_event.dart';
import 'package:rucking_app/features/premium/presentation/bloc/premium_state.dart';
import 'package:rucking_app/features/premium/domain/services/premium_service.dart';

class PremiumBloc extends Bloc<PremiumEvent, PremiumState> {
  final PremiumService _premiumService;

  PremiumBloc(this._premiumService) : super(PremiumInitial()) {
    on<InitializePremiumStatus>(_onInitializePremiumStatus);
    on<CheckPremiumStatus>(_onCheckPremiumStatus);
    on<UpdatePremiumStatus>(_onUpdatePremiumStatus);
    on<PurchasePremium>(_onPurchasePremium);
    on<RestorePurchases>(_onRestorePurchases);
  }

  Future<void> _onInitializePremiumStatus(
    InitializePremiumStatus event,
    Emitter<PremiumState> emit,
  ) async {
    emit(PremiumLoading());
    try {
      final isPremium = await _premiumService.isPremium();
      emit(PremiumLoaded(isPremium: isPremium));
    } catch (e) {
      emit(PremiumError('Failed to initialize premium status: ${e.toString()}'));
    }
  }

  Future<void> _onCheckPremiumStatus(
    CheckPremiumStatus event,
    Emitter<PremiumState> emit,
  ) async {
    try {
      final isPremium = await _premiumService.isPremium();
      emit(PremiumLoaded(isPremium: isPremium));
    } catch (e) {
      emit(PremiumError('Failed to check premium status: ${e.toString()}'));
    }
  }

  Future<void> _onUpdatePremiumStatus(
    UpdatePremiumStatus event,
    Emitter<PremiumState> emit,
  ) async {
    emit(PremiumLoaded(isPremium: event.isPremium));
  }

  Future<void> _onPurchasePremium(
    PurchasePremium event,
    Emitter<PremiumState> emit,
  ) async {
    emit(PremiumPurchasing());
    try {
      final success = await _premiumService.purchasePremium();
      if (success) {
        emit(PremiumPurchased());
        // Check status after purchase
        add(CheckPremiumStatus());
      } else {
        emit(const PremiumPurchaseError('Purchase failed'));
      }
    } catch (e) {
      emit(PremiumPurchaseError('Purchase error: ${e.toString()}'));
    }
  }

  Future<void> _onRestorePurchases(
    RestorePurchases event,
    Emitter<PremiumState> emit,
  ) async {
    emit(PremiumLoading());
    try {
      final success = await _premiumService.restorePurchases();
      if (success) {
        // Check status after restore
        add(CheckPremiumStatus());
      } else {
        emit(const PremiumError('No purchases to restore'));
      }
    } catch (e) {
      emit(PremiumError('Restore error: ${e.toString()}'));
    }
  }
}