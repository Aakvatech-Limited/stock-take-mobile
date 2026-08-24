import 'dart:async'; // For Timer
import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/uil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stock_count/constants/theme.dart';
import 'package:stock_count/screens/entry_detail_screen.dart';
import 'package:stock_count/screens/home.dart';
import 'package:stock_count/utilis/dialog_messages.dart';
import 'package:provider/provider.dart';
import 'package:stock_count/utilis/change_notifier.dart';

class CenterBox extends StatefulWidget {
  final Database? database;

  const CenterBox({Key? key, required this.database}) : super(key: key);

  @override
  _CenterBoxState createState() => _CenterBoxState();
}

class _CenterBoxState extends State<CenterBox> {
  List<Map<String, dynamic>> entries = [];
  Timer? _timer; // Declare a Timer

  @override
  void initState() {
    super.initState();
    fetchEntries(); // Fetch initial entries
    startAutoRefresh(); // Start auto-refresh
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel the timer when the widget is disposed
    super.dispose();
  }

  // Function to start auto-refresh every 5 seconds
  void startAutoRefresh() {
    _timer = Timer.periodic(Duration(seconds: 5), (timer) {
      fetchEntries(); // Fetch entries every 5 seconds
    });
  }

  Future<void> fetchEntries() async {
    if (widget.database != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        String? userDetailsJson = prefs.getString('userDetails');
        String? stockCountPersonId = prefs.getString('userId');

        if (userDetailsJson != null && stockCountPersonId != null) {
          // Updated query to fetch 'server_id'
          String query = '''
            SELECT 
              s.id, 
              s.server_id,  -- Fetch server_id
              s.warehouse, 
              s.posting_date, 
              s.posting_time, 
              s.scan_reference_mode,
              s.synced, 
              COUNT(i.id) AS item_count
            FROM StockCountEntry AS s
            LEFT JOIN StockCountEntryItem AS i ON s.id = i.stock_count_entry_id
            WHERE s.stock_count_person = ?
            GROUP BY s.id
            ORDER BY s.id DESC
          ''';
          final List<Map<String, dynamic>> result =
              await widget.database!.rawQuery(query, [stockCountPersonId]);
          setState(() {
            entries = result;
          });
        }
      } catch (e) {
        print("Error fetching entries: $e");
      }
    }
  }

  void startRecount(int entryId, String warehouse, String countType,
      String scanReferenceMode) {
    if (countType == 'Count type') {
      showErrorDialog(context, "Please select the Count type first.");
      return;
    }
    widget.database!.query('StockCountEntry',
        where: 'id = ?', whereArgs: [entryId]).then((result) {
      if (result.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
                recountEntryId: entryId,
                recountWarehouse: warehouse,
                countType: countType,
                scanReferenceMode: scanReferenceMode,
                database: widget.database),
          ),
        );
      }
    });
  }

  void startEntryDetails(int entryId, String warehouse) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EntryDetailsScreen(
          entryId: entryId,
          warehouse: warehouse,
          database: widget.database,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StockTakeNotifier>(
      builder: (context, stockTakeNotifier, child) {
        String countType = stockTakeNotifier.countType;
        String scanReferenceMode = stockTakeNotifier.scanReferenceMode;
        return Center(
          child: Container(
            width: double.maxFinite,
            padding: const EdgeInsets.symmetric(
                horizontal: fixPadding * 1.4, vertical: fixPadding * 3.5),
            margin: const EdgeInsets.symmetric(horizontal: 5),
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      "No entries available",
                      style: medium15Grey,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      // Use 'server_id' if it exists, otherwise use 'id'
                      String displayId = entries[index]['server_id'] ??
                          'Entry ${entries[index]['id']}';
                      return Column(
                        children: [
                          optionWidget(
                            () {
                              // Open the entry details when the card is tapped
                              startEntryDetails(entries[index]['id'],
                                  entries[index]['warehouse']);
                            },
                            "$displayId - ${entries[index]['warehouse']}",
                            "Items : ${entries[index]['item_count']} | ${entries[index]['posting_date']} | ${entries[index]['posting_time']}",
                            () {
                              // Start recount when the refresh icon is tapped
                              startRecount(
                                entries[index]['id'],
                                entries[index]['warehouse'],
                                countType,
                                (entries[index]['scan_reference_mode'] ??
                                        scanReferenceMode)
                                    .toString(),
                              );
                            },
                            entries[index]['synced'] == 0
                                ? whiteColor
                                : const Color.fromARGB(255, 176, 247, 202),
                          ),
                          const SizedBox(height: 10),
                        ],
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

Widget optionWidget(VoidCallback onTap, String title, String subTitle,
    VoidCallback onRefreshTap, Color circleColor) {
  return GestureDetector(
    onTap: onTap, // This handles the card tap for viewing entry details
    child: Container(
      width: double.maxFinite,
      padding: const EdgeInsets.symmetric(
          horizontal: fixPadding, vertical: fixPadding * 1.6),
      decoration: BoxDecoration(
        color: whiteColor,
        borderRadius: BorderRadius.circular(10.0),
        boxShadow: [
          BoxShadow(
            color: blackColor.withValues(alpha: 0.1),
            blurRadius: 6.0,
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onRefreshTap, // This handles the tap for the refresh icon
            child: Container(
              height: 40.0,
              width: 40.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: circleColor,
                boxShadow: [
                  BoxShadow(
                    color: blackColor.withValues(alpha: 0.15),
                    blurRadius: 6.0,
                  )
                ],
              ),
              alignment: Alignment.center,
              child: const Iconify(Uil.refresh),
            ),
          ),
          const SizedBox(width: fixPadding),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: semibold16Black33,
                ),
                const SizedBox(height: 5),
                Text(
                  subTitle,
                  style: medium14Grey,
                )
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Icon(
              Icons.arrow_forward_ios,
              color: Colors.black,
              size: 20.0,
            ),
          ),
        ],
      ),
    ),
  );
}
