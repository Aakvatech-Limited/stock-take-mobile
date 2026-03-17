import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:hive/hive.dart';
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
  String displayText = '0';

  bool isCameraInitialized = false;

  late AnimationController _animationController;
  late Animation<double> _animation;

  // Track which field is active for editing
  String activeField = 'value'; // Options: 'value' or 'scannedCode'

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
        if (mounted) {
          fetchExistingEntry();
        }
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
      displayText = existingEntry.isNotEmpty
          ? existingEntry.first['qty'].toString()
          : '0';
    });
  }

  Future<Map<String, dynamic>?> _resolveScanReference(
      String scanValue, String scanReferenceMode) async {
    final normalizedMode = scanReferenceMode.trim();
    final authBox = await Hive.openBox('authBox');

    final rawAssignedItems = authBox.get('assigned_items');
    final assignedItemCodes = <String>{};
    if (rawAssignedItems != null) {
      try {
        final decoded = rawAssignedItems is String
            ? jsonDecode(rawAssignedItems)
            : rawAssignedItems;
        if (decoded is List) {
          for (final row in decoded.whereType<Map>()) {
            final itemCode = (row['item'] ?? '').toString().trim();
            if (itemCode.isNotEmpty) assignedItemCodes.add(itemCode);
          }
        }
      } catch (_) {}
    }

    final rawMasters = authBox.get('scan_reference_masters');
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

    // Blank mode keeps classic barcode flow, with assigned-item shortcut.
    final isAssignedItemCode = assignedItemCodes.contains(scanValue);
    return {
      'scan_reference_mode': '',
      'scan_value': scanValue,
      'item_barcode': isAssignedItemCode ? '' : scanValue,
      'item_code': isAssignedItemCode ? scanValue : '',
      'batch_no': '',
      'serial_no': '',
    };
  }

  void _onButtonPressed(String label) {
    final stockTakeNotifier =
        Provider.of<StockTakeNotifier>(context, listen: false);

    if (!mounted) return;

    setState(() {
      if (label == 'Clear') {
        if (activeField == 'value') {
          displayText = '0';
        } else if (activeField == 'scannedCode') {
          stockTakeNotifier.setScannedData('');
        }
      } else if (label == '<') {
        if (activeField == 'value') {
          if (displayText.length > 1) {
            displayText = displayText.substring(0, displayText.length - 1);
          } else {
            displayText = '0';
          }
        } else if (activeField == 'scannedCode') {
          String currentScannedData = stockTakeNotifier.scannedData;
          if (currentScannedData.isNotEmpty) {
            stockTakeNotifier.setScannedData(
                currentScannedData.substring(0, currentScannedData.length - 1));
          }
        }
      } else {
        if (activeField == 'value') {
          if (displayText == '0') {
            displayText = label;
          } else {
            displayText += label;
          }
        } else if (activeField == 'scannedCode') {
          String currentScannedData = stockTakeNotifier.scannedData;
          if (currentScannedData == '0') {
            stockTakeNotifier.setScannedData(label);
          } else {
            stockTakeNotifier.setScannedData(currentScannedData + label);
          }
        }
      }
    });
  }

  void submitEntry() async {
    if (!mounted) return;

    final stockTakeNotifier =
        Provider.of<StockTakeNotifier>(context, listen: false);
    final scanValue = stockTakeNotifier.scannedData.trim();
    final scanReferenceMode = stockTakeNotifier.scanReferenceMode.trim();
    int quantity = int.tryParse(displayText) ?? 0;

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
          displayText = '0';
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
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      activeField = 'scannedCode';
                    });
                  },
                  child: _buildScannedCodeDisplay(
                    stockTakeNotifier.scannedData,
                    stockTakeNotifier.scanReferenceMode,
                  ),
                ),
              ),
            if (stockTakeNotifier.countType == 'Camera')
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      activeField = 'scannedCode';
                    });
                  },
                  child: _buildCameraView(
                    stockTakeNotifier.scannedData,
                    stockTakeNotifier.scanReferenceMode,
                  ),
                ),
              ),
            Expanded(
              flex: 6,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    activeField = 'value';
                  });
                },
                child: buildCalculator(),
              ),
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
            GestureDetector(
              onTap: () {
                setState(() {
                  activeField = 'scannedCode';
                });
              },
              child: Text(
                '[$modeLabel] Scanned Code: $scannedData',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: activeField == 'scannedCode'
                      ? Colors.blue
                      : Colors.black54,
                ),
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
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            activeField = 'scannedCode';
                          });
                        },
                        child: Container(
                          color: Colors.white.withAlpha(128),
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '[$modeLabel] Scanned Data: $scannedData',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: activeField == 'scannedCode'
                                  ? Colors.blue
                                  : Colors.black,
                            ),
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

  Widget buildCalculator() {
    return Container(
      padding: const EdgeInsets.all(8.0),
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
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  activeField = 'value';
                });
              },
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 24.0,
                  fontWeight: FontWeight.bold,
                  color: activeField == 'value' ? Colors.blue : Colors.black,
                ),
              ),
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: List.generate(12, (index) {
                List<String> buttons = [
                  '1',
                  '2',
                  '3',
                  '4',
                  '5',
                  '6',
                  '7',
                  '8',
                  '9',
                  'Clear',
                  '0',
                  '<'
                ];
                return CalculatorButton(
                  label: buttons[index],
                  onTap: () => _onButtonPressed(buttons[index]),
                );
              }),
            ),
          ),
          InkWell(
            onTap: submitEntry,
            child: Container(
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

class CalculatorButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const CalculatorButton({
    Key? key,
    required this.label,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: screenBgColor,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8.0),
        child: Text(
          label,
          style: semibold16Black33,
        ),
      ),
    );
  }
}
