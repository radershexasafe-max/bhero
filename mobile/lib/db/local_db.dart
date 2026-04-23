import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';

class LocalDb {
  static final LocalDb instance = LocalDb._();
  LocalDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'retail_suite.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_sales(
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_products(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            barcode TEXT NULL,
            sell_price REAL NOT NULL,
            cost_price REAL NOT NULL,
            reorder_level INTEGER NOT NULL
          )
        ''');
        await _createIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createIndexes(db);
        }
      },
    );
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_sales_created_at ON offline_sales(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cached_products_name ON cached_products(name COLLATE NOCASE)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cached_products_barcode ON cached_products(barcode)');
  }

  Future<void> cacheProducts(List<Product> products) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('cached_products');
    for (final p in products) {
      batch.insert('cached_products', p.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Product>> searchCachedProducts(String query) async {
    final d = await db;
    final q = query.trim();
    if (q.isEmpty) return [];
    final prefixRows = await d.query(
      'cached_products',
      where: 'name LIKE ? OR barcode LIKE ?',
      whereArgs: ['$q%', '$q%'],
      orderBy: 'name',
      limit: 25,
    );
    if (prefixRows.length >= 25) {
      return prefixRows.map(Product.fromDb).toList();
    }

    final seenIds = prefixRows.map((row) => row['id']).toSet();
    final containsRows = await d.query(
      'cached_products',
      where: '(name LIKE ? OR barcode LIKE ?) AND id NOT IN (${seenIds.isEmpty ? '0' : List.filled(seenIds.length, '?').join(',')})',
      whereArgs: ['%$q%', '%$q%', ...seenIds],
      orderBy: 'name',
      limit: 25 - prefixRows.length,
    );
    return [...prefixRows, ...containsRows].map(Product.fromDb).toList();
  }

  Future<List<Product>> getCachedProducts({int limit = 30}) async {
    final d = await db;
    final rows = await d.query(
      'cached_products',
      orderBy: 'name',
      limit: limit,
    );
    return rows.map(Product.fromDb).toList();
  }

  Future<Product?> getCachedByBarcode(String barcode) async {
    final d = await db;
    final rows = await d.query('cached_products', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    if (rows.isEmpty) return null;
    return Product.fromDb(rows.first);
  }

  Future<void> enqueueSale(String id, Map<String, dynamic> payload) async {
    final d = await db;
    await d.insert('offline_sales', {
      'id': id,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<({String id, Map<String, dynamic> payload, String createdAt})>> getQueuedSales() async {
    final d = await db;
    final rows = await d.query('offline_sales', orderBy: 'created_at ASC');
    return rows.map((r) {
      return (
        id: r['id'] as String,
        payload: jsonDecode(r['payload'] as String) as Map<String, dynamic>,
        createdAt: r['created_at'] as String,
      );
    }).toList();
  }

  Future<void> deleteQueuedSale(String id) async {
    final d = await db;
    await d.delete('offline_sales', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> queuedCount() async {
    final d = await db;
    final r = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM offline_sales'));
    return r ?? 0;
  }
}
