import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceHelper {
  static const _secureStorage = FlutterSecureStorage();
  static const String _uuidKey = 'upasthitix_device_uuid';
  static String? _cachedDeviceId;

  /// Retrieves a cryptographically secure random UUID bound to the device.
  /// Uses FlutterSecureStorage (Android Keystore / iOS Keychain) to persist
  /// the key securely and prevent cloned apps from accessing it.
  static Future<String> getUniqueDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    String? secureId;
    try {
      secureId = await _secureStorage.read(key: _uuidKey);
    } catch (e) {
      debugPrint('[DeviceHelper] Failed to read from SecureStorage: $e');
    }

    String? prefsId;
    try {
      final prefs = await SharedPreferences.getInstance();
      prefsId = prefs.getString('app_fallback_device_id') ?? prefs.getString('web_device_id');
    } catch (e) {
      debugPrint('[DeviceHelper] Failed to read SharedPreferences: $e');
    }

    // 1. If both exist and match, caching is successful
    if (secureId != null && secureId.isNotEmpty && prefsId != null && prefsId.isNotEmpty) {
      if (secureId == prefsId) {
        _cachedDeviceId = secureId;
        return _cachedDeviceId!;
      }
    }

    // 2. Self-Healing Case A: Keystore has it, but SharedPreferences does not
    if (secureId != null && secureId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_fallback_device_id', secureId);
      } catch (_) {}
      _cachedDeviceId = secureId;
      return _cachedDeviceId!;
    }

    // 3. Self-Healing Case B: SharedPreferences has it, but Keystore does not (e.g. corruption/update)
    if (prefsId != null && prefsId.isNotEmpty) {
      try {
        await _secureStorage.write(key: _uuidKey, value: prefsId);
      } catch (_) {}
      _cachedDeviceId = prefsId;
      return _cachedDeviceId!;
    }

    // 4. Generate new if both are missing
    final newId = _generateSecureUUID();
    try {
      await _secureStorage.write(key: _uuidKey, value: newId);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_fallback_device_id', newId);
    } catch (_) {}

    _cachedDeviceId = newId;
    return _cachedDeviceId!;
  }

  /// Generates a cryptographically secure RFC 4122 Version 4 UUID.
  static String _generateSecureUUID() {
    final Random random = Random.secure();
    final List<int> values = List<int>.generate(16, (i) => random.nextInt(256));
    
    // Set version 4 (random)
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant
    values[8] = (values[8] & 0x3f) | 0x80;
    
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return 'dev_${buffer.toString()}';
  }
}
