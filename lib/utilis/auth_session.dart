import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_count/config.dart';

// Thrown when the server can't be reached or the login is no longer valid.
class SessionException implements Exception {
  final bool sessionExpired;

  const SessionException.offline() : sessionExpired = false;
  const SessionException.expired() : sessionExpired = true;

  String get message => sessionExpired
      ? 'Your session has expired. Please log in again. Your entries are saved on this device.'
      : 'No internet connection. Your entries are saved on this device.';

  @override
  String toString() => message;
}

class AuthSession {
  static const Duration _refreshTimeout = Duration(seconds: 30);
  static const Duration _expiryMargin = Duration(minutes: 2);

  static Future<String>? _pendingRefresh;

  // POSTs JSON to a Frappe method with a valid token. If the server rejects
  // the token, refreshes it and retries once.
  static Future<http.Response> post(String method, {Object? body}) async {
    final baseUrl = await AppConfig.baseUrl;
    final uri = Uri.parse('$baseUrl/api/method/$method');
    final encodedBody = body == null ? null : jsonEncode(body);

    var token = await getValidAccessToken();
    var response = await _send(uri, token, encodedBody);
    if (response.statusCode == 401 || response.statusCode == 403) {
      token = await getValidAccessToken(rejectedToken: token);
      response = await _send(uri, token, encodedBody);
    }
    return response;
  }

  // Returns a token that is valid for a few more minutes, refreshing it
  // first when needed. [rejectedToken] forces a refresh unless another call
  // already replaced that token.
  static Future<String> getValidAccessToken({String? rejectedToken}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken') ?? '';
    final expiry = DateTime.tryParse(prefs.getString('tokenExpiry') ?? '');
    final isFresh = token.isNotEmpty &&
        expiry != null &&
        DateTime.now().add(_expiryMargin).isBefore(expiry);

    if (isFresh && token != rejectedToken) return token;

    // Overlapping calls (e.g. the periodic timer and a button tap) share one
    // refresh instead of each spending the refresh token.
    _pendingRefresh ??=
        _refresh(prefs).whenComplete(() => _pendingRefresh = null);
    return _pendingRefresh!;
  }

  // Saves a token response from Frappe's get_token endpoint and returns the
  // access token. Keeps the old refresh token if no new one was sent.
  static Future<String> saveTokens(Map<String, dynamic> data) async {
    final rawAccessToken = data['access_token'];
    if (rawAccessToken == null) {
      throw Exception('Server did not return an access token.');
    }
    final accessToken = rawAccessToken.toString().replaceAll('"', '');
    final refreshToken = (data['refresh_token'] ?? '').toString();
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accessToken', accessToken);
    if (refreshToken.isNotEmpty) {
      await prefs.setString('refreshToken', refreshToken);
    }
    await prefs.setString('tokenExpiry',
        DateTime.now().add(Duration(seconds: expiresIn)).toString());
    return accessToken;
  }

  static Future<String> _refresh(SharedPreferences prefs) async {
    final refreshToken = prefs.getString('refreshToken') ?? '';
    if (refreshToken.isEmpty) throw const SessionException.expired();

    final baseUrl = await AppConfig.baseUrl;
    final clientId = await AppConfig.clientId;

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl${AppConfig.tokenEndpoint}'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId,
        },
      ).timeout(_refreshTimeout);
    } on Exception {
      throw const SessionException.offline();
    }

    // Frappe answers 400 for an invalid grant and 404 for an unknown or
    // deleted refresh token: both mean the user must log in again.
    if (response.statusCode >= 400 && response.statusCode < 500) {
      throw const SessionException.expired();
    }
    if (response.statusCode != 200) {
      throw Exception('Token refresh failed (${response.statusCode}).');
    }
    return saveTokens(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<http.Response> _send(
      Uri uri, String token, String? body) async {
    try {
      return await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: body,
      );
    } on Exception {
      throw const SessionException.offline();
    }
  }
}
