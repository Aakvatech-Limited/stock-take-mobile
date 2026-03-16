import 'package:sqflite/sqflite.dart';

class DBSchema {
  static const int dbVersion = 2;

  // Function to initialize the database
  static Future<void> initDB(Database db, int version) async {
    // Creating the StockCountEntry table with sync-related columns
    await db.execute('''
      CREATE TABLE StockCountEntry (
        id INTEGER PRIMARY KEY AUTOINCREMENT, -- Local unique ID
        server_id TEXT, -- The ID from the Frappe server, to sync data
        company TEXT NOT NULL,
        warehouse TEXT NOT NULL,
        posting_date TEXT NOT NULL,
        posting_time TEXT NOT NULL,
        scan_reference_mode TEXT DEFAULT '',
        stock_count_person TEXT NOT NULL,
        synced INTEGER DEFAULT 0, -- Whether entry has been synced (0: no, 1: yes)
        last_sync_time TEXT -- Timestamp of the last sync
      );
    ''');

    // Creating the StockCountEntryItem table with sync-related columns
    await db.execute('''
      CREATE TABLE StockCountEntryItem (
        id INTEGER PRIMARY KEY AUTOINCREMENT, -- Local unique ID
        stock_count_entry_id INTEGER NOT NULL, -- Local FK to StockCountEntry
        server_id TEXT, -- The ID from the Frappe server for each item
        item_barcode TEXT NOT NULL,
        warehouse TEXT NOT NULL,
        qty INTEGER NOT NULL,
        synced INTEGER DEFAULT 0, -- Whether item has been synced (0: no, 1: yes)
        last_sync_time TEXT, -- Timestamp of the last sync
        FOREIGN KEY(stock_count_entry_id) REFERENCES StockCountEntry(id) ON DELETE CASCADE
      );
    ''');
  }

  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _addColumnIfMissing(
        db,
        tableName: 'StockCountEntry',
        columnName: 'scan_reference_mode',
        columnTypeSql: "TEXT DEFAULT ''",
      );
    }
  }

  static Future<void> _addColumnIfMissing(
    Database db, {
    required String tableName,
    required String columnName,
    required String columnTypeSql,
  }) async {
    final columns = await db.rawQuery("PRAGMA table_info($tableName)");
    final hasColumn = columns.any((column) => column['name'] == columnName);
    if (hasColumn) return;

    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $columnTypeSql',
    );
  }
}
