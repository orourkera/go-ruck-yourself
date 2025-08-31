import Foundation
import Flutter
import CoreMotion

// Stream handler for barometric pressure EventChannel
class BarometerStreamHandler: NSObject, FlutterStreamHandler {
    private static var eventSink: FlutterEventSink?
    private let altimeter = CMAltimeter()
    private var isListening = false
    
    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        print("[BAROMETER_STREAM] Flutter listening for barometric pressure updates")
        BarometerStreamHandler.eventSink = eventSink
        
        // Check if barometric pressure is available
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            print("[BAROMETER_STREAM] Barometric pressure not available on this device")
            return FlutterError(code: "UNAVAILABLE",
                               message: "Barometric pressure not available",
                               details: nil)
        }
        
        // Start altitude updates
        isListening = true
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { [weak self] (data, error) in
            guard self?.isListening == true else { return }
            
            if let error = error {
                print("[BAROMETER_STREAM] Error: \(error.localizedDescription)")
                eventSink(FlutterError(code: "ERROR",
                                      message: error.localizedDescription,
                                      details: nil))
                return
            }
            
            if let data = data {
                // Convert kPa to hPa (1 kPa = 10 hPa)
                let pressureHPa = data.pressure.doubleValue * 10
                let altitudeMeters = data.relativeAltitude.doubleValue
                
                let barometerData: [String: Any] = [
                    "pressure": pressureHPa,
                    "altitude": altitudeMeters,
                    "timestamp": Date().timeIntervalSince1970
                ]
                
                print("[BAROMETER_STREAM] Sending data: pressure=\(pressureHPa) hPa, altitude=\(altitudeMeters) m")
                eventSink(barometerData)
            }
        }
        
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("[BAROMETER_STREAM] Flutter stopped listening for barometric pressure updates")
        isListening = false
        altimeter.stopRelativeAltitudeUpdates()
        BarometerStreamHandler.eventSink = nil
        return nil
    }
}