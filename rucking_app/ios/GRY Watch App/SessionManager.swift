import Foundation
import WatchConnectivity

protocol SessionManagerDelegate: AnyObject {
    func sessionDidActivate()
    func sessionDidDeactivate()
    func didReceiveMessage(_ message: [String: Any])
}

class SessionManager: NSObject, ObservableObject, WCSessionDelegate {
    // Published properties for SwiftUI
    @Published var status: String = "Connecting..."
    @Published var heartRate: Int = 0

    var statusText: String {
        status
    }
    var heartRateText: String {
        heartRate > 0 ? "\(heartRate) BPM" : "--"
    }

    func startSession() {
        status = "Connected"
        // Add additional session start logic if needed
    }

    static let shared = SessionManager()
    weak var delegate: SessionManagerDelegate?
    private let session: WCSession
    
    override init() {
        session = WCSession.default
        super.init()
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }
    
    func sendMessage(_ message: [String: Any]) {
        guard session.activationState == .activated else {
            print("Session not activated, message not sent.")
            return
        }
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("Error sending message: \(error.localizedDescription)")
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            delegate?.sessionDidActivate()
        } else {
            delegate?.sessionDidDeactivate()
        }
        if let error = error {
            print("Session activation failed: \(error.localizedDescription)")
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        delegate?.didReceiveMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        delegate?.didReceiveMessage(message)
        replyHandler(["received": true])
    }
    
    // Handle application context
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print(" [WATCH] SessionManager received application context: \(applicationContext)")
        
        // Always update UI on the main thread (prevents the SwiftUI threading error)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Process application context the same way as messages
            self.delegate?.didReceiveMessage(applicationContext)
            
            // Update UI properties directly as well
            if let command = applicationContext["command"] as? String {
                self.status = "Received: \(command)"
            }
            
            if let metrics = applicationContext["metrics"] as? [String: Any], 
               let hr = metrics["heartRate"] as? Double {
                self.heartRate = Int(hr)
            }
        }
    }
}    
