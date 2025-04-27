import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
  // Reference to Flutter view controller
  var flutterViewController: FlutterViewController!
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Store reference to root view controller
    if let controller = window?.rootViewController as? FlutterViewController {
      flutterViewController = controller
      
      // Initialize API manually using Pigeon method channel names
      let binaryMessenger = controller.binaryMessenger
      
      // Setup watch method channels for receiving messages from Flutter
      let updateSessionChannelName = "dev.flutter.pigeon.rucking_app.FlutterRuckingApi.updateSessionOnWatch"
      let startSessionChannelName = "dev.flutter.pigeon.rucking_app.FlutterRuckingApi.startSessionOnWatch"
      let pauseSessionChannelName = "dev.flutter.pigeon.rucking_app.FlutterRuckingApi.pauseSessionOnWatch"
      let resumeSessionChannelName = "dev.flutter.pigeon.rucking_app.FlutterRuckingApi.resumeSessionOnWatch"
      let endSessionChannelName = "dev.flutter.pigeon.rucking_app.FlutterRuckingApi.endSessionOnWatch"
      
      // Setup channels for handling Flutter messages
      let codec = FlutterStandardMessageCodec.sharedInstance()
      
      // Channel for updating the watch session
      let updateSessionChannel = FlutterMethodChannel(name: updateSessionChannelName, binaryMessenger: binaryMessenger)
      updateSessionChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "updateSessionOnWatch" {
          if let args = call.arguments as? [String: Any],
             let distance = args["distance"] as? Double,
             let duration = args["duration"] as? Double,
             let pace = args["pace"] as? Double,
             let isPaused = args["isPaused"] as? Bool {
            
            self?.sendSessionUpdateToWatch(
              distance: distance,
              duration: duration,
              pace: pace,
              isPaused: isPaused
            )
            result(true)
          } else {
            result(FlutterError(code: "invalid_args", message: "Invalid arguments", details: nil))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
      // Channel for starting a session on the watch
      let startSessionChannel = FlutterMethodChannel(name: startSessionChannelName, binaryMessenger: binaryMessenger)
      startSessionChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "startSessionOnWatch" {
          if let args = call.arguments as? [String: Any],
             let weight = args["ruckWeight"] as? Double {
            
            self?.sendStartSessionToWatch(ruckWeight: weight)
            result(true)
          } else {
            result(FlutterError(code: "invalid_args", message: "Invalid arguments", details: nil))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
      // Channel for pausing a session on the watch
      let pauseSessionChannel = FlutterMethodChannel(name: pauseSessionChannelName, binaryMessenger: binaryMessenger)
      pauseSessionChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "pauseSessionOnWatch" {
          self?.sendPauseSessionToWatch()
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
      // Channel for resuming a session on the watch
      let resumeSessionChannel = FlutterMethodChannel(name: resumeSessionChannelName, binaryMessenger: binaryMessenger)
      resumeSessionChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "resumeSessionOnWatch" {
          self?.sendResumeSessionToWatch()
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
      // Channel for ending a session on the watch
      let endSessionChannel = FlutterMethodChannel(name: endSessionChannelName, binaryMessenger: binaryMessenger)
      endSessionChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "endSessionOnWatch" {
          if let args = call.arguments as? [String: Any],
             let duration = args["duration"] as? Double,
             let distance = args["distance"] as? Double,
             let calories = args["calories"] as? Double {
            
            self?.sendEndSessionToWatch(duration: duration, distance: distance, calories: calories)
            result(true)
          } else {
            result(FlutterError(code: "invalid_args", message: "Invalid arguments", details: nil))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
      // Register a method channel for user preferences
      let userPrefsChannel = FlutterMethodChannel(name: "com.getrucky.gfy/user_preferences", binaryMessenger: controller.binaryMessenger)
      userPrefsChannel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "syncUserPreferences" {
          guard let args = call.arguments as? [String: Any],
                let userId = args["userId"] as? String,
                let useMetricUnits = args["useMetricUnits"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for syncUserPreferences", details: nil))
            return
          }
          
          self?.syncUserPreferencesToWatch(userId: userId, useMetricUnits: useMetricUnits)
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
      // Set up WatchConnectivity
      setupWatchConnectivity()
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // MARK: - Watch Connectivity
  
  // Setup WatchConnectivity
  func setupWatchConnectivity() {
    if WCSession.isSupported() {
      let session = WCSession.default
      session.delegate = self
      session.activate()
    }
  }
  
  // MARK: - Required WCSessionDelegate methods
  
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    print("iOS WCSession activation state: \(activationState.rawValue)")
  }
  
  func sessionDidBecomeInactive(_ session: WCSession) {
    print("iOS WCSession became inactive")
  }
  
  func sessionDidDeactivate(_ session: WCSession) {
    print("iOS WCSession deactivated")
    // Reactivate session if needed
    WCSession.default.activate()
  }
  
  // MARK: - Watch message handling
  
  // Receive messages from watch
  func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
    DispatchQueue.main.async {
      self.handleWatchMessage(message)
    }
  }
  
  // Handle user info transfers (for when immediate delivery isn't available)
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
    DispatchQueue.main.async {
      self.handleWatchMessage(userInfo)
    }
  }
  
  // Handle incoming watch messages
  private func handleWatchMessage(_ message: [String: Any]) {
    guard let command = message["command"] as? String else { return }
    
    switch command {
    case "startSession":
      if let weight = message["ruckWeight"] as? Double {
        print("Received start session command from watch with weight: \(weight)")
        // Create a new Flutter method channel for session updates
        if let controller = flutterViewController {
          let sessionChannel = FlutterMethodChannel(name: "com.getrucky.gfy/watch_session", binaryMessenger: controller.binaryMessenger)
          
          // Create session information to send to Flutter
          let sessionInfo: [String: Any] = [
            "action": "startSession",
            "ruckWeight": weight,
            "timestamp": Date().timeIntervalSince1970
          ]
          
          // Send the session info to Flutter
          sessionChannel.invokeMethod("onWatchSessionUpdated", arguments: sessionInfo, result: { result in
            if let error = result as? FlutterError {
              print("Error sending session update to Flutter: \(error.message ?? "Unknown error")")
            } else {
              print("Successfully sent session start to Flutter")
            }
          })
        }
      }
      
    case "pauseSession":
      print("Received pause session command from watch")
      if let controller = flutterViewController {
        let sessionChannel = FlutterMethodChannel(name: "com.getrucky.gfy/watch_session", binaryMessenger: controller.binaryMessenger)
        
        let sessionInfo: [String: Any] = [
          "action": "pauseSession",
          "timestamp": Date().timeIntervalSince1970
        ]
        
        sessionChannel.invokeMethod("onWatchSessionUpdated", arguments: sessionInfo)
      }
      
    case "resumeSession":
      print("Received resume session command from watch")
      if let controller = flutterViewController {
        let sessionChannel = FlutterMethodChannel(name: "com.getrucky.gfy/watch_session", binaryMessenger: controller.binaryMessenger)
        
        let sessionInfo: [String: Any] = [
          "action": "resumeSession",
          "timestamp": Date().timeIntervalSince1970
        ]
        
        sessionChannel.invokeMethod("onWatchSessionUpdated", arguments: sessionInfo)
      }
      
    case "endSession":
      if let duration = message["duration"] as? Double,
         let distance = message["distance"] as? Double,
         let calories = message["calories"] as? Double {
        print("Received end session command from watch with duration: \(duration), distance: \(distance), calories: \(calories)")
        
        if let controller = flutterViewController {
          let sessionChannel = FlutterMethodChannel(name: "com.getrucky.gfy/watch_session", binaryMessenger: controller.binaryMessenger)
          
          let sessionInfo: [String: Any] = [
            "action": "endSession",
            "duration": duration,
            "distance": distance, 
            "calories": calories,
            "timestamp": Date().timeIntervalSince1970
          ]
          
          sessionChannel.invokeMethod("onWatchSessionUpdated", arguments: sessionInfo)
        }
      }
      
    case "updateHeartRate":
      if let heartRate = message["heartRate"] as? Double {
        print("Received update heart rate command from watch with heart rate: \(heartRate)")
        
        if let controller = flutterViewController {
          let healthChannel = FlutterMethodChannel(name: "com.getrucky.gfy/watch_health", binaryMessenger: controller.binaryMessenger)
          
          let healthData: [String: Any] = [
            "type": "heartRate",
            "value": heartRate,
            "timestamp": Date().timeIntervalSince1970
          ]
          
          healthChannel.invokeMethod("onHealthDataUpdated", arguments: healthData)
        }
      }
      
    default:
      print("Unknown command from watch: \(command)")
    }
  }
  
  // MARK: - Send messages to watch
  
  // Send session updates to watch
  func sendSessionUpdateToWatch(
    distance: Double,
    duration: Double,
    pace: Double,
    isPaused: Bool,
    heartRate: Double? = nil
  ) {
    guard WCSession.default.activationState == .activated else {
      print("Cannot send to watch - session not activated")
      return
    }
    
    // Prepare message
    var message: [String: Any] = [
      "command": "updateSession",
      "distance": distance,
      "duration": duration,
      "pace": pace,
      "isPaused": isPaused
    ]
    
    if let hr = heartRate {
      message["heartRate"] = hr
    }
    
    // Send message
    if WCSession.default.isReachable {
      // Send immediate message
      WCSession.default.sendMessage(message, replyHandler: nil) { error in
        print("Error sending session update to watch: \(error.localizedDescription)")
      }
    } else {
      // Queue message for later delivery
      WCSession.default.transferUserInfo(message)
    }
  }
  
  // Send start session to watch
  func sendStartSessionToWatch(ruckWeight: Double) {
    guard WCSession.default.activationState == .activated else {
      print("Cannot send to watch - session not activated")
      return
    }
    
    // Prepare message
    let message: [String: Any] = [
      "command": "startSession",
      "ruckWeight": ruckWeight
    ]
    
    // Send message
    if WCSession.default.isReachable {
      // Send immediate message
      WCSession.default.sendMessage(message, replyHandler: nil) { error in
        print("Error sending start session to watch: \(error.localizedDescription)")
      }
    } else {
      // Queue message for later delivery
      WCSession.default.transferUserInfo(message)
    }
  }
  
  // Send pause session to watch
  func sendPauseSessionToWatch() {
    guard WCSession.default.activationState == .activated else {
      print("Cannot send to watch - session not activated")
      return
    }
    
    // Prepare message
    let message: [String: Any] = [
      "command": "pauseSession"
    ]
    
    // Send message
    if WCSession.default.isReachable {
      // Send immediate message
      WCSession.default.sendMessage(message, replyHandler: nil) { error in
        print("Error sending pause session to watch: \(error.localizedDescription)")
      }
    } else {
      // Queue message for later delivery
      WCSession.default.transferUserInfo(message)
    }
  }
  
  // Send resume session to watch
  func sendResumeSessionToWatch() {
    guard WCSession.default.activationState == .activated else {
      print("Cannot send to watch - session not activated")
      return
    }
    
    // Prepare message
    let message: [String: Any] = [
      "command": "resumeSession"
    ]
    
    // Send message
    if WCSession.default.isReachable {
      // Send immediate message
      WCSession.default.sendMessage(message, replyHandler: nil) { error in
        print("Error sending resume session to watch: \(error.localizedDescription)")
      }
    } else {
      // Queue message for later delivery
      WCSession.default.transferUserInfo(message)
    }
  }
  
  // Send end session to watch
  func sendEndSessionToWatch(duration: Double, distance: Double, calories: Double) {
    guard WCSession.default.activationState == .activated else {
      print("Cannot send to watch - session not activated")
      return
    }
    
    // Prepare message
    let message: [String: Any] = [
      "command": "endSession",
      "duration": duration,
      "distance": distance,
      "calories": calories
    ]
    
    // Send message
    if WCSession.default.isReachable {
      // Send immediate message
      WCSession.default.sendMessage(message, replyHandler: nil) { error in
        print("Error sending end session to watch: \(error.localizedDescription)")
      }
    } else {
      // Queue message for later delivery
      WCSession.default.transferUserInfo(message)
    }
  }
  
  // Sync user preferences to the Watch
  private func syncUserPreferencesToWatch(userId: String, useMetricUnits: Bool) {
    guard WCSession.default.activationState == .activated else {
      print("Cannot send to watch - session not activated")
      return
    }
    
    // Create a dictionary with user info
    let userInfo: [String: Any] = [
      "type": "userPreferences",
      "userId": userId,
      "useMetricUnits": useMetricUnits
    ]
    
    // Transfer user info to the watch app
    WCSession.default.transferUserInfo(userInfo)
    print("Transferred user preferences to watch: userId=\(userId), useMetricUnits=\(useMetricUnits)")
  }
}
