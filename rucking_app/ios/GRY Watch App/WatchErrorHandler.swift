#if os(watchOS)
import Foundation
import WatchConnectivity

/// Centralized error handling for the watch app that sends errors to iPhone for Sentry logging
class WatchErrorHandler {
    
    enum ErrorSeverity: String {
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"
        case fatal = "fatal"
    }
    
    /// Log an error and send it to iPhone for Sentry reporting
    static func logError(
        operation: String,
        error: Error,
        context: [String: Any]? = nil,
        severity: ErrorSeverity = .error
    ) {
        let errorMessage = "\(operation) failed: \(error.localizedDescription)"
        
        // Always log locally first
        print("[\(severity.rawValue.uppercased())] \(errorMessage)")
        if let context = context {
            print("[\(severity.rawValue.uppercased())] Context: \(context)")
        }
        
        // Send to iPhone for Sentry reporting
        sendErrorToSentry(
            operation: operation,
            error: error,
            context: context,
            severity: severity
        )
    }
    
    /// Log a message-only error (no Error object)
    static func logMessage(
        operation: String,
        message: String,
        context: [String: Any]? = nil,
        severity: ErrorSeverity = .warning
    ) {
        let logMessage = "\(operation): \(message)"
        
        // Always log locally first
        print("[\(severity.rawValue.uppercased())] \(logMessage)")
        if let context = context {
            print("[\(severity.rawValue.uppercased())] Context: \(context)")
        }
        
        // Send to iPhone for Sentry reporting
        sendMessageToSentry(
            operation: operation,
            message: message,
            context: context,
            severity: severity
        )
    }
    
    /// Log HealthKit specific errors
    static func logHealthKitError(
        operation: String,
        error: Error,
        healthKitType: String? = nil
    ) {
        var context: [String: Any] = [
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code
        ]
        
        if let healthKitType = healthKitType {
            context["healthkit_type"] = healthKitType
        }
        
        logError(
            operation: "HealthKit_\(operation)",
            error: error,
            context: context,
            severity: .error
        )
    }
    
    /// Log WatchConnectivity specific errors
    static func logWatchConnectivityError(
        operation: String,
        error: Error,
        sessionState: WCSessionActivationState? = nil,
        isReachable: Bool? = nil
    ) {
        var context: [String: Any] = [
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code
        ]
        
        if let sessionState = sessionState {
            context["wc_session_state"] = sessionState.rawValue
        }
        
        if let isReachable = isReachable {
            context["wc_is_reachable"] = isReachable
        }
        
        logError(
            operation: "WatchConnectivity_\(operation)",
            error: error,
            context: context,
            severity: .error
        )
    }
    
    /// Log workout/session specific errors
    static func logWorkoutError(
        operation: String,
        error: Error,
        workoutState: String? = nil,
        sessionActive: Bool? = nil
    ) {
        var context: [String: Any] = [
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code
        ]
        
        if let workoutState = workoutState {
            context["workout_state"] = workoutState
        }
        
        if let sessionActive = sessionActive {
            context["session_active"] = sessionActive
        }
        
        logError(
            operation: "Workout_\(operation)",
            error: error,
            context: context,
            severity: .error
        )
    }
    
    // MARK: - Private Methods
    
    private static func sendErrorToSentry(
        operation: String,
        error: Error,
        context: [String: Any]?,
        severity: ErrorSeverity
    ) {
        var payload: [String: Any] = [
            "command": "watchErrorToSentry",
            "operation": operation,
            "error_message": error.localizedDescription,
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code,
            "severity": severity.rawValue,
            "timestamp": Date().timeIntervalSince1970,
            "source": "watch_app"
        ]
        
        if let context = context {
            payload["context"] = context
        }
        
        sendToPhone(payload)
    }
    
    private static func sendMessageToSentry(
        operation: String,
        message: String,
        context: [String: Any]?,
        severity: ErrorSeverity
    ) {
        var payload: [String: Any] = [
            "command": "watchMessageToSentry",
            "operation": operation,
            "message": message,
            "severity": severity.rawValue,
            "timestamp": Date().timeIntervalSince1970,
            "source": "watch_app"
        ]
        
        if let context = context {
            payload["context"] = context
        }
        
        sendToPhone(payload)
    }
    
    private static func sendToPhone(_ payload: [String: Any]) {
        guard WCSession.isSupported() else {
            print("[WATCH_ERROR] WatchConnectivity not supported - cannot send error to Sentry")
            return
        }
        
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("[WATCH_ERROR] WCSession not activated - cannot send error to Sentry")
            return
        }
        
        // Try immediate delivery first
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[WATCH_ERROR] Failed to send error to iPhone: \(error.localizedDescription)")
                // Fallback to queued delivery
                fallbackToQueuedDelivery(payload, session: session)
            }
        } else {
            // Use queued delivery when not reachable
            fallbackToQueuedDelivery(payload, session: session)
        }
    }
    
    private static func fallbackToQueuedDelivery(_ payload: [String: Any], session: WCSession) {
        // Use transferUserInfo for queued delivery
        session.transferUserInfo(payload)
        print("[WATCH_ERROR] Error queued for delivery to iPhone via transferUserInfo")
    }
}

#endif
