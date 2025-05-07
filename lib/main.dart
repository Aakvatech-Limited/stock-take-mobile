import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:stock_count/constants/theme.dart';
import 'package:stock_count/screens/login.dart';
import 'package:stock_count/utilis/change_notifier.dart';
import 'package:stock_count/utilis/sync_manager.dart'; // Import sync manager
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

// Initialize periodic sync tasks
Timer? _syncTimer;

void startPeriodicSync() {
  // Cancel any existing timer
  _syncTimer?.cancel();

  // Create a new timer that runs every 15 minutes
  _syncTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
    print("Starting periodic sync at ${DateTime.now()}");

    // Fetch data from server
    try {
      await SyncManager.fetchAndStoreWarehousesAndCompanies();
      await SyncManager.fetchAndStoreAssignedItems();
      await SyncManager.syncFromServer();
      print("Fetch sync completed at ${DateTime.now()}");
    } catch (e) {
      print("Error during fetch sync: $e");
    }

    // Post data to server
    try {
      await SyncManager.syncToServer();
      print("Post sync completed at ${DateTime.now()}");
    } catch (e) {
      print("Error during post sync: $e");
    }
  });

  print("Periodic sync scheduled every 15 minutes");
}

// Initialize Hive for background tasks
Future<void> initializeHiveForBackgroundTasks() async {
  final appDocumentDir = await getApplicationDocumentsDirectory();
  Hive.init(appDocumentDir.path);
  await Hive.openBox('authBox');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox('authBox');

  // Start periodic sync tasks if not on web
  if (!kIsWeb) {
    try {
      startPeriodicSync();
      print("Periodic sync initialized successfully");
    } catch (e) {
      print("Failed to initialize periodic sync: $e");
    }
  } else {
    print("Periodic sync not supported on web platform");
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => StockTakeNotifier(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock Taking',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          secondary: secondaryColor,
        ),
        primaryColor: primaryColor,
        fontFamily: 'Montserrat',
      ),
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
    );
  }
}

// Old callback functions have been removed
