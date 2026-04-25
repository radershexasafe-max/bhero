import '../api/api_client.dart';
import '../db/local_db.dart';

class SyncService {
  static DateTime? _lastProductSyncAt;

  static Future<({int synced, int remaining})> syncQueuedSales(ApiClient api) async {
    final db = LocalDb.instance;
    final queued = await db.getQueuedSales();
    var synced = 0;
    for (final q in queued) {
      try {
        await api.createSale(q.payload);
        await db.deleteQueuedSale(q.id);
        synced++;
      } catch (_) {
        // Stop early? We continue so we can sync others if only one is failing.
        // However, to avoid server overload, we keep going.
      }
    }
    final remaining = await db.queuedCount();
    return (synced: synced, remaining: remaining);
  }

  static Future<int> syncProductCache(
    ApiClient api, {
    Duration minInterval = const Duration(minutes: 15),
  }) async {
    final last = _lastProductSyncAt;
    final now = DateTime.now();
    if (last != null && now.difference(last) < minInterval) {
      return 0;
    }
    final products = await api.getProducts(all: true, limit: 5000);
    await LocalDb.instance.cacheProducts(products);
    _lastProductSyncAt = now;
    return products.length;
  }
}
