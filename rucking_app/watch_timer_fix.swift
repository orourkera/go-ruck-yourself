// Format timer consistently as HH:MM:SS regardless of duration
if let duration = metrics["duration"] as? Int {
    let hours = duration / 3600
    let minutes = (duration % 3600) / 60
    let seconds = duration % 60
    
    // Always use HH:MM:SS format for consistency
    self.status = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}
