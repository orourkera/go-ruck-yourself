import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

/// 🍎 **iOS Share Extension for GPX Files**
/// 
/// Handles GPX files shared from AllTrails and other apps
/// Processes the files and passes them to the main app
class ShareViewController: SLComposeServiceViewController {
    
    // MARK: - Configuration
    private let groupId = "group.com.rucksack.shared"
    private let maxFileSize: Int64 = 10 * 1024 * 1024 // 10MB limit
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedContent()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "Import Route to Ruck!"
        navigationController?.navigationBar.tintColor = UIColor(red: 0.8, green: 0.4, blue: 0.16, alpha: 1.0) // Ruck orange
        
        // Customize the placeholder text
        placeholder = "Add notes about this route (optional)"
        
        // Set character limit for notes
        charactersRemaining = 200
    }
    
    // MARK: - Content Processing
    private func processSharedContent() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("No content to share")
            return
        }
        
        for inputItem in inputItems {
            guard let attachments = inputItem.attachments else { continue }
            
            for attachment in attachments {
                processAttachment(attachment)
            }
        }
    }
    
    private func processAttachment(_ attachment: NSItemProvider) {
        // Check for GPX files
        if attachment.hasItemConformingToTypeIdentifier(UTType.xml.identifier) ||
           attachment.hasItemConformingToTypeIdentifier("public.xml") ||
           attachment.hasItemConformingToTypeIdentifier("com.topografix.gpx") {
            
            attachment.loadItem(forTypeIdentifier: UTType.xml.identifier, options: nil) { [weak self] (data, error) in
                DispatchQueue.main.async {
                    self?.handleGPXData(data, error: error)
                }
            }
        }
        // Check for file URLs
        else if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] (data, error) in
                DispatchQueue.main.async {
                    self?.handleFileURL(data, error: error)
                }
            }
        }
        // Check for URLs (AllTrails links)
        else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (data, error) in
                DispatchQueue.main.async {
                    self?.handleURL(data, error: error)
                }
            }
        }
        // Check for plain text (might contain URLs)
        else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (data, error) in
                DispatchQueue.main.async {
                    self?.handleText(data, error: error)
                }
            }
        }
    }
    
    // MARK: - Data Handlers
    private func handleGPXData(_ data: Any?, error: Error?) {
        guard let data = data else {
            showError("Failed to load GPX data: \\(error?.localizedDescription ?? \"Unknown error\")")
            return
        }
        
        var gpxContent: String?
        
        if let stringData = data as? String {
            gpxContent = stringData
        } else if let urlData = data as? URL {
            do {
                gpxContent = try String(contentsOf: urlData, encoding: .utf8)
            } catch {
                showError("Failed to read GPX file: \\(error.localizedDescription)")
                return
            }
        } else if let nsData = data as? Data {
            gpxContent = String(data: nsData, encoding: .utf8)
        }
        
        guard let validGPXContent = gpxContent else {
            showError("Invalid GPX file format")
            return
        }
        
        // Validate GPX content
        if !isValidGPX(validGPXContent) {
            showError("File does not appear to be a valid GPX file")
            return
        }
        
        // Check file size
        if validGPXContent.count > maxFileSize {
            showError("GPX file is too large (max 10MB)")
            return
        }
        
        saveGPXToSharedContainer(validGPXContent)
    }
    
    private func handleFileURL(_ data: Any?, error: Error?) {
        guard let fileURL = data as? URL else {
            showError("Failed to load file: \\(error?.localizedDescription ?? \"Unknown error\")")
            return
        }
        
        // Check if it's a GPX file
        let pathExtension = fileURL.pathExtension.lowercased()
        guard pathExtension == "gpx" else {
            showError("Only GPX files are supported")
            return
        }
        
        do {
            let gpxContent = try String(contentsOf: fileURL, encoding: .utf8)
            
            if !isValidGPX(gpxContent) {
                showError("Invalid GPX file format")
                return
            }
            
            if gpxContent.count > maxFileSize {
                showError("GPX file is too large (max 10MB)")
                return
            }
            
            saveGPXToSharedContainer(gpxContent)
        } catch {
            showError("Failed to read GPX file: \\(error.localizedDescription)")
        }
    }
    
    private func handleURL(_ data: Any?, error: Error?) {
        guard let url = data as? URL else {
            showError("Failed to load URL: \\(error?.localizedDescription ?? \"Unknown error\")")
            return
        }
        
        let urlString = url.absoluteString
        
        // Check if it's an AllTrails URL
        if urlString.contains("alltrails.com") {
            saveURLToSharedContainer(urlString, type: "alltrails")
        } else if urlString.hasSuffix(".gpx") {
            // Direct GPX file URL
            downloadGPXFromURL(url)
        } else {
            showError("Unsupported URL format")
        }
    }
    
    private func handleText(_ data: Any?, error: Error?) {
        guard let text = data as? String else {
            showError("Failed to load text: \\(error?.localizedDescription ?? \"Unknown error\")")
            return
        }
        
        // Check if text contains a URL
        if let url = extractURLFromText(text) {
            handleURL(url, error: nil)
        } else {
            showError("No valid URLs found in shared text")
        }
    }
    
    // MARK: - Helper Methods
    private func isValidGPX(_ content: String) -> Bool {
        // Basic GPX validation
        return content.contains("<gpx") && 
               content.contains("</gpx>") && 
               (content.contains("<trk") || content.contains("<wpt") || content.contains("<rte"))
    }
    
    private func extractURLFromText(_ text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        for match in matches ?? [] {
            if let range = Range(match.range, in: text) {
                let urlString = String(text[range])
                if let url = URL(string: urlString) {
                    return url
                }
            }
        }
        return nil
    }
    
    private func downloadGPXFromURL(_ url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.showError("Failed to download GPX: \\(error.localizedDescription)")
                    return
                }
                
                guard let data = data,
                      let gpxContent = String(data: data, encoding: .utf8) else {
                    self.showError("Failed to read downloaded GPX file")
                    return
                }
                
                if !self.isValidGPX(gpxContent) {
                    self.showError("Downloaded file is not a valid GPX")
                    return
                }
                
                self.saveGPXToSharedContainer(gpxContent)
            }
        }.resume()
    }
    
    // MARK: - Shared Container Operations
    private func saveGPXToSharedContainer(_ gpxContent: String) {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            showError("Failed to access shared container")
            return
        }
        
        let fileName = "shared_route_\\(Date().timeIntervalSince1970).gpx"
        let fileURL = sharedContainer.appendingPathComponent(fileName)
        
        do {
            try gpxContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Save metadata
            let metadata: [String: Any] = [
                "type": "gpx",
                "fileName": fileName,
                "notes": contentText ?? "",
                "timestamp": Date().timeIntervalSince1970,
                "source": "share_extension"
            ]
            
            saveMetadata(metadata, for: fileName)
            showSuccess("Route imported successfully!")
            
        } catch {
            showError("Failed to save GPX file: \\(error.localizedDescription)")
        }
    }
    
    private func saveURLToSharedContainer(_ urlString: String, type: String) {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            showError("Failed to access shared container")
            return
        }
        
        let fileName = "shared_url_\\(Date().timeIntervalSince1970).json"
        let fileURL = sharedContainer.appendingPathComponent(fileName)
        
        let data: [String: Any] = [
            "type": "url",
            "urlType": type,
            "url": urlString,
            "notes": contentText ?? "",
            "timestamp": Date().timeIntervalSince1970,
            "source": "share_extension"
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
            try jsonData.write(to: fileURL)
            
            saveMetadata(data, for: fileName)
            showSuccess("URL saved for import!")
            
        } catch {
            showError("Failed to save URL: \\(error.localizedDescription)")
        }
    }
    
    private func saveMetadata(_ metadata: [String: Any], for fileName: String) {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else {
            return
        }
        
        let metadataURL = sharedContainer.appendingPathComponent("metadata.json")
        var allMetadata: [[String: Any]] = []
        
        // Load existing metadata
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            if let data = try? Data(contentsOf: metadataURL),
               let existing = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                allMetadata = existing
            }
        }
        
        // Add new metadata
        var newMetadata = metadata
        newMetadata["fileName"] = fileName
        allMetadata.append(newMetadata)
        
        // Save updated metadata
        do {
            let data = try JSONSerialization.data(withJSONObject: allMetadata, options: [])
            try data.write(to: metadataURL)
        } catch {
            print("Failed to save metadata: \\(error)")
        }
    }
    
    // MARK: - UI Feedback
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Import Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "ShareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        })
        present(alert, animated: true)
    }
    
    private func showSuccess(_ message: String) {
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Open Ruck!", style: .default) { [weak self] _ in
            self?.openMainApp()
        })
        alert.addAction(UIAlertAction(title: "Done", style: .cancel) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        })
        present(alert, animated: true)
    }
    
    private func openMainApp() {
        let url = URL(string: "goruckyourself://import")!
        
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = responder?.next
        }
        
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    // MARK: - SLComposeServiceViewController Overrides
    override func isContentValid() -> Bool {
        // Validate content length
        let characterCount = contentText?.count ?? 0
        charactersRemaining = max(0, 200 - characterCount)
        return true
    }
    
    override func didSelectPost() {
        // This method is called when the user taps "Post"
        // The actual processing is handled in processSharedContent()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    override func configurationItems() -> [Any]! {
        // Return an array of SLComposeSheetConfigurationItem, if desired
        return []
    }
}
