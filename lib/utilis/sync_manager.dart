import 'package:stock_count/config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'dart:math';
import 'package:path/path.dart';
import 'package:stock_count/utilis/db_schema.dart';

class SyncManager {
  // Use a method to get the base URL asynchronously
  static Future<String> get _baseUrl async => await AppConfig.baseUrl;
  static Future<Database> getDatabase() async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'stock_count.db');
    return await openDatabase(
      path,
      version: DBSchema.dbVersion,
      onCreate: DBSchema.initDB,
      onUpgrade: DBSchema.onUpgrade,
    );
  }

  static String generateSyncUuid() {
    final random = Random.secure();
    String chunk(int length) => List.generate(
          length,
          (_) => random.nextInt(16).toRadixString(16),
        ).join();
    return '${chunk(8)}-${chunk(4)}-${chunk(4)}-${chunk(4)}-${chunk(12)}';
  }

  static Future<void> _ensureSyncUuids(Database db) async {
    final entriesMissingUuid = await db.query(
      'StockCountEntry',
      columns: ['id'],
      where: "sync_uuid IS NULL OR trim(sync_uuid) = ''",
    );
    for (final row in entriesMissingUuid) {
      await db.update(
        'StockCountEntry',
        {'sync_uuid': generateSyncUuid()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    final itemsMissingUuid = await db.query(
      'StockCountEntryItem',
      columns: ['id'],
      where: "sync_uuid IS NULL OR trim(sync_uuid) = ''",
    );
    for (final row in itemsMissingUuid) {
      await db.update(
        'StockCountEntryItem',
        {'sync_uuid': generateSyncUuid()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  // Sync to server without refreshing token automatically
  static Future<void> syncToServer() async {
    final prefs = await SharedPreferences.getInstance();
    String? accessToken = prefs.getString('accessToken');
    DateTime? tokenExpiry = DateTime.tryParse(prefs.getString('tokenExpiry') ?? '');

    // Proceed only if token is still valid
    if (accessToken == null ||
        accessToken.isEmpty ||
        tokenExpiry == null ||
        DateTime.now().isAfter(tokenExpiry)) {
      print("Access token is either missing or expired. Sync aborted.");
      return;
    }

    Database db = await getDatabase();
    await _ensureSyncUuids(db);

    try {
      // Fetch only unsynced entries (synced = 0)
      List<Map<String, dynamic>> unsyncedEntries = await db.query(
        'StockCountEntry',
        where: 'synced = ?',
        whereArgs: [0],
      );

      if (unsyncedEntries.isNotEmpty) {
        List<Map<String, dynamic>> bulkData = [];

        for (var entry in unsyncedEntries) {
          // Fetch associated unsynced items for each entry
          List<Map<String, dynamic>> entryItems = await db.query(
            'StockCountEntryItem',
            where: 'stock_count_entry_id = ? AND synced = 0',
            whereArgs: [entry['id']],
          );

          bulkData.add({
            'entry': {
              'local_id': (entry['sync_uuid'] ?? '').toString(),
              'company': entry['company'],
              'set_warehouse':
                  entry['warehouse'], // Map 'warehouse' to 'set_warehouse'
              'posting_date': entry['posting_date'],
              'posting_time': entry['posting_time'],
              'scan_reference_mode': entry['scan_reference_mode'] ?? '',
            },
            'entry_items': entryItems.map((item) {
              final mode = (item['scan_reference_mode'] ??
                      entry['scan_reference_mode'] ??
                      '')
                  .toString()
                  .trim();
              final rawScanValue = (item['scan_value'] ?? item['item_barcode'] ?? '')
                  .toString()
                  .trim();
              final itemCodeRaw = (item['item_code'] ?? '').toString().trim();
              final batchNoRaw = (item['batch_no'] ?? '').toString().trim();
              final serialNoRaw = (item['serial_no'] ?? '').toString().trim();

              String barcodePayload = '';
              String? itemCodePayload = itemCodeRaw.isEmpty ? null : itemCodeRaw;
              String? batchNoPayload = batchNoRaw.isEmpty ? null : batchNoRaw;
              String? serialNoPayload = serialNoRaw.isEmpty ? null : serialNoRaw;

              if (mode == 'Item Code') {
                itemCodePayload ??= rawScanValue.isNotEmpty ? rawScanValue : null;
              } else if (mode == 'Batch No') {
                batchNoPayload ??= rawScanValue.isNotEmpty ? rawScanValue : null;
              } else if (mode == 'Serial No') {
                serialNoPayload ??= rawScanValue.isNotEmpty ? rawScanValue : null;
              } else {
                barcodePayload = rawScanValue;
              }

              return {
                'local_id': (item['sync_uuid'] ?? '').toString(),
                'scan_reference_mode': mode,
                'scan_value': rawScanValue,
                'barcode': barcodePayload,
                'item_code': itemCodePayload,
                'batch_no': batchNoPayload,
                'serial_no': serialNoPayload,
                'warehouse': item['warehouse'],
                'qty': item['qty'],
              };
            }).toList(),
          });
        }

        var postData = {
          'api_call_type': 'sync_bulk_entries',
          'entries': bulkData,
        };

        final baseUrl = await _baseUrl;
        var response = await http.post(
          Uri.parse('$baseUrl/api/method/nex_bridge.api.stock_take.sync_entry'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(postData),
        );

        if (response.statusCode == 200) {
          var responseData = jsonDecode(response.body);
          final message = responseData['message'] as Map<String, dynamic>? ?? {};
          final status = (message['status'] ?? '').toString();
          final serverMessage = (message['message'] ?? '').toString();
          var syncedEntries = message['synced_entries'];
          var failedEntries = message['failed_entries'];

          if (status == 'error') {
            throw Exception(serverMessage.isNotEmpty
                ? serverMessage
                : 'Server rejected all entries.');
          }

          if (syncedEntries != null &&
              syncedEntries is List &&
              syncedEntries.isNotEmpty) {
            for (var syncedEntry in syncedEntries) {
              final syncedEntryUuid =
                  (syncedEntry['local_id'] ?? '').toString().trim();
              if (syncedEntryUuid.isEmpty) {
                continue;
              }
              await db.update(
                'StockCountEntry',
                {
                  'synced': 1,
                  'server_id': syncedEntry['server_id'],
                  'last_sync_time': DateTime.now().toIso8601String(),
                },
                where: 'sync_uuid = ?',
                whereArgs: [syncedEntryUuid],
              );

              List<dynamic> syncedItems = syncedEntry['items'] ?? [];

              for (var syncedItem in syncedItems) {
                final syncedItemUuid =
                    (syncedItem['local_id'] ?? '').toString().trim();
                if (syncedItemUuid.isEmpty) {
                  continue;
                }
                await db.update(
                  'StockCountEntryItem',
                  {
                    'synced': 1,
                    'server_id': syncedItem['server_id'],
                    'last_sync_time': DateTime.now().toIso8601String(),
                  },
                  where: 'sync_uuid = ?',
                  whereArgs: [syncedItemUuid],
                );
              }
            }
          } else {
            if (failedEntries is List && failedEntries.isNotEmpty) {
              throw Exception(serverMessage.isNotEmpty
                  ? serverMessage
                  : 'Server failed to sync entries.');
            }
            print("No synced entries found in response.");
          }
        } else {
          print("Error during bulk sync: ${response.body}");
        }
      } else {
        print("No unsynced entries found for sync.");
      }
    } catch (e) {
      print("Bulk sync to server failed: $e");
    }
  }

  // Revised syncFromServer method based on server_id
  static Future<void> syncFromServer() async {
    final prefs = await SharedPreferences.getInstance();
    String? accessToken = prefs.getString('accessToken');
    DateTime? tokenExpiry = DateTime.tryParse(prefs.getString('tokenExpiry') ?? '');

    // Proceed only if token is still valid
    if (accessToken == null ||
        accessToken.isEmpty ||
        tokenExpiry == null ||
        DateTime.now().isAfter(tokenExpiry)) {
      print("Access token is either missing or expired. Sync aborted.");
      return;
    }

    try {
      var postData = {'api_call_type': 'get_entries'};

      final baseUrl = await _baseUrl;
      var response = await http.post(
        Uri.parse('$baseUrl/api/method/nex_bridge.api.stock_take.sync_entry'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(postData),
      );

      if (response.statusCode == 200) {
        var responseData = jsonDecode(response.body)['message'];
        List<dynamic> serverEntries = responseData['entries'] ?? [];

        Database db = await getDatabase();

        for (var entry in serverEntries) {
          String? serverId = entry['name'];
          List<Map<String, dynamic>> localEntry = await db.query(
            'StockCountEntry',
            where: 'server_id = ?',
            whereArgs: [serverId],
          );

          if (localEntry.isEmpty) {
            await db.insert(
              'StockCountEntry',
              {
                'server_id': serverId,
                'sync_uuid': (entry['local_id'] ?? '').toString().isNotEmpty
                    ? entry['local_id']
                    : generateSyncUuid(),
                'company': entry['company'],
                'warehouse': entry['set_warehouse'],
                'posting_date': entry['posting_date'],
                'posting_time': entry['posting_time'],
                'scan_reference_mode': entry['scan_reference_mode'] ?? '',
                'stock_count_person': entry['owner'],
                'synced': 1,
                'last_sync_time': DateTime.now().toIso8601String(),
              },
            );

            List<dynamic> entryItems = entry['items'] ?? [];
            for (var item in entryItems) {
              final itemMode =
                  (item['scan_reference_mode'] ?? entry['scan_reference_mode'] ?? '')
                      .toString();
              final itemScanValue = (item['scan_value'] ??
                      item['barcode'] ??
                      item['item_code'] ??
                      item['batch_no'] ??
                      item['serial_no'] ??
                      '')
                  .toString();
              await db.insert(
                'StockCountEntryItem',
                {
                  'stock_count_entry_id':
                      await _getLocalEntryIdByServerId(db, serverId!),
                  'server_id': item['name'],
                  'sync_uuid': (item['local_id'] ?? '').toString().isNotEmpty
                      ? item['local_id']
                      : generateSyncUuid(),
                  'scan_reference_mode': itemMode,
                  'scan_value': itemScanValue,
                  'item_barcode': (item['barcode'] ?? '').toString(),
                  'item_code': item['item_code'],
                  'batch_no': item['batch_no'],
                  'serial_no': item['serial_no'],
                  'warehouse': item['warehouse'],
                  'qty': item['qty'],
                  'synced': 1,
                  'last_sync_time': DateTime.now().toIso8601String(),
                },
              );
            }
          } else {
            await db.update(
              'StockCountEntry',
              {
                'sync_uuid': (entry['local_id'] ?? '').toString().isNotEmpty
                    ? entry['local_id']
                    : generateSyncUuid(),
                'company': entry['company'],
                'warehouse': entry['set_warehouse'],
                'posting_date': entry['posting_date'],
                'posting_time': entry['posting_time'],
                'scan_reference_mode': entry['scan_reference_mode'] ?? '',
                'stock_count_person': entry['owner'],
                'synced': 1,
                'last_sync_time': DateTime.now().toIso8601String(),
              },
              where: 'server_id = ?',
              whereArgs: [serverId],
            );

            List<dynamic> entryItems = entry['items'] ?? [];
            for (var item in entryItems) {
              String? itemServerId = item['name'];
              final itemMode =
                  (item['scan_reference_mode'] ?? entry['scan_reference_mode'] ?? '')
                      .toString();
              final itemScanValue = (item['scan_value'] ??
                      item['barcode'] ??
                      item['item_code'] ??
                      item['batch_no'] ??
                      item['serial_no'] ??
                      '')
                  .toString();
              List<Map<String, dynamic>> localItem = await db.query(
                'StockCountEntryItem',
                where: 'server_id = ?',
                whereArgs: [itemServerId],
              );

              if (localItem.isEmpty) {
                await db.insert(
                  'StockCountEntryItem',
                  {
                    'stock_count_entry_id':
                        await _getLocalEntryIdByServerId(db, serverId!),
                    'server_id': itemServerId,
                    'sync_uuid': (item['local_id'] ?? '').toString().isNotEmpty
                        ? item['local_id']
                        : generateSyncUuid(),
                    'scan_reference_mode': itemMode,
                    'scan_value': itemScanValue,
                    'item_barcode': (item['barcode'] ?? '').toString(),
                    'item_code': item['item_code'],
                    'batch_no': item['batch_no'],
                    'serial_no': item['serial_no'],
                    'warehouse': item['warehouse'],
                    'qty': item['qty'],
                    'synced': 1,
                    'last_sync_time': DateTime.now().toIso8601String(),
                  },
                );
              } else {
                await db.update(
                  'StockCountEntryItem',
                  {
                    'sync_uuid': (item['local_id'] ?? '').toString().isNotEmpty
                        ? item['local_id']
                        : generateSyncUuid(),
                    'scan_reference_mode': itemMode,
                    'scan_value': itemScanValue,
                    'item_barcode': (item['barcode'] ?? '').toString(),
                    'item_code': item['item_code'],
                    'batch_no': item['batch_no'],
                    'serial_no': item['serial_no'],
                    'warehouse': item['warehouse'],
                    'qty': item['qty'],
                    'synced': 1,
                    'last_sync_time': DateTime.now().toIso8601String(),
                  },
                  where: 'server_id = ?',
                  whereArgs: [itemServerId],
                );
              }
            }
          }
        }

        print("Fetch from server completed successfully.");
      } else {
        print("Error fetching from server: ${response.body}");
      }
    } catch (e) {
      print("Fetch from server failed: $e");
    }
  }

  // Helper method to get local entry id by server_id
  static Future<int?> _getLocalEntryIdByServerId(
      Database db, String serverId) async {
    List<Map<String, dynamic>> result = await db.query(
      'StockCountEntry',
      where: 'server_id = ?',
      whereArgs: [serverId],
      columns: ['id'],
    );

    if (result.isNotEmpty) {
      return result.first['id'] as int?;
    }
    return null;
  }

  // Method to fetch and store warehouses and companies in SharedPreferences
  static Future<void> fetchAndStoreWarehousesAndCompanies() async {
    final prefs = await SharedPreferences.getInstance();
    String? accessToken = prefs.getString('accessToken');
    DateTime? tokenExpiry = DateTime.tryParse(prefs.getString('tokenExpiry') ?? '');

    if (accessToken == null ||
        accessToken.isEmpty ||
        tokenExpiry == null ||
        DateTime.now().isAfter(tokenExpiry)) {
      print("Access token is either missing or expired. Sync aborted.");
      return;
    }

    // Clear previous data
    await prefs.remove('warehouses_by_company');
    await prefs.remove('companies');
    print(
        "Cleared previous warehouse and company data before fetching new ones.");

    try {
      final baseUrl = await _baseUrl;
      var response = await http.post(
        Uri.parse(
            '$baseUrl/api/method/nex_bridge.api.stock_take.get_warehouses_grouped_by_company'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['message'] != null &&
            data['message']['warehouses_by_company'] != null &&
            data['message']['companies'] != null) {
          Map<String, List<String>> warehousesByCompany = {};
          (data['message']['warehouses_by_company'] as Map<String, dynamic>)
              .forEach((key, value) {
            warehousesByCompany[key] =
                List<String>.from(value as List<dynamic>);
          });

          List<String> companies =
              List<String>.from(data['message']['companies']);

          await prefs.setString(
              'warehouses_by_company', jsonEncode(warehousesByCompany));
          await prefs.setString('companies', jsonEncode(companies));

          print("Warehouses and companies stored in SharedPreferences.");
        } else {
          print("Unexpected response format for warehouses and companies.");
        }
      } else {
        print("Failed to fetch warehouses and companies: ${response.body}");
      }
    } catch (e) {
      print("Error fetching warehouses and companies: $e");
    }
  }

  // Method to fetch and store offline scan reference masters for Item/Batch/Serial modes
  static Future<void> fetchAndStoreScanReferenceMasters() async {
    final prefs = await SharedPreferences.getInstance();
    String? accessToken = prefs.getString('accessToken');
    DateTime? tokenExpiry = DateTime.tryParse(prefs.getString('tokenExpiry') ?? '');

    if (accessToken == null ||
        accessToken.isEmpty ||
        tokenExpiry == null ||
        DateTime.now().isAfter(tokenExpiry)) {
      print("Access token is either missing or expired. Sync aborted.");
      return;
    }

    try {
      await prefs.remove('scan_reference_masters');
      final baseUrl = await _baseUrl;
      var response = await http.post(
        Uri.parse(
            '$baseUrl/api/method/nex_bridge.api.stock_take.get_scan_reference_masters'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['message'] is Map<String, dynamic>) {
          final message = Map<String, dynamic>.from(data['message']);
          final payload = {
            'items': message['items'] is List ? message['items'] : <dynamic>[],
            'barcodes':
                message['barcodes'] is List ? message['barcodes'] : <dynamic>[],
            'batches':
                message['batches'] is List ? message['batches'] : <dynamic>[],
            'serial_nos': message['serial_nos'] is List
                ? message['serial_nos']
                : <dynamic>[],
            'scope': (message['scope'] ?? 'unknown').toString(),
            'item_count': message['item_count'] ?? 0,
          };
          await prefs.setString('scan_reference_masters', jsonEncode(payload));
          await prefs.setString('scan_reference_master_scope',
              (payload['scope'] ?? 'unknown').toString());
        } else {
          await prefs.remove('scan_reference_masters');
          print("Unexpected response format for scan reference masters.");
        }
      } else {
        print("Failed to fetch scan reference masters: ${response.body}");
      }
    } catch (e) {
      print("Error fetching scan reference masters: $e");
    }
  }

  static Future<Map<String, int>> getCachedMasterCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMasters = prefs.getString('scan_reference_masters');
    if (rawMasters == null) {
      return {
        'items': 0,
        'barcodes': 0,
        'batches': 0,
        'serial_nos': 0,
        'item_count': 0,
      };
    }

    try {
      final decoded = jsonDecode(rawMasters);
      if (decoded is! Map<String, dynamic>) {
        return {
          'items': 0,
          'barcodes': 0,
          'batches': 0,
          'serial_nos': 0,
          'item_count': 0,
        };
      }
      return {
        'items': decoded['items'] is List ? (decoded['items'] as List).length : 0,
        'barcodes':
            decoded['barcodes'] is List ? (decoded['barcodes'] as List).length : 0,
        'batches':
            decoded['batches'] is List ? (decoded['batches'] as List).length : 0,
        'serial_nos': decoded['serial_nos'] is List
            ? (decoded['serial_nos'] as List).length
            : 0,
        'item_count': decoded['item_count'] is int
            ? decoded['item_count']
            : int.tryParse((decoded['item_count'] ?? '0').toString()) ??
                0,
      };
    } catch (_) {
      return {
        'items': 0,
        'barcodes': 0,
        'batches': 0,
        'serial_nos': 0,
        'item_count': 0,
      };
    }
  }
}

  // Token refreshing logic for login (not used in background tasks)
  // static Future<void> refreshTokenIfNeeded() async {
  //   var authBox = await _getAuthBox(); // Ensure box is open
  //   String? refreshToken = authBox.get('refreshToken');
  //   DateTime? tokenExpiry = DateTime.tryParse(authBox.get('tokenExpiry') ?? '');

  //   if (tokenExpiry != null && DateTime.now().isAfter(tokenExpiry)) {
  //     print("Token expired, refreshing...");
  //     try {
  //       var response = await http.post(
  //         Uri.parse(
  //             '$_baseUrl/api/method/frappe.integrations.oauth2.get_token'),
  //         headers: {
  //           'Content-Type': 'application/x-www-form-urlencoded',
  //         },
  //         body: {
  //           'grant_type': 'refresh_token',
  //           'refresh_token': refreshToken,
  //           'client_id': AppConfig.clientId,
  //           'redirect_uri': AppConfig.redirectUri,
  //         },
  //       );

  //       if (response.statusCode == 200) {
  //         var tokenData = jsonDecode(response.body);
  //         authBox.put('accessToken', tokenData['access_token']);
  //         authBox.put('tokenExpiry',
  //             DateTime.now().add(Duration(seconds: tokenData['expires_in'])));
  //         print("Token refreshed successfully.");
  //       } else {
  //         print("Error refreshing token: ${response.body}");
  //       }
  //     } catch (e) {
  //       print("Token refresh failed: $e");
  //     }
  //   } else {
  //     print("Token still valid, no need to refresh.");
  //   }
  // }
}
