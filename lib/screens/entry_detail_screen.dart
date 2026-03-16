import 'package:flutter/material.dart';
import 'package:stock_count/constants/theme.dart';
import 'package:sqflite/sqflite.dart';

class EntryDetailsScreen extends StatefulWidget {
  final int entryId;
  final String warehouse;
  final Database? database;

  const EntryDetailsScreen({
    Key? key,
    required this.entryId,
    required this.warehouse,
    required this.database,
  }) : super(key: key);

  @override
  State<EntryDetailsScreen> createState() => _EntryDetailsScreenState();
}

class _EntryDetailsScreenState extends State<EntryDetailsScreen> {
  List<Map<String, dynamic>> scannedItems = [];
  Map<String, dynamic>? entryDetails;

  @override
  void initState() {
    super.initState();
    fetchEntryDetails();
    fetchScannedItems();
  }

  // Fetch entry details (company, warehouse, posting_date, posting_time)
  Future<void> fetchEntryDetails() async {
    try {
      final List<Map<String, dynamic>> result = await widget.database!.query(
        'StockCountEntry',
        where: 'id = ?',
        whereArgs: [widget.entryId],
      );
      if (result.isNotEmpty) {
        setState(() {
          entryDetails = result.first;
        });
      }
    } catch (e) {
      print("Error fetching entry details: $e");
    }
  }

  // Fetch scanned items for the entry
  Future<void> fetchScannedItems() async {
    try {
      final List<Map<String, dynamic>> result = await widget.database!.query(
        'StockCountEntryItem',
        where: 'stock_count_entry_id = ?',
        whereArgs: [widget.entryId],
      );
      setState(() {
        scannedItems = result;
      });
    } catch (e) {
      print("Error fetching scanned items: $e");
    }
  }

  Widget buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: medium14Grey,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: const Color(0xFFE8E8E8),
                borderRadius: BorderRadius.circular(5.0),
              ),
              child: Text(
                value,
                style: semibold14Black33,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          entryDetails != null && entryDetails!['server_id'] != null
              ? entryDetails!['server_id'] // Show server_id if exists
              : 'Entry: ${widget.entryId}', // Fallback to entryId
          style: const TextStyle(color: Color.fromRGBO(255, 255, 255, 1)),
        ),
        backgroundColor: primaryColor,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color.fromRGBO(255, 255, 255, 1),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          double totalWidth = constraints.maxWidth -
              32; // Keeping consistent padding of 16 from left and right
          double column1Width = totalWidth * 0.15; // 15% for No.
          double column2Width = totalWidth * 0.55; // 55% for Item Scanned Code
          double column3Width = totalWidth * 0.30; // 30% for Qty

          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16.0), // Consistent padding
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20), // Add vertical spacing here
                if (entryDetails != null) ...[
                  buildDetailRow('Company:', entryDetails!['company']),
                  buildDetailRow('Date:', entryDetails!['posting_date']),
                  buildDetailRow('Time:', entryDetails!['posting_time']),
                  buildDetailRow('Warehouse:', entryDetails!['warehouse']),
                  buildDetailRow(
                    'Reference Mode:',
                    (entryDetails!['scan_reference_mode'] ?? '')
                            .toString()
                            .isEmpty
                        ? 'Blank'
                        : entryDetails!['scan_reference_mode'].toString(),
                  ),
                  const SizedBox(height: 20),
                ],

                const Text(
                  'Scanned Items:',
                  style: semibold16Black33,
                ),
                const SizedBox(height: 10),

                scannedItems.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'No scanned items found for this entry.',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      )
                    : Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: Table(
                            columnWidths: {
                              0: FixedColumnWidth(column1Width),
                              1: FixedColumnWidth(column2Width),
                              2: FixedColumnWidth(column3Width),
                            },
                            border: TableBorder.all(
                                color: Colors.grey.withValues(alpha: 0.5),
                                style: BorderStyle.solid,
                                width: 1),
                            children: [
                              const TableRow(
                                decoration: BoxDecoration(
                                    color:
                                        Color(0xFFE8E8E8)), // Header background
                                children: [
                                  TableCell(
                                    child: Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text('No.',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  TableCell(
                                    child: Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text('Item Scanned Code',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  TableCell(
                                    child: Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text('Qty',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                              ...scannedItems.asMap().entries.map((entry) {
                                final index = entry.key;
                                final item = entry.value;
                                return TableRow(
                                  children: [
                                    TableCell(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text('${index + 1}',
                                            style: medium14Black33),
                                      ),
                                    ),
                                    TableCell(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(item['item_barcode'],
                                            style: medium14Black33),
                                      ),
                                    ),
                                    TableCell(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text('${item['qty']}',
                                            style: medium14Black33),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }
}
