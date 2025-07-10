import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:rucking_app/core/utils/app_logger.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_bloc.dart';
import 'package:rucking_app/features/ruck_session/presentation/bloc/active_session_event.dart';

/// This is a temporary diagnostic helper class to debug photo loading issues
/// without dealing with the complex session_detail_screen.dart file
class PhotoDebugHelper {
  static void debugPhotoLoading(String? ruckId) {
    if (ruckId == null) {
      AppLogger.error("[PHOTO_DEBUG] Cannot debug photo loading - ruckId is null");
      return;
    }
    
    AppLogger.debug("[PHOTO_DEBUG] Testing photo loading for ruck ID: $ruckId");
    
    try {
      final activeSessionBloc = GetIt.instance<ActiveSessionBloc>();
      
      // Log the current state
      final currentState = activeSessionBloc.state;
      AppLogger.debug("[PHOTO_DEBUG] Current ActiveSessionBloc state: $currentState");
      
      // Dispatch LoadSessionForViewing and wait a bit
      AppLogger.debug("[PHOTO_DEBUG] Dispatching LoadSessionForViewing for ruckId: $ruckId");
      // TODO: Fix during refactor - requires session object
      // activeSessionBloc.add(LoadSessionForViewing(sessionId: ruckId, session: session));
      
      // Add a delay then fetch photos (simulating what SessionDetailScreen would do)
      Timer(const Duration(seconds: 1), () {
        AppLogger.debug("[PHOTO_DEBUG] Now dispatching ClearSessionPhotos");
        activeSessionBloc.add(ClearSessionPhotos(ruckId: ruckId));
        
        Timer(const Duration(milliseconds: 500), () {
          AppLogger.debug("[PHOTO_DEBUG] Now dispatching FetchSessionPhotosRequested");
          activeSessionBloc.add(FetchSessionPhotosRequested(ruckId));
          
          // Log state after a delay
          Timer(const Duration(seconds: 3), () {
            final updatedState = activeSessionBloc.state;
            AppLogger.debug("[PHOTO_DEBUG] State after photo loading: $updatedState");
          });
        });
      });
    } catch (e) {
      AppLogger.error("[PHOTO_DEBUG] Error in debug helper: $e");
    }
  }
}
