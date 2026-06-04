import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/carbon.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:hive/hive.dart'; // Hive for token management

import 'package:stock_count/components/calculator_card.dart';
import 'package:stock_count/components/center_box.dart';
import 'package:stock_count/constants/theme.dart';
import 'package:stock_count/utilis/change_notifier.dart';
import 'package:stock_count/utilis/db_schema.dart';
import 'package:stock_count/utilis/dialog_messages.dart';
import 'package:stock_count/utilis/sync_manager.dart';
import 'package:stock_count/screens/login.dart'; // Import login screen

class HomeScreen extends StatefulWidget {
  final int? recountEntryId;
  final String? recountWarehouse;
  final String? countType;
  final String? scanReferenceMode;
  final Database? database;

  const HomeScreen({
    Key? key,
    this.countType,
    this.scanReferenceMode,
    this.recountEntryId,
    this.recountWarehouse,
    this.database,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool showCountTypeButton = true;
  Database? database;
  int currentEntryId = 0;
  bool isCountStarted = false;
  String? selectedWarehouse;
  String? selectedCompany;
  bool isWarehouseSelected = false;
  bool recountEntry = false;
  String? firstName;
  String? lastName;
  String? userEmail;
  String? profilePictureUrl;
  String? accessToken;
  bool isTokenExpired = false; // Variable to track token expiration
  List<Map<String, dynamic>> masterItems = [];
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = ""; // State to store search input

  // Variables for slide-in dialog
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isDialogVisible = false;
  bool _isCloudSyncing = false;
  bool _isMasterSyncing = false;

  @override
  void initState() {
    super.initState();
    checkAuthentication(); // Check authentication before loading HomeScreen
    initializeDb();

    // Initialize Animation Controller for the slide-in dialog
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500), // Slow down the transition
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Start off-screen
      end: Offset.zero, // End at screen's center
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Initialize fade animation
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    if (widget.recountEntryId != null &&
        widget.recountWarehouse != null &&
        widget.countType != null) {
      currentEntryId = widget.recountEntryId!;
      selectedWarehouse = widget.recountWarehouse!;
      context.read<StockTakeNotifier>().setCountType(widget.countType!);
      context
          .read<StockTakeNotifier>()
          .setScanReferenceMode(widget.scanReferenceMode ?? '');
      isCountStarted = true;
      showCountTypeButton = false;
      recountEntry = true;
      database = widget.database;
    }
  }

  // Check if the user is authenticated by verifying the token
  Future<void> checkAuthentication() async {
    var authBox = await Hive.openBox('authBox');
    String? accessToken = authBox.get('accessToken');
    String? tokenExpiryString =
        authBox.get('tokenExpiry'); // Retrieve as String

    DateTime? tokenExpiry;

    // Parse the tokenExpiryString to DateTime if it's not null
    if (tokenExpiryString != null) {
      tokenExpiry = DateTime.parse(tokenExpiryString);
    }

    // If no token or token is expired, redirect to login
    if (accessToken == null ||
        tokenExpiry == null ||
        DateTime.now().isAfter(tokenExpiry)) {
      // Token is invalid or expired, log out and redirect to login
      logOutUser();
      return;
    }

    // If token is valid, proceed to fetch user details
    fetchUserDetails();
  }

  // Log out user and clear Hive token data
  void logOutUser() async {
    var authBox = await Hive.openBox('authBox');
    await authBox.clear(); // Clear all stored token data

    // Navigate to login screen
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> fetchUserDetails() async {
    var authBox = await Hive.openBox('authBox');
    String? userDetailsJson = authBox.get('userDetails');
    accessToken = authBox.get('accessToken');

    if (userDetailsJson != null) {
      Map<String, dynamic> userDetails = json.decode(userDetailsJson);

      setState(() {
        firstName = userDetails['given_name'];
        lastName = userDetails['family_name'] ?? "";
        userEmail = userDetails['email'];
        profilePictureUrl = userDetails['picture'];
      });
    } else {
      showErrorDialog(context, "User details are missing.");
    }
  }

  Future<void> initializeDb() async {
    var databasesPath = await getDatabasesPath();
    String path = p.join(databasesPath, 'stock_count.db');

    database = await openDatabase(
      path,
      version: DBSchema.dbVersion,
      onCreate: DBSchema.initDB,
      onUpgrade: DBSchema.onUpgrade,
    );
  }

  void startCount() async {
    var authBox = await Hive.openBox('authBox');
    String? userId = authBox.get('userId');
    final stockTakeNotifier =
        Provider.of<StockTakeNotifier>(context, listen: false);

    String postingDate = DateTime.now().toString().substring(0, 10);
    String postingTime = DateTime.now().toString().substring(11);

    int id = await database!.insert('StockCountEntry', {
      'sync_uuid': SyncManager.generateSyncUuid(),
      'company': selectedCompany,
      'warehouse': selectedWarehouse,
      'posting_date': postingDate,
      'posting_time': postingTime,
      'scan_reference_mode': stockTakeNotifier.scanReferenceMode,
      'stock_count_person': userId
    });

    setState(() {
      currentEntryId = id;
    });
  }

  // Toggle the visibility of the slide-in dialog and fetch masters if counting is started
  void _toggleDialog() {
    if (_isDialogVisible) {
      _animationController.reverse().then((_) {
        setState(() {
          _isDialogVisible = false;
        });
      });
    } else {
      if (isCountStarted) {
        fetchMasterItems(); // Fetch item masters only when opening the dialog in count mode
      }
      setState(() {
        _isDialogVisible = true;
      });
      _animationController.forward();
    }
  }

  List<Widget> get _pages {
    return isCountStarted
        ? [
            CalculatorCard(
                database: database,
                entryId: currentEntryId,
                warehouse: selectedWarehouse,
                recountEntry: recountEntry),
            CenterBox(database: database)
          ]
        : [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: fixPadding * 2.0),
              child: Center(
                child: Text(
                  "Tap Scan Setup to choose scanner source and optional reference mode, then press Start Count.",
                  style: medium15Grey,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            CenterBox(database: database),
          ];
  }

  void _onItemTapped(int index) async {
    if (_isDialogVisible && index != 1) {
      _animationController.reverse().then((_) {
        if (!mounted) return;
        setState(() {
          _isDialogVisible = false;
        });
      });
    }

    if (Provider.of<StockTakeNotifier>(context, listen: false).countType ==
            'Count type' &&
        _selectedIndex == 0 &&
        index != 1) {
      showErrorDialog(context, "Please select the Count type first.");
      return;
    }

    if (index == 0 && !isCountStarted && _selectedIndex != 1) {
      // Fetch both warehouses and companies from Hive storage
      var authBox = await Hive.openBox('authBox'); // Ensure Hive box is open

      String? warehousesJson = authBox.get('warehouses_by_company');
      String? companiesJson = authBox.get('companies');

      if (warehousesJson != null && companiesJson != null) {
        Map<String, List<String>> warehousesByCompany = {};
        (jsonDecode(warehousesJson) as Map<String, dynamic>)
            .forEach((key, value) {
          warehousesByCompany[key] = List<String>.from(value as List<dynamic>);
        });

        List<String> companies = List<String>.from(jsonDecode(companiesJson));

        if (warehousesByCompany.isNotEmpty) {
          showWarehouseBottomSheet(context, warehousesByCompany, companies);
        }
      } else {
        // Optional: handle the case where no data is found in Hive
        showErrorDialog(
            context, 'No warehouse or company data found in local storage.');
      }
      return;
    } else if (isCountStarted && index == 1) {
      showErrorDialog(context, "Please stop the count first.");
      return;
    } else if (isCountStarted) {
      setState(() {
        isCountStarted = false;
        showCountTypeButton = true;
        _selectedIndex =
            1; // Navigate to "Entries" tab when stop count is pressed
      });
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> fetchMasterItems() async {
    final items = await _loadMasterItemsFromCache();
    if (!mounted) return;
    if (items.isEmpty) {
      showErrorDialog(context, 'No master items found. Please pull masters first.');
      return;
    }
    setState(() {
      masterItems = items;
    });
  }

  Future<List<Map<String, dynamic>>> _loadMasterItemsFromCache() async {
    var authBox = await Hive.openBox('authBox');
    final rawMasters = authBox.get('scan_reference_masters');
    if (rawMasters == null) return <Map<String, dynamic>>[];

    try {
      final decoded = rawMasters is String ? jsonDecode(rawMasters) : rawMasters;
      if (decoded is! Map<String, dynamic>) return <Map<String, dynamic>>[];
      final rawItems = decoded['items'];
      final items = <Map<String, dynamic>>[];
      if (rawItems is List) {
        for (final row in rawItems.whereType<Map>()) {
          final itemCode = (row['item_code'] ?? row['item'] ?? '').toString().trim();
          if (itemCode.isEmpty) continue;
          items.add({
            'item_code': itemCode,
            'item_name': (row['item_name'] ?? '').toString().trim(),
          });
        }
      }
      items.sort((a, b) =>
          (a['item_code'] as String).compareTo((b['item_code'] as String)));
      return items;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _showItemCodePickerForCounting() async {
    final items = await _loadMasterItemsFromCache();
    if (!mounted) return;
    if (items.isEmpty) {
      showErrorDialog(context, 'No master items found. Please pull masters first.');
      return;
    }

    final notifier = Provider.of<StockTakeNotifier>(context, listen: false);
    final searchController = TextEditingController();
    String query = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = items.where((item) {
              final itemCode =
                  (item['item_code'] ?? '').toString().toLowerCase();
              final itemName =
                  (item['item_name'] ?? '').toString().toLowerCase();
              final q = query.toLowerCase();
              return itemCode.contains(q) || itemName.contains(q);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Items', style: semibold16Black33),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchController,
                        onChanged: (value) => setModalState(() => query = value),
                        decoration: InputDecoration(
                          hintText: 'Search item code or name',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    searchController.clear();
                                    setModalState(() => query = '');
                                  },
                                  icon: const Icon(Icons.clear),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching items'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final itemCode =
                                    (item['item_code'] ?? '').toString();
                                final itemName =
                                    (item['item_name'] ?? '').toString();
                                return ListTile(
                                  title: Text(itemCode, style: medium14Black33),
                                  subtitle:
                                      itemName.isNotEmpty ? Text(itemName) : null,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    notifier.setScannedData(itemCode);
                                    Navigator.of(sheetContext).pop();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadMasterBatchesFromCache() async {
    var authBox = await Hive.openBox('authBox');
    final rawMasters = authBox.get('scan_reference_masters');
    if (rawMasters == null) return <Map<String, dynamic>>[];

    try {
      final decoded = rawMasters is String ? jsonDecode(rawMasters) : rawMasters;
      if (decoded is! Map<String, dynamic>) return <Map<String, dynamic>>[];
      final rawBatches = decoded['batches'];
      final batches = <Map<String, dynamic>>[];
      if (rawBatches is List) {
        for (final row in rawBatches.whereType<Map>()) {
          final batchNo = (row['batch_no'] ?? '').toString().trim();
          final itemCode = (row['item_code'] ?? '').toString().trim();
          if (batchNo.isEmpty) continue;
          batches.add({
            'batch_no': batchNo,
            'item_code': itemCode,
          });
        }
      }
      batches.sort((a, b) =>
          (a['batch_no'] as String).compareTo((b['batch_no'] as String)));
      return batches;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _showBatchNoPickerForCounting() async {
    final batches = await _loadMasterBatchesFromCache();
    if (!mounted) return;
    if (batches.isEmpty) {
      showErrorDialog(context, 'No master batches found. Please pull masters first.');
      return;
    }

    final notifier = Provider.of<StockTakeNotifier>(context, listen: false);
    final searchController = TextEditingController();
    String query = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = batches.where((batch) {
              final batchNo = (batch['batch_no'] ?? '').toString().toLowerCase();
              final itemCode = (batch['item_code'] ?? '').toString().toLowerCase();
              final q = query.toLowerCase();
              return batchNo.contains(q) || itemCode.contains(q);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Batches', style: semibold16Black33),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchController,
                        onChanged: (value) => setModalState(() => query = value),
                        decoration: InputDecoration(
                          hintText: 'Search batch no or item code',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    searchController.clear();
                                    setModalState(() => query = '');
                                  },
                                  icon: const Icon(Icons.clear),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching batches'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final batch = filtered[index];
                                final batchNo = (batch['batch_no'] ?? '').toString();
                                final itemCode = (batch['item_code'] ?? '').toString();
                                return ListTile(
                                  title: Text(batchNo, style: medium14Black33),
                                  subtitle: itemCode.isNotEmpty ? Text('Item: $itemCode') : null,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    notifier.setScannedData(batchNo);
                                    Navigator.of(sheetContext).pop();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
  }

  Future<void> _syncToCloud() async {
    if (_isCloudSyncing) return;

    setState(() {
      _isCloudSyncing = true;
    });

    try {
      await SyncManager.syncToServer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud sync completed.')),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, "Cloud sync failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isCloudSyncing = false;
        });
      }
    }
  }

  Future<void> _syncMasters() async {
    if (_isMasterSyncing) return;

    setState(() {
      _isMasterSyncing = true;
    });

    try {
      await SyncManager.fetchAndStoreWarehousesAndCompanies();
      await SyncManager.fetchAndStoreScanReferenceMasters();
      await SyncManager.syncFromServer();
      final authBox = await Hive.openBox('authBox');
      final scope = (authBox.get('scan_reference_master_scope') ?? 'unknown')
          .toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Master sync completed [$scope].',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, "Master sync failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isMasterSyncing = false;
        });
      }
    }
  }

  Future<void> _addMasterItemWithQty(String itemCode, int qty) async {
    if (database == null) {
      showErrorDialog(context, 'Database is not ready.');
      return;
    }
    if (!isCountStarted || currentEntryId == 0) {
      showErrorDialog(context, 'Please start count before adding items.');
      return;
    }
    if (qty <= 0) {
      showErrorDialog(context, 'Quantity must be greater than zero.');
      return;
    }

    final warehouse = selectedWarehouse ?? widget.recountWarehouse;
    if (warehouse == null || warehouse.isEmpty) {
      showErrorDialog(context, 'Warehouse is missing for this entry.');
      return;
    }

    final existingEntries = await database!.query(
      'StockCountEntryItem',
      where:
          'stock_count_entry_id = ? AND scan_reference_mode = ? AND scan_value = ? AND warehouse = ?',
      whereArgs: [currentEntryId, 'Item Code', itemCode, warehouse],
      limit: 1,
    );

    if (existingEntries.isNotEmpty) {
      final existingSyncUuid =
          (existingEntries.first['sync_uuid'] ?? '').toString().trim();
      final updateData = <String, Object?>{
        'scan_reference_mode': 'Item Code',
        'scan_value': itemCode,
        'item_barcode': '',
        'item_code': itemCode,
        'batch_no': '',
        'serial_no': '',
        'qty': qty,
        'synced': 0,
      };
      if (existingSyncUuid.isEmpty) {
        updateData['sync_uuid'] = SyncManager.generateSyncUuid();
      }

      await database!.update(
        'StockCountEntryItem',
        updateData,
        where:
            'stock_count_entry_id = ? AND scan_reference_mode = ? AND scan_value = ? AND warehouse = ?',
        whereArgs: [currentEntryId, 'Item Code', itemCode, warehouse],
      );
    } else {
      await database!.insert(
        'StockCountEntryItem',
        {
          'stock_count_entry_id': currentEntryId,
          'sync_uuid': SyncManager.generateSyncUuid(),
          'scan_reference_mode': 'Item Code',
          'scan_value': itemCode,
          'item_barcode': '',
          'item_code': itemCode,
          'batch_no': '',
          'serial_no': '',
          'warehouse': warehouse,
          'qty': qty,
          'synced': 0,
        },
      );
    }

    await database!.update(
      'StockCountEntry',
      {'synced': 0},
      where: 'id = ?',
      whereArgs: [currentEntryId],
    );

    if (!mounted) return;
    final notifier = Provider.of<StockTakeNotifier>(context, listen: false);
    notifier.setScanReferenceMode('Item Code');
    notifier.setScannedData(itemCode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added $itemCode with qty $qty')),
    );
  }

  Future<void> _showMasterItemQtyDialog(String itemCode) async {
    final qtyController = TextEditingController(text: '1');
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(itemCode, style: semibold16Black33),
              const SizedBox(height: 10),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final qty = int.tryParse(qtyController.text.trim()) ?? 0;
                Navigator.of(dialogContext).pop();
                await _addMasterItemWithQty(itemCode, qty);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stockTakeNotifier = context.watch<StockTakeNotifier>();
    final currentMode = stockTakeNotifier.scanReferenceMode.trim();
    final showPickerAction = isCountStarted &&
        _selectedIndex == 0 &&
        (currentMode == 'Item Code' || currentMode == 'Batch No');

    return Stack(
      children: [
        Scaffold(
          backgroundColor: f8Color,
          appBar: AppBar(
            elevation: 0,
            toolbarHeight: 70.0,
            automaticallyImplyLeading: false,
            centerTitle: false,
            backgroundColor: primaryColor,
            titleSpacing: 20.0,
            title: headerTitle(),
            actions: [
              if (showPickerAction)
                IconButton(
                  tooltip: currentMode == 'Item Code' ? 'Items' : 'Batches',
                  onPressed: currentMode == 'Item Code'
                      ? _showItemCodePickerForCounting
                      : _showBatchNoPickerForCounting,
                  icon: const Icon(
                    Icons.list_alt_rounded,
                    color: whiteColor,
                    size: 22.0,
                  ),
                ),
              IconButton(
                tooltip: 'Sync Cloud',
                onPressed: _isCloudSyncing ? null : _syncToCloud,
                icon: _isCloudSyncing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: whiteColor,
                        ),
                      )
                    : const Icon(
                        Icons.cloud_upload_outlined,
                        color: whiteColor,
                        size: 22.0,
                      ),
              ),
              IconButton(
                tooltip: 'Pull Masters',
                onPressed: _isMasterSyncing ? null : _syncMasters,
                icon: _isMasterSyncing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: whiteColor,
                        ),
                      )
                    : const Icon(
                        Icons.sync,
                        color: whiteColor,
                        size: 22.0,
                      ),
              ),
              if (_selectedIndex == 1)
                IconButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: fixPadding * 2.0),
                  onPressed: _toggleDialog, // Trigger the slide-in dialog
                  icon: Iconify(
                    isCountStarted ? Carbon.list : Carbon.settings,
                    color: whiteColor,
                    size: 22.0,
                  ),
                ),
            ],
          ),
          body: Consumer<StockTakeNotifier>(
            builder: (context, stockTakeNotifier, child) {
              return _pages.elementAt(_selectedIndex);
            },
          ),
          floatingActionButton: showCountTypeButton
              ? FloatingActionButton.extended(
                  onPressed: () => _showScanSetupDialog(context),
                  backgroundColor: primaryColor,
                  label: Consumer<StockTakeNotifier>(
                    builder: (context, stockTakeNotifier, child) {
                      return Text(
                        _scanSetupLabel(stockTakeNotifier),
                        style: const TextStyle(color: Colors.white),
                      );
                    },
                  ),
                  icon: const Icon(Icons.tune, color: Colors.white),
                )
              : null,
          bottomNavigationBar: BottomNavigationBar(
            items: _selectedIndex == 1 && isCountStarted
                ? [
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.list_alt), // Change to a list icon
                      label: 'Entries', // Update label to "Entries"
                    ),
                  ]
                : isCountStarted
                    ? [
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.stop_circle_outlined),
                          label: 'Stop Count',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.list_alt), // Change to a list icon
                          label: 'Entries', // Update label to "Entries"
                        ),
                      ]
                    : [
                        const BottomNavigationBarItem(
                          icon: Icon(Icons
                              .play_circle_outline), // Use play icon from Icons
                          label: 'Start Count',
                        ),
                        const BottomNavigationBarItem(
                          icon:
                              Icon(Icons.list_alt), // Use list icon from Icons
                          label: 'Entries', // Update label to "Entries"
                        ),
                      ],
            currentIndex: _selectedIndex,
            selectedItemColor: primaryColor,
            unselectedItemColor: greyColor,
            onTap: _onItemTapped,
          ),
        ),
        if (_isDialogVisible) ...[
          FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onTap:
                  _toggleDialog, // Close the drawer if you tap on the dimmed area
              child: Container(
                color:
                    Colors.black.withValues(alpha: 0.5), // Dim the background
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          SlideTransition(
            position: _slideAnimation,
            child: Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: Colors.white,
                child: Container(
                  width: MediaQuery.of(context).size.width *
                      0.6, // Half-screen width
                  height: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: isCountStarted
                        ? buildMasterItemsList()
                        : buildSettingsList(),
                  ),
                ),
              ),
            ),
          ),
        ]
      ],
    );
  }

