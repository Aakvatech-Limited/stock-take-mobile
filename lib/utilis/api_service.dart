import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:stock_count/config.dart';
import 'package:stock_count/screens/home.dart';
import 'package:stock_count/utilis/dialog_messages.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:hive/hive.dart';
import 'package:stock_count/utilis/sync_manager.dart'; // Import SyncManager to fetch user data

class ApiService {
  // We'll use methods instead of constants since we need to fetch values asynchronously
  static Future<String> get _clientId async => await AppConfig.clientId;
  static final String _redirectUri = AppConfig.redirectUri;
  static final String _tokenEndpoint = AppConfig.tokenEndpoint;
  static final String _userInfoEndpoint = AppConfig.userInfoEndpoint;

  // Helper method to get authorization endpoint (same as base URL)
  static Future<String> get _authorizationEndpoint async =>
      await AppConfig.baseUrl;

  // Login with Frappe
  static Future<void> loginWithFrappe(BuildContext context) async {
    try {
      // Get the dynamic configuration values
      final baseUrl = await _authorizationEndpoint;
      final clientId = await _clientId;

      final url = Uri.parse(
          '$baseUrl/api/method/frappe.integrations.oauth2.authorize?client_id=$clientId&response_type=code&scope=all%20openid&redirect_uri=$_redirectUri');

      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: 'stockcount',
      );

      final code = Uri.parse(result).queryParameters['code'];

      if (code != null) {
        final tokenResponse = await http.post(
          Uri.parse('$baseUrl$_tokenEndpoint'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': _redirectUri,
            'client_id': clientId,
          },
        );

        if (tokenResponse.statusCode == 200) {
          final Map<String, dynamic> responseData =
              jsonDecode(tokenResponse.body);
          final accessToken = responseData['access_token'].replaceAll('"', '');
          final refreshToken = responseData['refresh_token'];
          final expiresIn =
              responseData['expires_in']; // Expiry time in seconds

          // Save tokens to Hive
          var authBox = Hive.box('authBox');
          await authBox.put('accessToken', accessToken);
          await authBox.put('refreshToken', refreshToken);
          await authBox.put('tokenExpiry',
              DateTime.now().add(Duration(seconds: expiresIn)).toString());

          // Fetch user information
          final userInfoResponse = await http.get(
            Uri.parse('$baseUrl$_userInfoEndpoint'),
            headers: {
              'Authorization': 'Bearer $accessToken',
            },
          );

          if (userInfoResponse.statusCode == 200) {
            final userInfo = jsonDecode(userInfoResponse.body);

            await authBox.put('userId', userInfo['email']);

            // Store user details in Hive
            await authBox.put('userDetails', jsonEncode(userInfo));

            // Fetch user-specific data (warehouses, companies, masters)
            await fetchUserSpecificData();

            // Navigate to HomeScreen
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (Route<dynamic> route) => false,
            );
          } else {
            showErrorDialog(
                context, "Failed to fetch user info: ${userInfoResponse.body}");
          }
        } else {
          showErrorDialog(context,
              "Token exchange failed with status: ${tokenResponse.body}");
        }
      } else {
        showErrorDialog(
            context, "No authorization code found in the redirect URL.");
      }
    } catch (e) {
      showErrorDialog(context, "An error occurred: $e");
    }
  }

  // Fetch user-specific data after successful login
  static Future<void> fetchUserSpecificData() async {
    await SyncManager.fetchAndStoreWarehousesAndCompanies();
    await SyncManager.fetchAndStoreScanReferenceMasters();
  }
}
