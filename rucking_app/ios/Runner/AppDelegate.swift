import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
  // Reference to Flutter view controller
  var flutterViewController: FlutterViewController!
  // FlutterAPI instance for sending messages to Flutter
  var flutterRuckingApi: FlutterRuckingApi?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Store reference to root view controller
    if let controller = window?.rootViewController as? FlutterViewController {
      flutterViewController = controller
      
      // Set up Pigeon generated API
      RuckingApiSetup.setUp(binaryMessenger: controller.binaryMessenger)
      
      // Set up FlutterAPI for sending messages to Flutter
      flutterRuckingApi = FlutterRuckingApi(binaryMessenger: controller.binaryMessenger)
    }
    
    // Set up WatchConnectivity
    setupWatchConnectivity()
    
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
        // Forward to Flutter using Pigeon API
        _ = RuckingApi().startSessionFromWatch(weight) { success in
          print("Start session result: \(success)")
        }
      }
      
    case "pauseSession":
      _ = RuckingApi().pauseSessionFromWatch { success in
        print("Pause session result: \(success)")
      }
      
    case "resumeSession":
      _ = RuckingApi().resumeSessionFromWatch { success in
        print("Resume session result: \(success)")
      }
      
    case "endSession":
      if let duration = message["duration"] as? Double,
         let distance = message["distance"] as? Double,
         let calories = message["calories"] as? Double {
        
        _ = RuckingApi().endSessionFromWatch(
          Int32(duration),
          distance,
          calories) { success in
          print("End session result: \(success)")
        }
      }
      
    case "updateHeartRate":
      if let heartRate = message["heartRate"] as? Double {
        _ = RuckingApi().updateHeartRateFromWatch(heartRate) { success in
          print("Update heart rate result: \(success)")
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
}
