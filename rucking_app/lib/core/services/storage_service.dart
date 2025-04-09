import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interface for storage operations
abstract class StorageService {
  /// Store a string value
  Future<void> setString(String key, String value);
  
  /// Retrieve a string value
  Future<String?> getString(String key);
  
  /// Store a boolean value
  Future<void> setBool(String key, bool value);
  
  /// Retrieve a boolean value
  Future<bool> getBool(String key, {bool defaultValue = false});
  
  /// Store an integer value
  Future<void> setInt(String key, int value);
  
  /// Retrieve an integer value
  Future<int> getInt(String key, {int defaultValue = 0});
  
  /// Store a double value
  Future<void> setDouble(String key, double value);
  
  /// Retrieve a double value
  Future<double> getDouble(String key, {double defaultValue = 0.0});
  
  /// Store an object value (serialized to JSON)
  Future<void> setObject(String key, Map<String, dynamic> value);
  
  /// Retrieve an object value (deserialized from JSON)
  Future<Map<String, dynamic>?> getObject(String key);
  
  /// Store a string value securely
  Future<void> setSecureString(String key, String value);
  
  /// Retrieve a string value securely
  Future<String?> getSecureString(String key);
  
  /// Get the authentication token
  Future<String?> getAuthToken();
  
  /// Check if a key exists
  Future<bool> hasKey(String key);
  
  /// Remove a specific value
  Future<void> remove(String key);
  
  /// Remove a specific secure value
  Future<void> removeSecure(String key);
  
  /// Clear all stored values
  Future<void> clear();
}

/// Implementation of StorageService using SharedPreferences and FlutterSecureStorage
class StorageServiceImpl implements StorageService {
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;
  
  StorageServiceImpl(this._prefs, this._secureStorage);
  
  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }
  
  @override
  Future<String?> getString(String key) async {
    return _prefs.getString(key);
  }
  
  @override
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }
  
  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    return _prefs.getBool(key) ?? defaultValue;
  }
  
  @override
  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }
  
  @override
  Future<int> getInt(String key, {int defaultValue = 0}) async {
    return _prefs.getInt(key) ?? defaultValue;
  }
  
  @override
  Future<void> setDouble(String key, double value) async {
    await _prefs.setDouble(key, value);
  }
  
  @override
  Future<double> getDouble(String key, {double defaultValue = 0.0}) async {
    return _prefs.getDouble(key) ?? defaultValue;
  }
  
  @override
  Future<void> setObject(String key, Map<String, dynamic> value) async {
    final jsonString = jsonEncode(value);
    await _prefs.setString(key, jsonString);
  }
  
  @override
  Future<Map<String, dynamic>?> getObject(String key) async {
    final jsonString = _prefs.getString(key);
    if (jsonString == null) return null;
    
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
  
  @override
  Future<void> setSecureString(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }
  
  @override
  Future<String?> getSecureString(String key) async {
    return await _secureStorage.read(key: key);
  }
  
  @override
  Future<String?> getAuthToken() async {
    return await getSecureString('auth_token');
  }
  
  @override
  Future<bool> hasKey(String key) async {
    return _prefs.containsKey(key);
  }
  
  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
  
  @override
  Future<void> removeSecure(String key) async {
    await _secureStorage.delete(key: key);
  }
  
  @override
  Future<void> clear() async {
    await _prefs.clear();
    await _secureStorage.deleteAll();
  }
} 