package com.ruck.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.*

/**
 * 🤖 **Android File Share Receiver for GPX Files**
 * 
 * Handles GPX files shared from AllTrails and other apps
 * Processes the files and notifies the main app
 */
class FileShareReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "FileShareReceiver"
        private const val MAX_FILE_SIZE = 10 * 1024 * 1024L // 10MB
        private const val SHARED_PREFS_NAME = "shared_files"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "FileShareReceiver triggered with action: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_SEND -> handleSingleFile(context, intent)
            Intent.ACTION_SEND_MULTIPLE -> handleMultipleFiles(context, intent)
            Intent.ACTION_VIEW -> handleFileOpen(context, intent)
        }
    }
    
    private fun handleSingleFile(context: Context, intent: Intent) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri != null) {
                    processSharedFile(context, uri, intent.getStringExtra(Intent.EXTRA_TEXT))
                } else {
                    // Check for text content (URLs)
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (!text.isNullOrEmpty()) {
                        processSharedText(context, text)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling single file", e)
                showError(context, "Failed to import file: ${e.message}")
            }
        }
    }
    
    private fun handleMultipleFiles(context: Context, intent: Intent) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                if (uris != null) {
                    for (uri in uris) {
                        processSharedFile(context, uri, null)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling multiple files", e)
                showError(context, "Failed to import files: ${e.message}")
            }
        }
    }
    
    private fun handleFileOpen(context: Context, intent: Intent) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val uri = intent.data
                if (uri != null) {
                    processSharedFile(context, uri, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling file open", e)
                showError(context, "Failed to open file: ${e.message}")
            }
        }
    }
    
    private suspend fun processSharedFile(context: Context, uri: Uri, notes: String?) {
        Log.d(TAG, "Processing shared file: $uri")
        
        val contentResolver = context.contentResolver
        val mimeType = contentResolver.getType(uri)
        
        Log.d(TAG, "File MIME type: $mimeType")
        
        // Check if it's a supported file type
        if (!isSupportedFileType(mimeType, uri)) {
            showError(context, "Unsupported file type. Only GPX files are supported.")
            return
        }
        
        try {
            contentResolver.openInputStream(uri)?.use { inputStream ->
                // Check file size
                val fileSize = getFileSize(inputStream)
                if (fileSize > MAX_FILE_SIZE) {
                    showError(context, "File is too large. Maximum size is 10MB.")
                    return
                }
                
                // Reset stream and read content
                contentResolver.openInputStream(uri)?.use { freshInputStream ->
                    val content = freshInputStream.readBytes().toString(Charsets.UTF_8)
                    
                    // Validate GPX content
                    if (!isValidGPX(content)) {
                        showError(context, "Invalid GPX file format.")
                        return
                    }
                    
                    // Save to shared directory
                    saveGPXFile(context, content, notes, uri)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing file", e)
            showError(context, "Failed to process file: ${e.message}")
        }
    }
    
    private fun processSharedText(context: Context, text: String) {
        Log.d(TAG, "Processing shared text: $text")
        
        // Check if text contains URLs
        val urlPattern = Regex("https?://[^\\s]+")
        val urls = urlPattern.findAll(text).map { it.value }.toList()
        
        if (urls.isEmpty()) {
            showError(context, "No valid URLs found in shared text.")
            return
        }
        
        for (url in urls) {
            if (isAllTrailsURL(url)) {
                saveSharedURL(context, url, "alltrails", text)
            } else if (url.endsWith(".gpx", ignoreCase = true)) {
                saveSharedURL(context, url, "gpx_download", text)
            }
        }
        
        if (urls.any { isAllTrailsURL(it) || it.endsWith(".gpx", ignoreCase = true) }) {
            showSuccess(context, "URL(s) saved for import!")
        } else {
            showError(context, "No supported URLs found. Only AllTrails links and GPX files are supported.")
        }
    }
    
    private fun isSupportedFileType(mimeType: String?, uri: Uri): Boolean {
        // Check MIME type
        val supportedMimeTypes = listOf(
            "application/gpx+xml",
            "application/xml",
            "text/xml",
            "application/octet-stream"
        )
        
        if (mimeType != null && supportedMimeTypes.contains(mimeType)) {
            return true
        }
        
        // Check file extension
        val fileName = uri.lastPathSegment?.lowercase() ?: ""
        return fileName.endsWith(".gpx")
    }
    
    private fun isValidGPX(content: String): Boolean {
        return content.contains("<gpx", ignoreCase = true) &&
               content.contains("</gpx>", ignoreCase = true) &&
               (content.contains("<trk", ignoreCase = true) ||
                content.contains("<wpt", ignoreCase = true) ||
                content.contains("<rte", ignoreCase = true))
    }
    
    private fun isAllTrailsURL(url: String): Boolean {
        return url.contains("alltrails.com", ignoreCase = true)
    }
    
    private fun getFileSize(inputStream: InputStream): Long {
        var size = 0L
        val buffer = ByteArray(1024)
        var bytesRead: Int
        while (inputStream.read(buffer).also { bytesRead = it } != -1) {
            size += bytesRead
        }
        return size
    }
    
    private fun saveGPXFile(context: Context, content: String, notes: String?, uri: Uri) {
        try {
            val timestamp = System.currentTimeMillis()
            val fileName = "shared_route_$timestamp.gpx"
            val internalDir = File(context.filesDir, "shared_imports")
            
            if (!internalDir.exists()) {
                internalDir.mkdirs()
            }
            
            val file = File(internalDir, fileName)
            FileOutputStream(file).use { outputStream ->
                outputStream.write(content.toByteArray())
            }
            
            // Save metadata
            val metadata = mapOf(
                "type" to "gpx",
                "fileName" to fileName,
                "notes" to (notes ?: ""),
                "timestamp" to timestamp,
                "source" to "intent_receiver",
                "originalUri" to uri.toString()
            )
            
            saveMetadata(context, metadata)
            
            Log.d(TAG, "GPX file saved: $fileName")
            showSuccess(context, "Route imported successfully!")
            
            // Notify main app if it's running
            notifyMainApp(context, "gpx_imported", fileName)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error saving GPX file", e)
            showError(context, "Failed to save GPX file: ${e.message}")
        }
    }
    
    private fun saveSharedURL(context: Context, url: String, type: String, originalText: String) {
        try {
            val timestamp = System.currentTimeMillis()
            val fileName = "shared_url_$timestamp.json"
            val internalDir = File(context.filesDir, "shared_imports")
            
            if (!internalDir.exists()) {
                internalDir.mkdirs()
            }
            
            val data = mapOf(
                "type" to "url",
                "urlType" to type,
                "url" to url,
                "notes" to originalText,
                "timestamp" to timestamp,
                "source" to "intent_receiver"
            )
            
            val file = File(internalDir, fileName)
            val jsonString = android.util.JsonWriter(file.writer()).use { writer ->
                writeJsonObject(writer, data)
                file.readText()
            }
            
            // Save metadata
            saveMetadata(context, data)
            
            Log.d(TAG, "URL saved: $fileName")
            
            // Notify main app if it's running
            notifyMainApp(context, "url_shared", fileName)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error saving URL", e)
            showError(context, "Failed to save URL: ${e.message}")
        }
    }
    
    private fun writeJsonObject(writer: android.util.JsonWriter, obj: Map<String, Any>) {
        writer.beginObject()
        for ((key, value) in obj) {
            writer.name(key)
            when (value) {
                is String -> writer.value(value)
                is Number -> writer.value(value)
                is Boolean -> writer.value(value)
                else -> writer.value(value.toString())
            }
        }
        writer.endObject()
    }
    
    private fun saveMetadata(context: Context, metadata: Map<String, Any>) {
        try {
            val sharedPrefs = context.getSharedPreferences(SHARED_PREFS_NAME, Context.MODE_PRIVATE)
            val editor = sharedPrefs.edit()
            
            // Convert metadata to JSON string for storage
            val metadataJson = buildString {
                append("{")
                metadata.entries.forEachIndexed { index, (key, value) ->
                    if (index > 0) append(",")
                    append("\"$key\":\"$value\"")
                }
                append("}")
            }
            
            val key = "import_${metadata["timestamp"]}"
            editor.putString(key, metadataJson)
            editor.apply()
            
            Log.d(TAG, "Metadata saved with key: $key")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving metadata", e)
        }
    }
    
    private fun notifyMainApp(context: Context, action: String, fileName: String) {
        try {
            val intent = Intent("com.goruckyourself.app.FILE_IMPORTED").apply {
                putExtra("action", action)
                putExtra("fileName", fileName)
                putExtra("timestamp", System.currentTimeMillis())
            }
            context.sendBroadcast(intent)
            Log.d(TAG, "Broadcast sent to main app: $action")
        } catch (e: Exception) {
            Log.e(TAG, "Error notifying main app", e)
        }
    }
    
    private fun showError(context: Context, message: String) {
        Log.e(TAG, "Error: $message")
        // In a real implementation, you might show a Toast or notification
        // For now, we'll just log the error
    }
    
    private fun showSuccess(context: Context, message: String) {
        Log.i(TAG, "Success: $message")
        // In a real implementation, you might show a Toast or notification
        // For now, we'll just log the success
    }
}
