import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_count/constants/theme.dart';
import 'package:stock_count/utilis/change_notifier.dart';
import 'package:stock_count/utilis/sync_manager.dart';
import 'package:stock_count/utilis/dialog_messages.dart';
import 'package:sunmi_scanner/sunmi_scanner.dart';

class CalculatorCard extends StatefulWidget {
  final Database? database;
  final int entryId;
  final warehouse;
  final bool? recountEntry;

  const CalculatorCard({
    Key? key,
    this.database,
    required this.entryId,
    required this.warehouse,
    this.recountEntry,
  }) : super(key: key);

  @override
  _CalculatorCardState createState() => _CalculatorCardState();
}

class _CalculatorCardState extends State<CalculatorCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final MobileScannerController scannerController = MobileScannerController();
  final TextEditingController scannedCodeController = TextEditingController();
  final TextEditingController qtyController = TextEditingController(text: '0');

  bool isCameraInitialized = false;

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));

    WidgetsBinding.instance.addObserver(this);

    final stockTakeNotifier =
        Provider.of<StockTakeNotifier>(context, listen: false);

    // Listen for changes in scannedData to fetch entry details
    stockTakeNotifier.addListener(() {
      if (stockTakeNotifier.scannedData.isNotEmpty) {
        if (scannedCodeController.text != stockTakeNotifier.scannedData) {
          scannedCodeController.text = stockTakeNotifier.scannedData;
        }
        if (mounted) {
          fetchExistingEntry();
        }
      }
    });

    scannedCodeController.addListener(() {
      if (stockTakeNotifier.scannedData != scannedCodeController.text) {
        stockTakeNotifier.setScannedData(scannedCodeController.text);
      }
    });

    final countType = stockTakeNotifier.countType;

    if (countType == 'Beam') {
      SunmiScanner.onBarcodeScanned().listen((event) {
        _setScannedValue(event);
      });
    }
  }

  @override
  void dispose() {
    scannerController.dispose();
    scannedCodeController.dispose();
    qtyController.dispose();
    _animationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      scannerController.stop();
    } else if (state == AppLifecycleState.resumed) {
      scannerController.start();
    }
  }

  void _setScannedValue(String value) {
    if (mounted) {
      Provider.of<StockTakeNotifier>(context, listen: false)
          .setScannedData(value);
      print("Scanned: $value");
    }
  }

  void fetchExistingEntry() async {
    if (!mounted) return;

    final stockTakeNotifier =
        Provider.of<StockTakeNotifier>(context, listen: false);
    final scanValue = stockTakeNotifier.scannedData.trim();
    final scanReferenceMode = stockTakeNotifier.scanReferenceMode;

    final existingEntry = await widget.database!.query(
      'StockCountEntryItem',
      where:
          'stock_count_entry_id = ? AND warehouse = ? AND ((scan_reference_mode = ? AND scan_value = ?) OR ((scan_reference_mode IS NULL OR scan_reference_mode = \'\') AND item_barcode = ?))',
      whereArgs: [
        widget.entryId,
        widget.warehouse,
        scanReferenceMode,
        scanValue,
        scanValue,
      ],
    );

    if (!mounted) return;

    setState(() {
      qtyController.text = existingEntry.isNotEmpty
          ? existingEntry.first['qty'].toString()
          : '0';
    });
  }

  Future<Map<String, dynamic>?> _resolveScanReference(
      String scanValue, String scanReferenceMode) async {
    final normalizedMode = scanReferenceMode.trim();
    final prefs = await SharedPreferences.getInstance();

    final rawMasters = prefs.getString('scan_reference_masters');
    final batchToItem = <String, String>{};
    final serialMap = <String, Map<String, String>>{};
    final barcodeToItem = <String, String>{};
    if (rawMasters != null) {
      try {
        final decoded =
            rawMasters is String ? jsonDecode(rawMasters) : rawMasters;
        if (decoded is Map<String, dynamic>) {
          final batches = decoded['batches'];
          if (batches is List) {
            for (final row in batches.whereType<Map>()) {
              final batchNo = (row['batch_no'] ?? '').toString().trim();
              final itemCode = (row['item_code'] ?? '').toString().trim();
              if (batchNo.isNotEmpty && itemCode.isNotEmpty) {
                batchToItem[batchNo] = itemCode;
                batchToItem[batchNo.toUpperCase()] = itemCode;
              }
            }
          }

          final serialNos = decoded['serial_nos'];
          if (serialNos is List) {
            for (final row in serialNos.whereType<Map>()) {
              final serialNo = (row['serial_no'] ?? '').toString().trim();
              final itemCode = (row['item_code'] ?? '').toString().trim();
              final batchNo = (row['batch_no'] ?? '').toString().trim();
              if (serialNo.isNotEmpty && itemCode.isNotEmpty) {
                serialMap[serialNo] = {
                  'item_code': itemCode,
                  'batch_no': batchNo,
                };
                serialMap[serialNo.toUpperCase()] = {
                  'item_code': itemCode,
                  'batch_no': batchNo,
                };
              }
            }
          }

          final barcodes = decoded['barcodes'];
          if (barcodes is List) {
            for (final row in barcodes.whereType<Map>()) {
              final barcode = (row['barcode'] ?? '').toString().trim();
              final itemCode = (row['item_code'] ?? '').toString().trim();
              if (barcode.isNotEmpty && itemCode.isNotEmpty) {
                barcodeToItem[barcode] = itemCode;
              }
            }
          }
        }
      } catch (_) {}
    }

    if (normalizedMode == 'Item Code') {
      final mappedItemCode = barcodeToItem[scanValue];
      final itemCode =
          (mappedItemCode ?? scanValue).trim();
      return {
        'scan_reference_mode': normalizedMode,
        'scan_value': scanValue,
        'item_barcode': '',
        'item_code': itemCode,
        'batch_no': '',
        'serial_no': '',
      };
    }

    if (normalizedMode == 'Batch No') {
      final itemCode = batchToItem[scanValue] ?? batchToItem[scanValue.toUpperCase()];
      if (itemCode == null || itemCode.isEmpty) {
        showErrorDialog(
          context,
          'Batch "$scanValue" was not found offline. Please sync masters first.',
        );
        return null;
      }

      return {
        'scan_reference_mode': normalizedMode,
        'scan_value': scanValue,
        'item_barcode': '',
        'item_code': itemCode,
        'batch_no': scanValue,
        'serial_no': '',
      };
    }

    if (normalizedMode == 'Serial No') {
      final serialDetails = serialMap[scanValue] ?? serialMap[scanValue.toUpperCase()];
      if (serialDetails == null || (serialDetails['item_code'] ?? '').isEmpty) {
        showErrorDialog(
          context,
          'Serial "$scanValue" was not found offline. Please sync masters first.',
        );
        return null;
      }

      return {
        'scan_reference_mode': normalizedMode,
        'scan_value': scanValue,
        'item_barcode': '',
        'item_code': serialDetails['item_code'],
        'batch_no': serialDetails['batch_no'] ?? '',
        'serial_no': scanValue,
      };
    }

    // Blank mode keeps classic barcode flow.
    return {
      'scan_reference_mode': '',
      'scan_value': scanValue,
      'item_barcode': scanValue,
      'item_code': '',
      'batch_no': '',
      'serial_no': '',
    };
  }

  void submitEntry() async {
    if (!mounted) return;

    final stockTakeNotifier =
        Provider.of<StockTakeNotifier>(context, listen: false);
    final scanValue = scannedCodeController.text.trim();
    final scanReferenceMode = stockTakeNotifier.scanReferenceMode.trim();
    int quantity = int.tryParse(qtyController.text) ?? 0;

    if (widget.database == null) {
      print("Database is null.");
      return;
    }

    if (widget.entryId != 0 && scanValue.isNotEmpty && quantity > 0) {
      if (scanReferenceMode == 'Serial No' && quantity != 1) {
        showErrorDialog(
          context,
          'Serial No mode accepts quantity 1 per scanned serial.',
        );
        return;
      }

      final resolved =
          await _resolveScanReference(scanValue, scanReferenceMode);
      if (resolved == null) {
        return;
      }

      List<Map> existingEntries = await widget.database!.query(
        'StockCountEntryItem',
        where:
            'stock_count_entry_id = ? AND scan_reference_mode = ? AND scan_value = ? AND warehouse = ?',
        whereArgs: [
          widget.entryId,
          resolved['scan_reference_mode'],
          resolved['scan_value'],
          widget.warehouse,
        ],
      );

      if (existingEntries.isNotEmpty) {
        final existingSyncUuid =
            (existingEntries.first['sync_uuid'] ?? '').toString().trim();
        final updateData = <String, Object?>{
          'scan_reference_mode': resolved['scan_reference_mode'],
          'scan_value': resolved['scan_value'],
          'item_barcode': resolved['item_barcode'],
          'item_code': resolved['item_code'],
          'batch_no': resolved['batch_no'],
          'serial_no': resolved['serial_no'],
          'qty': quantity,
          'synced': 0,
        };
        if (existingSyncUuid.isEmpty) {
          updateData['sync_uuid'] = SyncManager.generateSyncUuid();
        }

        await widget.database!.update(
          'StockCountEntryItem',
          updateData,
          where:
              'stock_count_entry_id = ? AND scan_reference_mode = ? AND scan_value = ? AND warehouse = ?',
          whereArgs: [
            widget.entryId,
            resolved['scan_reference_mode'],
            resolved['scan_value'],
            widget.warehouse,
          ],
        );
      } else {
        await widget.database!.insert('StockCountEntryItem', {
          'stock_count_entry_id': widget.entryId,
          'sync_uuid': SyncManager.generateSyncUuid(),
          'scan_reference_mode': resolved['scan_reference_mode'],
          'scan_value': resolved['scan_value'],
          'item_barcode': resolved['item_barcode'],
          'item_code': resolved['item_code'],
          'batch_no': resolved['batch_no'],
          'serial_no': resolved['serial_no'],
          'warehouse': widget.warehouse,
          'qty': quantity,
          'synced': 0
        });
      }

      await widget.database!.update(
        'StockCountEntry',
        {'synced': 0},
        where: 'id = ?',
        whereArgs: [widget.entryId],
      );

      stockTakeNotifier.setScannedData('');
      if (mounted) {
        setState(() {
          qtyController.text = '0';
          scannedCodeController.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StockTakeNotifier>(
      builder: (context, stockTakeNotifier, child) {
        return Column(
          children: [
            if (stockTakeNotifier.countType == 'Beam')
              Expanded(
                flex: 3,
                child: _buildScannedCodeDisplay(
                  stockTakeNotifier.scannedData,
                  stockTakeNotifier.scanReferenceMode,
                ),
              ),
            if (stockTakeNotifier.countType == 'Camera')
              Expanded(
                flex: 3,
                child: _buildCameraView(
                  stockTakeNotifier.scannedData,
                  stockTakeNotifier.scanReferenceMode,
                ),
              ),
            Expanded(
              flex: 6,
              child: buildForm(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScannedCodeDisplay(
      String scannedData, String scanReferenceMode) {
    final modeLabel = scanReferenceMode.isEmpty ? 'Blank' : scanReferenceMode;
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _animation,
              child: Icon(Icons.qr_code_scanner,
                  size: 48, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(height: 20),
            Text(
              '[$modeLabel] Scanned Code: $scannedData',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView(String scannedData, String scanReferenceMode) {
    final modeLabel = scanReferenceMode.isEmpty ? 'Blank' : scanReferenceMode;
    return Container(
      height: 250, // Set a fixed height for the camera view
      child: Stack(
        children: [
          MobileScanner(
            controller: scannerController,
            onDetect: (BarcodeCapture capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && mounted) {
                final String code = barcodes.first.rawValue ?? '';
                Provider.of<StockTakeNotifier>(context, listen: false)
                    .setScannedData(code);
                print("Scanned QR/Barcode: $code");
              }
            },
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Consumer<StockTakeNotifier>(
                    builder: (context, stockTakeNotifier, child) {
                      return Container(
                        color: Colors.white.withAlpha(128),
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '[$modeLabel] Scanned Data: $scannedData',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.black,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildForm() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextFormField(
            controller: scannedCodeController,
            decoration: InputDecoration(
              labelText: 'Scanned Code',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              prefixIcon: const Icon(Icons.qr_code),
            ),
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: qtyController,
            decoration: InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              prefixIcon: const Icon(Icons.numbers),
            ),
            keyboardType: TextInputType.number,
          ),
          const Spacer(),
          InkWell(
            onTap: submitEntry,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: screenBgColor,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(17.0),
              child: const Text(
                "Submit Entry",
                style: semibold16Black33,
              ),
            ),
          )
        ],
      ),
    );
  }
}
