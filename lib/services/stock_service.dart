import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/m.dart';
import '../data/providers.dart';

class StockService {
  static Future<void> deductCart({
    required WidgetRef ref,
    required List<CartItem> cart,
    required String shopId,
    required String payment,
    String by = 'POS',
  }) async {
    if (cart.isEmpty) return;
    final db = FirebaseDatabase.instance;
    final batch = <String, dynamic>{};
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();

    final products = ref.read(productsProvider);

    for (final item in cart) {
      final latest = products.firstWhere(
        (p) => p.productId == item.product.productId,
        orElse: () => item.product,
      );
      final newQty = (latest.stockQty - item.qty).clamp(0, 99999);

      batch['products/${latest.productId}/stockQty'] = newQty;
      batch['products/${latest.productId}/updatedAt'] = nowIso;

      final txId = 'tx_${nowMs}_${latest.productId}';
      batch['transactions/$txId'] = {
        'shopId': shopId,
        'productId': latest.productId,
        'productName': latest.productName,
        'qty': item.qty,
        'price': latest.sellingPrice,
        'cost': latest.costPrice,
        'total': latest.sellingPrice * item.qty,
        'type': 'sale',
        'payment': payment,
        'time': nowMs,
        'by': by,
      };

      final histId = 'h_${nowMs}_${latest.productId}';
      batch['stock_history/$histId'] = {
        'shopId': shopId,
        'productId': latest.productId,
        'productName': latest.productName,
        'oldQty': latest.stockQty,
        'newQty': newQty,
        'delta': -item.qty,
        'type': 'sale',
        'time': nowMs,
        'by': by,
      };
    }

    try {
      await db.ref().update(batch);
      for (final item in cart) {
        ref.read(productsProvider.notifier).adjustQty(item.product.productId, -item.qty);
      }
    } catch (e) {
      debugPrint('StockService.deductCart error: $e');
      rethrow;
    }
  }
}