// Build list of settings items (when not counting)
  List<Widget> buildSettingsList() {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Settings', style: semibold16Black33),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _toggleDialog,
          ),
        ],
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Logout', style: medium14Black33),
        onTap: logOutUser,
      ),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('Version 0.0.1', style: medium14Black33),
      ),
      const Spacer(),
      const Divider(),
      Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: Image.asset(
          'assets/images/aakvatech.jpg',
          width: MediaQuery.of(context).size.width * 0.5,
        ),
      ),
    ];
  }

  List<Widget> buildMasterItemsList() {
    // Filter items based on the search query
    List<Map<String, dynamic>> filteredItems = masterItems.where((item) {
      final itemCode = (item['item_code'] ?? '').toString().toLowerCase();
      final itemName = (item['item_name'] ?? '').toString().toLowerCase();
      final query = searchQuery.toLowerCase();
      return itemCode.contains(query) || itemName.contains(query);
    }).toList();

    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Items', style: semibold16Black33),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _toggleDialog,
          ),
        ],
      ),
      const Divider(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {
              searchQuery = value;
            });
          },
          decoration: InputDecoration(
            hintText: "Search items...",
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        searchQuery = "";
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
          ),
        ),
      ),
      const Divider(),
      Flexible(
        child: filteredItems.isNotEmpty
            ? ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  var item = filteredItems[index];
                  final itemCode = (item['item_code'] ?? '').toString();
                  final itemName = (item['item_name'] ?? '').toString();
                  return ListTile(
                    title: Text(itemCode.isNotEmpty ? itemCode : 'Unnamed Item',
                        style: medium14Black33),
                    subtitle: Text(
                      itemName.isNotEmpty ? itemName : 'Tap to enter quantity and add',
                    ),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: itemCode.isEmpty
                        ? null
                        : () => _showMasterItemQtyDialog(itemCode),
                  );
                },
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox, size: 40, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    const Text(
                      "No items found",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
      ),
      const Divider(),
    ];
  }

  void _showScanSetupDialog(BuildContext context) {
    final notifier = context.read<StockTakeNotifier>();
    String tempCountType = notifier.countType;
    String tempReferenceMode = notifier.scanReferenceMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                color: whiteColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
              ),
              child: SafeArea(
                child: Wrap(
                  children: [
                    const Center(
                      child: Text('Scan Setup', style: semibold18Primary),
                    ),
                    const SizedBox(height: 14),
                    const Text('Scanner Source', style: semibold15Black33),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSetupOption(
                            title: 'Beam',
                            icon: Icons.document_scanner_outlined,
                            isSelected: tempCountType == 'Beam',
                            onTap: () =>
                                setModalState(() => tempCountType = 'Beam'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildSetupOption(
                            title: 'Camera',
                            icon: Icons.qr_code_scanner,
                            isSelected: tempCountType == 'Camera',
                            onTap: () =>
                                setModalState(() => tempCountType = 'Camera'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Scan Reference Mode', style: semibold15Black33),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        _buildReferenceChip(
                          label: 'Blank',
                          value: '',
                          selectedValue: tempReferenceMode,
                          onSelected: (value) =>
                              setModalState(() => tempReferenceMode = value),
                        ),
                        _buildReferenceChip(
                          label: 'Item Code',
                          value: 'Item Code',
                          selectedValue: tempReferenceMode,
                          onSelected: (value) =>
                              setModalState(() => tempReferenceMode = value),
                        ),
                        _buildReferenceChip(
                          label: 'Batch No',
                          value: 'Batch No',
                          selectedValue: tempReferenceMode,
                          onSelected: (value) =>
                              setModalState(() => tempReferenceMode = value),
                        ),
                        _buildReferenceChip(
                          label: 'Serial No',
                          value: 'Serial No',
                          selectedValue: tempReferenceMode,
                          onSelected: (value) =>
                              setModalState(() => tempReferenceMode = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          notifier.setCountType(tempCountType);
                          notifier.setScanReferenceMode(tempReferenceMode);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Apply', style: semibold16White),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void showWarehouseBottomSheet(BuildContext context,
      Map<String, List<String>> warehousesByCompany, List<String> companies) {
    String defaultSelectedCompany =
        companies.isNotEmpty ? companies[0] : 'Select Company';
    List<String> filteredWarehouses =
        warehousesByCompany[defaultSelectedCompany] ?? [];
    bool isCompanyExpanded = false;
    bool isWarehouseExpanded = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: whiteColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select Options',
                      style: semibold18Primary, textAlign: TextAlign.center),
                  const SizedBox(height: 16.0),

                  // Accordion for Company Selection
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        isCompanyExpanded = !isCompanyExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 12.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: greyColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              defaultSelectedCompany,
                              style: medium14Black33,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            isCompanyExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: isCompanyExpanded ? companies.length * 50.0 : 0,
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: companies.length,
                      itemBuilder: (BuildContext context, int index) {
                        return ListTile(
                          title: Text(companies[index], style: medium14Black33),
                          onTap: () {
                            setState(() {
                              defaultSelectedCompany = companies[index];
                              filteredWarehouses =
                                  warehousesByCompany[defaultSelectedCompany] ??
                                      [];
                              isCompanyExpanded = false;
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16.0),

                  // Accordion for Warehouse List
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        isWarehouseExpanded = !isWarehouseExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 12.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: greyColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Warehouses', style: medium14Black33),
                          Icon(
                            isWarehouseExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16.0),

                  // Limited Height and Scrollable Warehouse List
                  Flexible(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: isWarehouseExpanded
                          ? MediaQuery.of(context).size.height * 0.5
                          : 0,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredWarehouses.length,
                        itemBuilder: (BuildContext context, int index) {
                          return ListTile(
                            title: Text(filteredWarehouses[index],
                                style: medium14Black33),
                            onTap: () {
                              Navigator.of(context).pop();
                              setState(() {
                                selectedWarehouse = filteredWarehouses[index];
                                selectedCompany = defaultSelectedCompany;
                                isCountStarted = true;
                                showCountTypeButton = false;
                              });
                              startCount();
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _scanSetupLabel(StockTakeNotifier notifier) {
    final scanner =
        notifier.countType == 'Count type' ? 'Scanner' : notifier.countType;
    final reference = notifier.scanReferenceMode.isEmpty
        ? 'Blank'
        : notifier.scanReferenceMode;
    return '$scanner • $reference';
  }

  Widget _buildSetupOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withValues(alpha: 0.08) : whiteColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? primaryColor : greyColor.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18, color: isSelected ? primaryColor : black33Color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? primaryColor : black33Color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceChip({
    required String label,
    required String value,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    final isSelected = selectedValue == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      labelStyle: TextStyle(
        color: isSelected ? whiteColor : black33Color,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: whiteColor,
      selectedColor: primaryColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: greyColor.withValues(alpha: 0.35)),
      ),
    );
  }

  Widget headerTitle() {
    return Row(
      children: [
        CircleAvatar(
          maxRadius: 25,
          backgroundColor: Colors.white,
          child: profilePictureUrl != null && accessToken != null
              ? ImageWithBearerToken(
                  imageUrl: profilePictureUrl!,
                  bearerToken: accessToken!,
                )
              : Text(
                  firstName != null ? firstName![0].toUpperCase() : 'S',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 25,
                    color: primaryColor,
                  ),
                ),
        ),
        widthSpace,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    firstName ?? "",
                    style: semibold16White,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(
                    width: 5,
                  ),
                  Text(
                    lastName ?? "",
                    style: semibold16White,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              heightBox(2.0),
              Row(
                children: [
                  const Iconify(
                    Carbon.email,
                    color: whiteColor,
                    size: 14.0,
                  ),
                  width5Space,
                  Expanded(
                    child: Text(
                      userEmail ?? "",
                      style: medium14White,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                ],
              )
            ],
          ),
        )
      ],
    );
  }
}

class ImageWithBearerToken extends StatelessWidget {
  final String imageUrl;
  final String bearerToken;

  const ImageWithBearerToken({
    required this.imageUrl,
    required this.bearerToken,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<http.Response>(
      future: _fetchImage(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading image'));
        } else if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasData) {
            if (snapshot.data!.statusCode == 200 &&
                snapshot.data!.headers['content-type']!.startsWith('image/')) {
              return Image.memory(snapshot.data!.bodyBytes);
            } else {
              return Center(child: Text('Invalid image data or unauthorized.'));
            }
          } else {
            return Center(child: Text('No data received.'));
          }
        } else {
          return const CircularProgressIndicator();
        }
      },
    );
  }

  Future<http.Response> _fetchImage() async {
    final headers = {'Authorization': 'Bearer $bearerToken'};
    final response = await http.get(Uri.parse(imageUrl), headers: headers);
    return response;
  }
}
