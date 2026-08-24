import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:stock_count/constants/theme.dart';
import 'package:stock_count/screens/setup_dialog.dart';
import 'package:stock_count/utilis/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  DateTime? backPressTime;
  bool _isLoggingIn = false;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        bool backStatus = onWillPop();
        if (backStatus) {
          exit(0);
        }
        return false;
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              // Settings button
              IconButton(
                icon: const Icon(Icons.settings, color: primaryColor),
                onPressed: () => _showSettingsDialog(context),
                tooltip: 'App Settings',
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  // Header Animation (Lottie)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Lottie.asset(
                      'assets/lottie_assets/2.json',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const Spacer(flex: 1),
                  // Title and Description Information
                  const LoginInfo(
                    title: "STOCK TAKE",
                    description:
                        "Streamline your stock management with real-time data integration and easy ERPNext connectivity. Simplifying your stock-taking process for higher efficiency.",
                  ),
                  const Spacer(flex: 2),
                  // Login Button with fixed height
                  loginButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Login Button with loader support, fixed height of 48, retaining original styling
  Widget loginButton(BuildContext context) {
    return InkWell(
      onTap: _isLoggingIn
          ? null
          : () async {
              setState(() {
                _isLoggingIn = true;
              });
              await ApiService.loginWithFrappe(context);
              setState(() {
                _isLoggingIn = false;
              });
            },
      child: Container(
        height: 48,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: fixPadding * 2.0),
        decoration: BoxDecoration(
          color: secondaryColor,
          borderRadius: BorderRadius.circular(10.0),
          boxShadow: [
            BoxShadow(
              color: secondaryColor.withOpacity(0.1),
              blurRadius: 12.0,
              offset: const Offset(0, 6),
            )
          ],
        ),
        alignment: Alignment.center,
        child: _isLoggingIn
            ? const SizedBox(
                width: 20,
                height: 21,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                "GET STARTED",
                style: bold18White,
              ),
      ),
    );
  }

  // Show settings dialog
  Future<void> _showSettingsDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return const SetupDialog(isFirstLaunch: false);
      },
    );

    // If configuration was updated successfully, refresh the app state
    if (result == true) {
      setState(() {});
    }
  }

  // Custom back button handler: double-tap to exit
  bool onWillPop() {
    DateTime now = DateTime.now();
    if (backPressTime == null ||
        now.difference(backPressTime!) > const Duration(seconds: 2)) {
      backPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          backgroundColor: blackColor,
          content: Text(
            "Press back once again to exit",
            style: semibold15White,
          ),
        ),
      );
      return false;
    } else {
      return true;
    }
  }
}

class LoginInfo extends StatelessWidget {
  const LoginInfo({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        alignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
