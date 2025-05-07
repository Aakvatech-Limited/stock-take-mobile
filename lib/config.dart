import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // Default values (used as fallback)
  static const String _defaultClientId = 'pijppl7q46';
  static const String _defaultBaseUrl = 'https://dev14-csf-tz.aakvaerp.com';
  static const String redirectUri = 'stockcount://oauth2redirect';
  static const String tokenEndpoint =
      '/api/method/frappe.integrations.oauth2.get_token';
  static const String userInfoEndpoint =
      '/api/method/frappe.integrations.oauth2.openid_profile';

  // Shared preferences keys
  static const String _clientIdKey = 'client_id';
  static const String _baseUrlKey = 'base_url';
  static const String _configuredKey = 'is_configured';

  // Cached values
  static String? _clientId;
  static String? _baseUrl;
  static bool? _isConfigured;

  // Getters that use cached values or load from SharedPreferences
  static Future<String> get clientId async {
    if (_clientId != null) return _clientId!;
    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getString(_clientIdKey) ?? _defaultClientId;
    return _clientId!;
  }

  static Future<String> get baseUrl async {
    if (_baseUrl != null) return _baseUrl!;
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    return _baseUrl!;
  }

  static Future<bool> get isConfigured async {
    if (_isConfigured != null) return _isConfigured!;
    final prefs = await SharedPreferences.getInstance();
    _isConfigured = prefs.getBool(_configuredKey) ?? false;
    return _isConfigured!;
  }

  // Setters to update values in SharedPreferences
  static Future<bool> setClientId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = value;
    return prefs.setString(_clientIdKey, value);
  }

  static Future<bool> setBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = value;
    return prefs.setString(_baseUrlKey, value);
  }

  static Future<bool> setConfigured(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    _isConfigured = value;
    return prefs.setBool(_configuredKey, value);
  }

  // Save all configuration at once
  static Future<bool> saveConfig({
    required String clientId,
    required String baseUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = clientId;
    _baseUrl = baseUrl;
    _isConfigured = true;

    await prefs.setString(_clientIdKey, clientId);
    await prefs.setString(_baseUrlKey, baseUrl);
    return prefs.setBool(_configuredKey, true);
  }

  // Reset configuration to defaults
  static Future<bool> resetConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = _defaultClientId;
    _baseUrl = _defaultBaseUrl;
    _isConfigured = false;

    await prefs.setString(_clientIdKey, _defaultClientId);
    await prefs.setString(_baseUrlKey, _defaultBaseUrl);
    return prefs.setBool(_configuredKey, false);
  }
}
