import WatchConnectivity

class SessionManager: NSObject, WCSessionDelegate {
    
    private var session: WCSession?
    private var messageHandler: (([String: Any]) -> Void)?
    
    var isConnected: Bool {
        return session?.activationState == .activated && session?.isReachable == true
    }
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    func setMessageHandler(_ handler: @escaping ([String: Any]) -> Void) {
        self.messageHandler = handler
    }
    
    func sendMessage(_ message: [String: Any], completion: ((Error?) -> Void)? = nil) {
        guard let session = session, session.isActivated, session.isReachable else {
            completion?(NSError(domain: "SessionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Watch session is not connected."]))
            return
        }
        
        session.sendMessage(message, replyHandler: nil) { error in
            completion?(error)
        }
    }
    
    // MARK: - WCSessionDelegate Methods
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Session activation failed: \(error.localizedDescription)")
            return
        }
        
        print("Session activation state: \(activationState.rawValue)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        messageHandler?(message)
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("Session reachability changed: \(session.isReachable ? "Reachable" : "Not Reachable")")
    }
}
