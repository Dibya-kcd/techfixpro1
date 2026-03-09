import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import '../models/m.dart';
import '../data/providers.dart';
import '../data/active_session.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InvState();
}

class _InvState extends ConsumerState<InventoryScreen> {
  String? _cat;
  bool _synced = false;
  bool _syncing = false;

  Future<void> _syncProductsFromFirebase(String shopId) async {
    try {
      final db = FirebaseDatabase.instance;
      final snap = await db.ref('products')
          .orderByChild('shopId')
          .equalTo(shopId)
          .get();
      final list = <Product>[];
      if (snap.exists && snap.children.isNotEmpty) {
        for (final child in snap.children) {
          final key = child.key;
          final value = child.value;
          if (key == null || value is! Map) continue;
          final data = Map<String, dynamic>.from(value);
          list.add(Product(
            productId: key,
            shopId: (data['shopId'] as String?) ?? shopId,
            sku: (data['sku'] as String?) ?? '',
            productName: (data['productName'] as String?) ?? (data['name'] as String?) ?? '',
            category: (data['category'] as String?) ?? (data['cat'] as String?) ?? 'Spare Parts',
            brand: (data['brand'] as String?) ?? '',
            description: (data['description'] as String?) ?? '',
            supplierName: (data['supplierName'] as String?) ?? (data['supplier'] as String?) ?? '',
            costPrice: (data['costPrice'] as num?)?.toDouble() ?? (data['cost'] as num?)?.toDouble() ?? 0,
            sellingPrice: (data['sellingPrice'] as num?)?.toDouble() ?? (data['price'] as num?)?.toDouble() ?? 0,
            stockQty: (data['stockQty'] as int?) ?? (data['qty'] as int?) ?? 0,
            reorderLevel: (data['reorderLevel'] as int?) ?? (data['reorder'] as int?) ?? 5,
            isActive: (data['isActive'] as bool?) ?? true,
            imageUrl: (data['imageUrl'] as String?) ?? '',
            createdAt: (data['createdAt'] as String?) ?? '',
            updatedAt: (data['updatedAt'] as String?) ?? '',
          ));
        }
      }
      ref.read(productsProvider.notifier).setAll(list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final search = ref.watch(searchInvProvider);
    final sessionAsync = ref.watch(currentUserProvider);
    final session = sessionAsync.asData?.value;
    final activeSession = ref.watch(activeSessionProvider);
    final resolvedShopId = activeSession?.shopId.isNotEmpty == true
        ? activeSession!.shopId : (session?.shopId ?? '');
    if (!_synced && !_syncing && resolvedShopId.isNotEmpty) {
      _syncing = true;
      _syncProductsFromFirebase(resolvedShopId).whenComplete(() {
        if (mounted) {
          setState(() {
            _synced = true;
            _syncing = false;
          });
        }
      });
    }
    final cats = ['All', ...{...products.map((p) => p.category)}];
    final totalVal = products.fold(0.0, (s, p) => s + p.costPrice * p.stockQty);

    final filtered = products.where((p) {
      final s = search.toLowerCase();
      final ms = s.isEmpty || p.productName.toLowerCase().contains(s)
          || p.sku.toLowerCase().contains(s) || p.brand.toLowerCase().contains(s);
      final mc = _cat == null || _cat == 'All' || p.category == _cat;
      return ms && mc;
    }).toList();

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(children: [
        // Header
        Container(
          color: C.bgElevated,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            // Stats strip
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('${products.length} SKUs', C.primary),
                const SizedBox(width: 8),
                _chip('₹${(totalVal / 1000).toStringAsFixed(0)}k Value', C.green),
                const SizedBox(width: 8),
                if (products.any((p) => p.isLowStock))
                  _chip('${products.where((p) => p.isLowStock).length} Low Stock', C.yellow),
                const SizedBox(width: 8),
                if (products.any((p) => p.isOutOfStock))
                  _chip('${products.where((p) => p.isOutOfStock).length} Out of Stock', C.red),
              ]),
            ),
            const SizedBox(height: 10),
            // Search
            TextField(
              onChanged: (v) => ref.read(searchInvProvider.notifier).state = v,
              style: GoogleFonts.syne(fontSize: 13, color: C.text),
              decoration: const InputDecoration(
                hintText: 'Search name, SKU, brand...',
                prefixIcon: Icon(Icons.search, color: C.textMuted, size: 20),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            // Category filters
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: cats.map((cat) {
                final sel = (_cat == null && cat == 'All') || _cat == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _cat = cat == 'All' ? null : cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? C.primary.withValues(alpha: 0.18) : C.bgCard,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: sel ? C.primary : C.border),
                      ),
                      child: Text(cat, style: GoogleFonts.syne(fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: sel ? C.primary : C.textMuted)),
                    ),
                  ),
                );
              }).toList()),
            ),
          ]),
        ),

        Expanded(
          child: filtered.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('📦', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text('No products found', style: GoogleFonts.syne(
                      fontSize: 16, fontWeight: FontWeight.w700, color: C.textMuted)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final p = filtered[i];
                    final sc = p.isOutOfStock ? C.red : p.isLowStock ? C.yellow : C.green;
                    final catIcon = p.category == 'Mobile Phones' ? '📱'
                        : p.category == 'Spare Parts' ? '🔩' : '🔌';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SCard(
                        onLongPress: () => _showStockHistory(context, p),
                        onTap: () => _openProductForm(context, p),
                        borderColor: p.isOutOfStock
                            ? C.red.withValues(alpha: 0.3)
                            : p.isLowStock
                                ? C.yellow.withValues(alpha: 0.3)
                                : null,
                        child: Row(children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                                color: C.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12)),
                            child: Center(child: Text(catIcon,
                                style: const TextStyle(fontSize: 22))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.productName, style: GoogleFonts.syne(
                                fontWeight: FontWeight.w700, fontSize: 13, color: C.white),
                                overflow: TextOverflow.ellipsis),
                            Text('${p.sku}${p.brand.isNotEmpty ? " · ${p.brand}" : ""}',
                                style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(fmtMoney(p.sellingPrice), style: GoogleFonts.syne(
                                  fontWeight: FontWeight.w800, fontSize: 14, color: C.primary)),
                              const SizedBox(width: 8),
                              Text('Cost: ${fmtMoney(p.costPrice)}', style: GoogleFonts.syne(
                                  fontSize: 11, color: C.textMuted)),
                            ]),
                          ])),
                          const SizedBox(width: 10),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: sc.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(p.isOutOfStock ? 'OUT' : '${p.stockQty} pcs',
                                  style: GoogleFonts.syne(fontSize: 12,
                                      fontWeight: FontWeight.w700, color: sc)),
                            ),
                            const SizedBox(height: 4),
                            Text('Min: ${p.reorderLevel}', style: GoogleFonts.syne(
                                fontSize: 10, color: C.textMuted)),
                            const SizedBox(height: 4),
                            // Quick stock adjust
                            Row(children: [
                              _qtyBtn(Icons.remove, () => _adjustQty(p, -1)),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('${p.stockQty}', style: GoogleFonts.syne(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: C.white))),
                              _qtyBtn(Icons.add, () => _adjustQty(p, 1)),
                            ]),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Scan to add
          FloatingActionButton(
            heroTag: 'fab_scan',
            onPressed: () => _scanToAdd(context),
            backgroundColor: C.bgElevated,
            foregroundColor: C.primary,
            mini: true,
            tooltip: 'Scan barcode to add/update',
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 10),
          // Manual add
          FloatingActionButton.extended(
            heroTag: 'fab_inventory',
            onPressed: () => _openProductForm(context, null),
            backgroundColor: C.primary,
            foregroundColor: C.bg,
            icon: const Icon(Icons.add),
            label: Text('Add Product',
                style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Text(label, style: GoogleFonts.syne(
        fontSize: 12, fontWeight: FontWeight.w700, color: color)),
  );

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 24, height: 24,
      decoration: BoxDecoration(border: Border.all(color: C.border),
          borderRadius: BorderRadius.circular(6), color: C.bgElevated),
      child: Icon(icon, size: 14, color: C.text),
    ),
  );

  void _openProductForm(BuildContext context, Product? p) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProductFormScreen(product: p)));

  /// Scan barcode from the inventory list screen.
  /// 1. Open scanner → get barcode + online product info
  /// 2. Check if SKU already exists in local provider
  ///    YES → show "Already in stock" sheet with +qty buttons
  ///    NO  → open ProductFormScreen pre-filled with all scan data
  Future<void> _scanToAdd(BuildContext context) async {
    final result = await Navigator.of(context).push<_ScanResult>(
      MaterialPageRoute(builder: (_) => const _BarcodeScannerScreen()),
    );
    if (result == null || !mounted) return;

    // Check for existing product with same SKU / barcode
    final products = ref.read(productsProvider);
    final existing = products.where(
      (p) => p.sku.trim().toLowerCase() == result.barcode.trim().toLowerCase(),
    ).firstOrNull;

    if (existing != null) {
      // Already in stock — show quick-restock sheet
      _showRestockSheet(context, existing, result);
    } else {
      // New product — open pre-filled form
      if (!context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProductFormScreen(scanResult: result),
      ));
    }
  }

  /// Quick-restock bottom sheet when scanned product already exists
  void _showRestockSheet(BuildContext ctx, Product p, _ScanResult scan) {
    int qty = 1;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: C.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: C.border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),

            // Product summary
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.inventory_2, color: C.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.productName, style: GoogleFonts.syne(
                    fontSize: 15, fontWeight: FontWeight.w800, color: C.white)),
                Text('${p.brand}  ·  SKU: ${p.sku}', style: GoogleFonts.syne(
                    fontSize: 12, color: C.textMuted)),
              ])),
            ]),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: C.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Already in stock', style: GoogleFonts.syne(
                    fontSize: 12, color: C.green)),
                Text('Current stock: ${p.stockQty} units', style: GoogleFonts.syne(
                    fontSize: 12, fontWeight: FontWeight.w700, color: C.green)),
              ]),
            ),
            const SizedBox(height: 20),

            // Quantity picker
            Text('Add quantity', style: GoogleFonts.syne(
                fontSize: 13, color: C.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _qtyBtn(Icons.remove, () {
                if (qty > 1) setSheet(() => qty--);
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('$qty', style: GoogleFonts.syne(
                    fontSize: 28, fontWeight: FontWeight.w800, color: C.white)),
              ),
              _qtyBtn(Icons.add, () => setSheet(() => qty++)),
            ]),
            const SizedBox(height: 8),
            // Quick presets
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final n in [5, 10, 25, 50])
                GestureDetector(
                  onTap: () => setSheet(() => qty = n),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: qty == n
                          ? C.primary.withValues(alpha: 0.2)
                          : C.bg.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: qty == n ? C.primary : C.border),
                    ),
                    child: Text('+$n', style: GoogleFonts.syne(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: qty == n ? C.primary : C.textMuted)),
                  ),
                ),
            ]),
            const SizedBox(height: 24),

            // Confirm button
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetCtx);
                  _adjustQty(p, qty);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        '✅ Added $qty to ${p.productName} — now ${p.stockQty + qty} in stock',
                        style: GoogleFonts.syne(fontWeight: FontWeight.w700),
                      ),
                      backgroundColor: C.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ));
                  }
                },
                icon: const Icon(Icons.add_circle, size: 18),
                label: Text('Add $qty to Stock',
                    style: GoogleFonts.syne(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.primary,
                  foregroundColor: C.bg,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Option to edit the product instead
            TextButton(
              onPressed: () {
                Navigator.pop(sheetCtx);
                _openProductForm(context, p);
              },
              child: Text('Edit product details instead',
                  style: GoogleFonts.syne(
                      fontSize: 13, color: C.textMuted)),
            ),
          ]),
        ),
      ),
    );
  }

  void _showStockHistory(BuildContext context, Product p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Stock History', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
                        Text(p.productName, style: GoogleFonts.syne(fontSize: 12, color: C.primary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: C.bgCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.border)),
                    child: Text('${p.stockQty} current', style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.w700, color: C.white)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<DatabaseEvent>(
                stream: FirebaseDatabase.instance.ref('stock_history')
                    .orderByChild('productId')
                    .equalTo(p.productId)
                    .onValue,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                    return Center(child: Text('No history found', style: GoogleFonts.syne(color: C.textMuted)));
                  }
                  
                  final data = snapshot.data!.snapshot.children.map((c) => Map<String, dynamic>.from(c.value as Map)).toList();
                  data.sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: data.length,
                    itemBuilder: (context, i) {
                      final h = data[i];
                      final delta = h['delta'] as int;
                      final type = h['type'] as String;
                      final date = DateTime.fromMillisecondsSinceEpoch(h['time'] as int);
                      final isPositive = delta > 0;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: C.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: (isPositive ? C.green : C.red).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isPositive ? Icons.add : Icons.remove,
                                size: 18, color: isPositive ? C.green : C.red,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    type.toUpperCase(),
                                    style: GoogleFonts.syne(fontSize: 10, fontWeight: FontWeight.w800, color: isPositive ? C.green : C.red, letterSpacing: 0.5),
                                  ),
                                  Text(
                                    'By ${h['by'] ?? "Unknown"}',
                                    style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.w600, color: C.white),
                                  ),
                                  Text(
                                    '${date.day}/${date.month} ${date.hour}:${date.minute}',
                                    style: GoogleFonts.syne(fontSize: 10, color: C.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${isPositive ? "+" : ""}$delta',
                                  style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.w800, color: isPositive ? C.green : C.red),
                                ),
                                Text(
                                  '${h['newQty']} total',
                                  style: GoogleFonts.syne(fontSize: 10, color: C.textMuted),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _adjustQty(Product p, int delta) async {
    final notifier = ref.read(productsProvider.notifier);
    notifier.adjustQty(p.productId, delta);
    try {
      final active = ref.read(activeSessionProvider);
      final stream = ref.read(currentUserProvider).asData?.value;
      final shopId  = (active?.shopId.isNotEmpty == true)
          ? active!.shopId : (stream?.shopId ?? '');
      final db = FirebaseDatabase.instance;
      final newQty = (p.stockQty + delta).clamp(0, 99999);
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final batch = <String, dynamic>{};
      batch['products/${p.productId}/stockQty'] = newQty;
      batch['products/${p.productId}/updatedAt'] = DateTime.now().toIso8601String();
      
      // Log stock history
      final histId = 'h_${now}_${p.productId}';
      
      // For simplicity, we'll just update the specific fields in the product node
      // and also keep the stock_history collection for the stream
      batch['stock_history/$histId'] = {
        'shopId': shopId,
        'productId': p.productId,
        'productName': p.productName,
        'oldQty': p.stockQty,
        'newQty': newQty,
        'delta': delta,
        'type': delta > 0 ? 'restock' : 'adjustment',
        'time': now,
        'by': active?.displayName ?? stream?.displayName ?? 'Admin',
      };
      
      await db.ref().update(batch);
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════
//  Product Add / Edit Form
// ═══════════════════════════════════════════════════════════════
class ProductFormScreen extends ConsumerStatefulWidget {
  final Product? product;
  final _ScanResult? scanResult; // pre-fill from barcode scan
  const ProductFormScreen({super.key, this.product, this.scanResult});
  @override
  ConsumerState<ProductFormScreen> createState() => _ProdFormState();
}

class _ProdFormState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name, _sku, _brand, _description, _supplier;
  late TextEditingController _cost, _price, _qty, _reorder;
  late String _cat;
  bool get _isEdit => widget.product != null;

  static const _cats = ['Spare Parts', 'Accessories', 'Mobile Phones', 'Tablets',
    'Wearables', 'Tools', 'Other'];

  @override
  void initState() {
    super.initState();
    final p    = widget.product;
    final scan = widget.scanResult;
    // When coming from a barcode scan (new product), scanResult takes priority.
    // When editing an existing product, widget.product takes priority.
    _name        = TextEditingController(text: p?.productName ?? scan?.name ?? '');
    _sku         = TextEditingController(text: p?.sku ?? scan?.barcode ?? '');
    _brand       = TextEditingController(text: p?.brand ?? scan?.brand ?? '');
    _description = TextEditingController(text: p?.description ?? scan?.description ?? '');
    _supplier    = TextEditingController(text: p?.supplierName ?? '');
    _cost        = TextEditingController(text: p?.costPrice.toStringAsFixed(0) ?? '');
    _price       = TextEditingController(text: p?.sellingPrice.toStringAsFixed(0) ?? '');
    _qty         = TextEditingController(text: p?.stockQty.toString() ?? '0');
    _reorder     = TextEditingController(text: p?.reorderLevel.toString() ?? '5');
    _cat         = p?.category ?? scan?.category ?? 'Spare Parts';
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _brand, _description, _supplier,
      _cost, _price, _qty, _reorder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.of(context).push<_ScanResult>(
      MaterialPageRoute(builder: (_) => const _BarcodeScannerScreen()),
    );
    if (result == null || !mounted) return;

    // Fill all known fields automatically
    setState(() {
      _sku.text = result.barcode;
      if (result.name.isNotEmpty  && _name.text.isEmpty)        _name.text        = result.name;
      if (result.brand.isNotEmpty && _brand.text.isEmpty)       _brand.text       = result.brand;
      if (result.description.isNotEmpty && _description.text.isEmpty) {
        _description.text = result.description;
      }
      if (result.category.isNotEmpty) _cat = result.category;
    });

    final filled = <String>['SKU'];
    if (result.name.isNotEmpty)        filled.add('Name');
    if (result.brand.isNotEmpty)       filled.add('Brand');
    if (result.description.isNotEmpty) filled.add('Description');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Text(result.name.isNotEmpty ? '✅ ' : '📦 ',
            style: const TextStyle(fontSize: 16)),
        Expanded(child: Text(
          result.name.isNotEmpty
              ? 'Auto-filled: ${filled.join(', ')}'
              : 'Barcode ${result.barcode} scanned — fill details manually',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        )),
      ]),
      backgroundColor: result.name.isNotEmpty ? C.green : C.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final notifier = ref.read(productsProvider.notifier);
    final existing = widget.product;
    final id = existing?.productId ?? 'p${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final shopId  = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');

    final product = (existing ??
        Product(
          productId: id,
          shopId: shopId,
          sku: '',
          productName: '',
          category: 'Spare Parts',
          costPrice: 0,
          sellingPrice: 0,
          stockQty: 0,
          reorderLevel: 5,
          createdAt: now,
          updatedAt: now,
        )).copyWith(
      productName: _name.text.trim(),
      sku: _sku.text.trim().isEmpty
          ? 'SKU-${DateTime.now().millisecond}'
          : _sku.text.trim(),
      brand: _brand.text.trim(),
      category: _cat,
      description: _description.text.trim(),
      supplierName: _supplier.text.trim(),
      costPrice: double.tryParse(_cost.text) ?? 0,
      sellingPrice: double.tryParse(_price.text) ?? 0,
      stockQty: int.tryParse(_qty.text) ?? 0,
      reorderLevel: int.tryParse(_reorder.text) ?? 5,
      updatedAt: now,
    );

    try {
      final db = FirebaseDatabase.instance;
      await db.ref('products/$id').set({
        'productId': product.productId,
        'shopId': product.shopId,
        'sku': product.sku,
        'productName': product.productName,
        'category': product.category,
        'brand': product.brand,
        'description': product.description,
        'supplierName': product.supplierName,
        'costPrice': product.costPrice,
        'sellingPrice': product.sellingPrice,
        'stockQty': product.stockQty,
        'reorderLevel': product.reorderLevel,
        'isActive': product.isActive,
        'imageUrl': product.imageUrl,
        'createdAt': product.createdAt,
        'updatedAt': product.updatedAt,
      });
      if (mounted) {
        nav.pop();
        messenger.showSnackBar(SnackBar(
          content: Text(_isEdit ? 'Product updated!' : 'Product added!',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.green, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (_isEdit) {
        notifier.update(product);
      } else {
        notifier.add(product);
      }
      if (mounted) {
        nav.pop();
      }
    }
  }

  void _confirmDelete() {
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Product?', style: GoogleFonts.syne(
            fontWeight: FontWeight.w800, color: C.white)),
        content: Text('Remove "${widget.product!.productName}" from inventory?',
            style: GoogleFonts.syne(fontSize: 13, color: C.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.syne(color: C.textMuted))),
          ElevatedButton(
            onPressed: () async {
            final id = widget.product!.productId;
            try {
              final db = FirebaseDatabase.instance;
              await db.ref('products/$id').remove();
            } catch (_) {}
            ref.read(productsProvider.notifier).delete(id);
             if (!context.mounted) return;
             Navigator.of(ctx).pop();
             nav.pop();
          },
            style: ElevatedButton.styleFrom(backgroundColor: C.red, foregroundColor: C.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Delete', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final margin = double.tryParse(_price.text) != null && double.tryParse(_cost.text) != null
        ? double.tryParse(_price.text)! - double.tryParse(_cost.text)!
        : 0.0;
    final marginPct = double.tryParse(_cost.text) != null && double.tryParse(_cost.text)! > 0
        ? (margin / double.tryParse(_cost.text)!) * 100
        : 0.0;

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Product' : 'New Product',
            style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('Save', style: GoogleFonts.syne(
                fontWeight: FontWeight.w800, fontSize: 15, color: C.primary)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const SLabel('PRODUCT INFO'),
            _field('Product Name', _name, required: true, hint: 'e.g. Samsung S24 OLED Screen'),
            Row(children: [
              Expanded(child: _field('SKU / Barcode', _sku, hint: 'SCR-SAM-S24', 
                  suffix: IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: C.primary),
                    onPressed: _scanBarcode,
                  ))),
              const SizedBox(width: 10),
              Expanded(child: _field('Brand', _brand, hint: 'Samsung, Apple...')),
            ]),

            // Category
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CATEGORY', style: GoogleFonts.syne(fontSize: 10,
                  fontWeight: FontWeight.w700, color: C.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                initialValue: _cat,
                dropdownColor: C.bgElevated,
                style: GoogleFonts.syne(fontSize: 13, color: C.text),
                decoration: const InputDecoration(),
                onChanged: (v) => setState(() => _cat = v ?? 'Spare Parts'),
                items: _cats.map((c) => DropdownMenuItem(value: c,
                    child: Text(c, style: GoogleFonts.syne(fontSize: 13)))).toList(),
              ),
              const SizedBox(height: 12),
            ]),
            _field('Description', _description, hint: 'Optional product description', maxLines: 2),
            _field('Supplier', _supplier, hint: 'iSpares, Suresh Electronics...'),

            const SLabel('PRICING & STOCK'),
            Row(children: [
              Expanded(child: _field('Cost Price', _cost, required: true,
                  prefix: '₹', type: TextInputType.number,
                  onChanged: (_) => setState(() {}))),
              const SizedBox(width: 10),
              Expanded(child: _field('Selling Price', _price, required: true,
                  prefix: '₹', type: TextInputType.number,
                  onChanged: (_) => setState(() {}))),
            ]),

            // Margin preview
            if (double.tryParse(_cost.text) != null && double.tryParse(_price.text) != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: margin >= 0
                      ? C.green.withValues(alpha: 0.08)
                      : C.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (margin >= 0 ? C.green : C.red).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Profit Margin', style: GoogleFonts.syne(
                      fontSize: 13, color: C.textMuted)),
                  Text('${fmtMoney(margin)} (${marginPct.toStringAsFixed(1)}%)',
                      style: GoogleFonts.syne(fontSize: 14, fontWeight: FontWeight.w800,
                          color: margin >= 0 ? C.green : C.red)),
                ]),
              ),

            Row(children: [
              Expanded(child: _field('Stock Qty', _qty, required: true,
                  type: TextInputType.number, prefix: '×')),
              const SizedBox(width: 10),
              Expanded(child: _field('Reorder Level', _reorder,
                  type: TextInputType.number, hint: 'Alert below this qty')),
            ]),

            // Stock status preview
            Builder(builder: (_) {
              final qty = int.tryParse(_qty.text) ?? 0;
              final reorder = int.tryParse(_reorder.text) ?? 5;
              final isOut = qty == 0;
              final isLow = qty > 0 && qty <= reorder;
              final color = isOut ? C.red : isLow ? C.yellow : C.green;
              final label = isOut ? '⚠️ Out of Stock' : isLow ? '⚠️ Low Stock — will trigger alert' : '✅ Adequate Stock';
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.3))),
                child: Text(label, style: GoogleFonts.syne(fontSize: 12, color: color)),
              );
            }),
            const SizedBox(height: 24),

            PBtn(label: _isEdit ? '💾 Update Product' : '➕ Add Product',
                onTap: _save, full: true, color: C.primary),
            if (_isEdit) ...[
              const SizedBox(height: 12),
              PBtn(label: '🗑️ Delete Product', onTap: _confirmDelete,
                  full: true, color: C.red, outline: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {
    String? hint, String? prefix, TextInputType? type, int maxLines = 1,
    bool required = false, ValueChanged<String>? onChanged, Widget? suffix,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: TextSpan(
          text: label.toUpperCase(),
          style: GoogleFonts.syne(fontSize: 10, fontWeight: FontWeight.w700,
              color: C.textMuted, letterSpacing: 0.5),
          children: required ? [TextSpan(text: ' *',
              style: GoogleFonts.syne(color: C.accent))] : [],
        )),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl, keyboardType: type, maxLines: maxLines,
          onChanged: (v) { onChanged?.call(v); setState(() {}); },
          style: GoogleFonts.syne(fontSize: 13, color: C.text),
          decoration: InputDecoration(
            hintText: hint, 
            prefixText: prefix,
            prefixStyle: GoogleFonts.syne(color: C.textMuted, fontSize: 13),
            suffixIcon: suffix,
          ),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        ),
        const SizedBox(height: 12),
      ]);
}


// ═══════════════════════════════════════════════════════════════
//  SCAN RESULT — flat model (no nested productInfo)
// ═══════════════════════════════════════════════════════════════
class _ScanResult {
  final String barcode;
  final String name;
  final String brand;
  final String description;
  final String category;
  const _ScanResult({
    required this.barcode,
    this.name = '', this.brand = '',
    this.description = '', this.category = '',
  });
}

// ═══════════════════════════════════════════════════════════════
//  BARCODE LOOKUP SERVICE
//
//  Fires go-upc.com AND UPC Item DB in PARALLEL (Future.wait).
//  Results are merged field-by-field — best data wins:
//    • go-upc  → strongest for electronics / phone parts / accessories
//    • UPC DB  → strongest for general retail, fills any gaps go-upc missed
//  Open Food Facts fires only if both primary sources return nothing.
// ═══════════════════════════════════════════════════════════════
class _BarcodeLookupService {
  static const _ua      = {'User-Agent': 'TechFixPro/3.0 (repair-shop-app)'};
  static const _timeout = Duration(seconds: 8);

  // ── Raw result holder from each source ──────────────────────
  static ({String name, String brand, String desc, String cat}) _empty() =>
      (name: '', brand: '', desc: '', cat: '');

  // ── go-upc.com ───────────────────────────────────────────────
  static Future<({String name, String brand, String desc, String cat})>
      _fetchGoUpc(String barcode) async {
    try {
      final r = await http
          .get(Uri.parse('https://go-upc.com/api/v1/code/$barcode'), headers: _ua)
          .timeout(_timeout);
      if (r.statusCode == 200) {
        final j    = jsonDecode(r.body) as Map<String, dynamic>;
        final prod = j['product'] as Map<String, dynamic>? ?? {};
        return (
          name:  (prod['name']        as String?) ?? '',
          brand: (prod['brand']       as String?) ?? '',
          desc:  (prod['description'] as String?) ?? '',
          cat:   (prod['category']    as String?) ?? '',
        );
      }
    } catch (_) {}
    return _empty();
  }

  // ── UPC Item DB ──────────────────────────────────────────────
  static Future<({String name, String brand, String desc, String cat})>
      _fetchUpcItemDb(String barcode) async {
    try {
      final r = await http
          .get(
            Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode'),
            headers: {'Accept': 'application/json', ..._ua},
          )
          .timeout(_timeout);
      if (r.statusCode == 200) {
        final j     = jsonDecode(r.body) as Map<String, dynamic>;
        final items = (j['items'] as List<dynamic>?) ?? [];
        if (items.isNotEmpty) {
          final item = items.first as Map<String, dynamic>;
          // UPC DB sometimes returns category under 'category' field
          final rawCat = (item['category'] as String?) ?? '';
          return (
            name:  (item['title']       as String?) ?? '',
            brand: (item['brand']       as String?) ?? '',
            desc:  (item['description'] as String?) ?? '',
            cat:   rawCat,
          );
        }
      }
    } catch (_) {}
    return _empty();
  }

  // ── Open Food Facts (fallback only) ─────────────────────────
  static Future<({String name, String brand, String desc, String cat})>
      _fetchOpenFood(String barcode) async {
    try {
      final r = await http
          .get(
            Uri.parse('https://world.openfoodfacts.org/api/v0/product/$barcode.json'),
            headers: _ua,
          )
          .timeout(_timeout);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if ((j['status'] as int?) == 1) {
          final p = j['product'] as Map<String, dynamic>? ?? {};
          final brand = (p['brands'] as String?) ?? '';
          return (
            name:  (p['product_name'] as String?) ?? '',
            brand: brand.split(',').first.trim(),
            desc:  (p['generic_name'] as String?)
                ?? (p['ingredients_text'] as String?)
                    ?.split(',')
                    .take(3)
                    .join(', ')
                ?? '',
            cat: '',
          );
        }
      }
    } catch (_) {}
    return _empty();
  }

  // ── Main entry point ─────────────────────────────────────────
  static Future<_ScanResult> lookup(String barcode) async {
    // Fire primary sources in parallel
    final results = await Future.wait([
      _fetchGoUpc(barcode),
      _fetchUpcItemDb(barcode),
    ]);

    final goUpc  = results[0];
    final upcDb  = results[1];

    // Merge: prefer go-upc for each field (better for electronics),
    // fall through to UPC Item DB for any field go-upc left blank.
    String name  = goUpc.name.isNotEmpty  ? goUpc.name  : upcDb.name;
    String brand = goUpc.brand.isNotEmpty ? goUpc.brand : upcDb.brand;
    String desc  = goUpc.desc.isNotEmpty  ? goUpc.desc  : upcDb.desc;
    String cat   = goUpc.cat.isNotEmpty   ? goUpc.cat   : upcDb.cat;

    // If both primary sources returned nothing, try Open Food Facts
    if (name.isEmpty && brand.isEmpty) {
      final food = await _fetchOpenFood(barcode);
      name  = food.name;
      brand = food.brand;
      desc  = food.desc;
    }

    // Resolve category
    final resolvedCat = cat.isNotEmpty ? cat : _guessCategory(name, brand);

    return _ScanResult(
      barcode: barcode,
      name: name, brand: brand,
      description: desc, category: resolvedCat,
    );
  }

  static String _guessCategory(String name, String brand) {
    final l = '${name.toLowerCase()} ${brand.toLowerCase()}';
    if (l.contains('iphone') || l.contains('samsung') || l.contains('pixel') ||
        l.contains('oneplus') || l.contains('phone') || l.contains('mobile')) {
      return 'Mobile Phones';
    }
    if (l.contains('ipad') || l.contains('tablet')) {
      return 'Tablets';
    }
    if (l.contains('watch') || l.contains('band') ||
        l.contains('earbuds') || l.contains('airpods')) {
      return 'Wearables';
    }
    if (l.contains('charger') || l.contains('cable') || l.contains('case') ||
        l.contains('cover') || l.contains('adapter')) {
      return 'Accessories';
    }
    if (l.contains('screen') || l.contains('battery') || l.contains('speaker') ||
        l.contains('camera') || l.contains('flex') || l.contains('connector')) {
      return 'Spare Parts';
    }
    return 'Spare Parts';
  }
}

// ═══════════════════════════════════════════════════════════════
//  OCR TEXT PARSER  (shared logic with add_repair)
//  Extracts product name, brand from recognised text lines.
// ═══════════════════════════════════════════════════════════════
class _OcrProductParser {
  static const _brands = [
    'Samsung', 'Apple', 'OnePlus', 'Xiaomi', 'Redmi', 'POCO', 'Realme',
    'Oppo', 'Vivo', 'iQOO', 'Motorola', 'Nokia', 'Sony', 'LG', 'Google',
    'Huawei', 'Honor', 'Asus', 'Lenovo', 'Tecno', 'Infinix', 'itel',
  ];

  static ({String name, String brand, String sku, List<String> allLines})
      parse(List<String> rawLines) {
    final lines = rawLines.map((l) => l.trim()).where((t) => t.isNotEmpty).toList();
    String name = '', brand = '', sku = '';

    // Longest non-numeric line is likely the product name
    final textLines = lines.where((l) => !RegExp(r'^\d+$').hasMatch(l)).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (textLines.isNotEmpty) name = textLines.first;

    for (final line in lines) {
      if (brand.isEmpty) {
        for (final b in _brands) {
          if (line.toLowerCase().contains(b.toLowerCase())) { brand = b; break; }
        }
      }
      // SKU / barcode: alphanumeric 6-20 chars that looks like a part number
      if (sku.isEmpty) {
        final m = RegExp(r'\b[A-Z0-9\-]{6,20}\b').firstMatch(line);
        if (m != null && !RegExp(r'^\d+$').hasMatch(m.group(0)!)) {
          sku = m.group(0)!;
        }
      }
    }

    return (name: name, brand: brand, sku: sku, allLines: lines);
  }
}

// ═══════════════════════════════════════════════════════════════
//  FULL-SCREEN BARCODE + OCR SCANNER  (inventory variant)
//
//  Two modes:
//    Barcode — auto-detects; looks up product name/brand online
//    Read Text — takes a photo (image_picker); extracts product
//                name, brand, SKU from label via ML Kit OCR
//
//  pubspec.yaml additions:
//    google_mlkit_text_recognition: ^0.13.1   ← new
//    (image_picker, path_provider already present)
// ═══════════════════════════════════════════════════════════════
enum _InvScanMode { barcode, ocr }

class _BarcodeScannerScreen extends StatefulWidget {
  const _BarcodeScannerScreen();
  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _ctrl;
  _InvScanMode _mode      = _InvScanMode.barcode;
  bool _torchOn           = false;
  bool _processing        = false;
  bool _barcodeActive     = true;
  String? _lastBarcode;

  // OCR state
  dynamic _recognizer;   // TextRecognizer — dynamic to avoid web compile error
  bool _ocrDone          = false;
  List<String> _ocrLines = [];
  String _ocrName = '', _ocrBrand = '', _ocrSku = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    if (!kIsWeb) {
      try { _recognizer = TextRecognizer(script: TextRecognitionScript.latin); } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    try { (_recognizer as dynamic)?.close(); } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _ctrl.stop();
    } else if (state == AppLifecycleState.resumed && !_processing) {
      _ctrl.start();
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_mode != _InvScanMode.barcode || !_barcodeActive || _processing) return;
    final hits = capture.barcodes.where((b) => b.rawValue?.isNotEmpty == true).toList();
    if (hits.isEmpty) return;

    final raw = hits.first.rawValue!;
    if (raw == _lastBarcode) return;
    _lastBarcode = raw;

    HapticFeedback.mediumImpact();
    setState(() { _barcodeActive = false; _processing = true; });
    await _ctrl.stop();

    final result = await _BarcodeLookupService.lookup(raw);

    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _captureOcr() async {
    if (_processing) return;
    if (kIsWeb) { _manualEntry(); return; }

    await _ctrl.stop();
    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (_) {}
    if (!_processing) _ctrl.start();
    if (photo == null || !mounted) return;

    setState(() { _processing = true; _ocrDone = false; });
    try {
      final recognized = await (_recognizer as TextRecognizer)
          .processImage(InputImage.fromFilePath(photo.path));
      try { File(photo.path).delete(); } catch (_) {}

      final rawLines = recognized.blocks
          .expand((b) => b.lines)
          .map((l) => l.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final parsed = _OcrProductParser.parse(rawLines);

      if (!mounted) return;
      if (parsed.allLines.isEmpty) {
        setState(() => _processing = false);
        _ctrl.start();
        _showSnack('No text found — better lighting or move closer', isError: true);
        return;
      }

      setState(() {
        _processing = false; _ocrDone = true;
        _ocrLines = parsed.allLines;
        _ocrName  = parsed.name;
        _ocrBrand = parsed.brand;
        _ocrSku   = parsed.sku;
      });

      // Auto-confirm when we have a name
      if (_ocrName.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) _confirmOcr();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        _ctrl.start();
        _showSnack('OCR failed: $e', isError: true);
      }
    }
  }

  void _confirmOcr() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(_ScanResult(
      barcode: _ocrSku,
      name: _ocrName, brand: _ocrBrand,
    ));
  }

  void _switchMode(_InvScanMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m; _barcodeActive = true;
      _ocrDone = false; _ocrLines = [];
      _ocrName = _ocrBrand = _ocrSku = '';
    });
    if (!_processing) _ctrl.start();
  }

  void _manualEntry() {
    final ctrl = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enter Barcode / SKU', style: GoogleFonts.syne(
            fontWeight: FontWeight.w800, color: Colors.white)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: GoogleFonts.syne(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. 012345678905 or SCR-SAM-S24',
            hintStyle: GoogleFonts.syne(color: Colors.white38)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c),
              child: Text('Cancel', style: GoogleFonts.syne(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Confirm', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ).then((v) async {
      if (v == null || v.isEmpty || !mounted) return;
      setState(() { _processing = true; _lastBarcode = v; });
      await _ctrl.stop();
      final result = await _BarcodeLookupService.lookup(v);
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
      backgroundColor: isError ? Colors.red.shade800 : C.bgElevated,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),

        if (_mode == _InvScanMode.barcode)
          CustomPaint(painter: _ScanOverlayPainter()),
        if (_mode == _InvScanMode.ocr && !_ocrDone)
          CustomPaint(painter: _OcrVignettePainterInv()),

        // Top bar
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            _circleBtn(Icons.close, () => Navigator.pop(context)),
            const Spacer(),
            _InvModePill(mode: _mode, onChanged: _switchMode),
            const Spacer(),
            _circleBtn(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              () async { await _ctrl.toggleTorch(); setState(() => _torchOn = !_torchOn); },
              bg: _torchOn ? Colors.amber.withValues(alpha: 0.75) : null,
            ),
          ]),
        )),

        // Barcode hint
        if (_mode == _InvScanMode.barcode && !_processing)
          Positioned(
            top: h * 0.28, left: 0, right: 0,
            child: Center(child: _pill('Align barcode within the frame')),
          ),

        // OCR instructions
        if (_mode == _InvScanMode.ocr && !_processing && !_ocrDone)
          Positioned(
            top: h * 0.13, left: 20, right: 20,
            child: Center(child: _pill(
              kIsWeb
                  ? 'OCR not available on web — tap Capture to enter manually'
                  : 'Aim at product label or packaging\nthen tap Capture',
            )),
          ),

        // OCR capture button
        if (_mode == _InvScanMode.ocr && !_processing && !_ocrDone)
          Positioned(
            bottom: bottom + 44, left: 0, right: 0,
            child: Center(child: GestureDetector(
              onTap: _captureOcr,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 32),
              ),
            )),
          ),

        // OCR results
        if (_mode == _InvScanMode.ocr && _ocrDone && !_processing)
          _InvOcrResultPanel(
            name: _ocrName, brand: _ocrBrand, sku: _ocrSku,
            allLines: _ocrLines,
            onConfirm: _confirmOcr,
            onRetry: () => setState(() {
              _ocrDone = false; _ocrLines = [];
              _ocrName = _ocrBrand = _ocrSku = '';
            }),
          ),

        // Processing spinner
        if (_processing)
          Container(
            color: Colors.black.withValues(alpha: 0.78),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                _mode == _InvScanMode.ocr ? 'Reading product label…' : 'Looking up product…',
                style: GoogleFonts.syne(fontSize: 15,
                    fontWeight: FontWeight.w700, color: Colors.white)),
            ])),
          ),

        // Barcode bottom
        if (_mode == _InvScanMode.barcode && !_processing)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 24),
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
              )),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text("Can't scan? Switch to Read Text ↑ or enter manually",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(fontSize: 11, color: Colors.white54)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _manualEntry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Text('⌨️  Type Barcode / SKU',
                        style: GoogleFonts.syne(fontSize: 13,
                            fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback fn, {Color? bg}) =>
      GestureDetector(
        onTap: fn,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: bg ?? Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(99)),
    child: Text(text, textAlign: TextAlign.center,
        style: GoogleFonts.syne(fontSize: 12, color: Colors.white70)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
class _InvModePill extends StatelessWidget {
  final _InvScanMode mode;
  final ValueChanged<_InvScanMode> onChanged;
  const _InvModePill({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _tab('Barcode',   Icons.qr_code_scanner, _InvScanMode.barcode),
      _tab('Read Text', Icons.text_fields,      _InvScanMode.ocr),
    ]),
  );

  Widget _tab(String label, IconData icon, _InvScanMode m) {
    final sel = mode == m;
    return GestureDetector(
      onTap: () => onChanged(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: sel ? const Color(0xFF6C63FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.syne(
              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _InvOcrResultPanel extends StatelessWidget {
  final String name, brand, sku;
  final List<String> allLines;
  final VoidCallback onConfirm, onRetry;
  const _InvOcrResultPanel({
    required this.name, required this.brand, required this.sku,
    required this.allLines, required this.onConfirm, required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final hasResult = name.isNotEmpty || brand.isNotEmpty || sku.isNotEmpty;
    final otherLines = allLines
        .where((l) => l != name && l != brand && l != sku && l.length >= 3)
        .take(14).toList();

    return Positioned.fill(
      top: MediaQuery.of(context).padding.top + 60,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.97),
                   Colors.black.withValues(alpha: 0.65)],
        )),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            if (hasResult) ...[
              Container(
                width: double.infinity, padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF6C63FF), width: 1.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 16),
                    const SizedBox(width: 6),
                    Text('Product Detected', style: GoogleFonts.syne(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: const Color(0xFF6C63FF))),
                  ]),
                  const SizedBox(height: 10),
                  if (name.isNotEmpty)  _row('Name',  name),
                  if (brand.isNotEmpty) _row('Brand', brand),
                  if (sku.isNotEmpty)   _row('SKU',   sku, mono: true),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                      label: Text('Use These Details',
                          style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            if (otherLines.isNotEmpty) ...[
              Text('ALL TEXT FOUND', style: GoogleFonts.syne(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: Colors.white38, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: otherLines.map((l) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Text(l, style: GoogleFonts.syne(
                      fontSize: 11, color: Colors.white60)),
                )).toList(),
              ),
              const SizedBox(height: 20),
            ],

            Center(child: GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text('🔄  Scan Again',
                    style: GoogleFonts.syne(fontSize: 13,
                        fontWeight: FontWeight.w700, color: Colors.white70)),
              ),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 60, child: Text(label, style: GoogleFonts.syne(
          fontSize: 11, color: Colors.white54))),
      Expanded(child: Text(value, style: mono
          ? const TextStyle(fontFamily: 'monospace', fontSize: 13,
                            color: Colors.white, letterSpacing: 1.2)
          : GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700,
                              color: Colors.white))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  OVERLAY PAINTERS
// ─────────────────────────────────────────────────────────────────────────────
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanW = size.width * 0.72;
    final scanH = scanW * 0.55;
    final l = (size.width - scanW) / 2, t = size.height * 0.35;
    final r = l + scanW, b = t + scanH;

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(l, t, r, b), const Radius.circular(14)))
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    const cl = 22.0;
    final p = Paint()..color = const Color(0xFF00C2FF)
        ..strokeWidth = 3.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    void br(Offset a, Offset c, Offset d) {
      canvas.drawLine(a, c, p); canvas.drawLine(c, d, p);
    }
    br(Offset(l,t+cl), Offset(l,t), Offset(l+cl,t));
    br(Offset(r-cl,t), Offset(r,t), Offset(r,t+cl));
    br(Offset(l,b-cl), Offset(l,b), Offset(l+cl,b));
    br(Offset(r-cl,b), Offset(r,b), Offset(r,b-cl));

    canvas.drawLine(Offset(l+8, t+scanH/2), Offset(r-8, t+scanH/2),
        Paint()..color = const Color(0xFF00C2FF).withValues(alpha: 0.7)
               ..strokeWidth = 2);
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

class _OcrVignettePainterInv extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = RadialGradient(
        center: Alignment.center, radius: 0.85,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.4)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    const m = 28.0, cl = 30.0;
    final p = Paint()..color = Colors.white.withValues(alpha: 0.65)
        ..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    void br(Offset a, Offset c, Offset d) {
      canvas.drawLine(a, c, p); canvas.drawLine(c, d, p);
    }
    br(Offset(m,m+cl),                       Offset(m,m),                       Offset(m+cl,m));
    br(Offset(size.width-m-cl,m),             Offset(size.width-m,m),            Offset(size.width-m,m+cl));
    br(Offset(m,size.height-m-cl),            Offset(m,size.height-m),           Offset(m+cl,size.height-m));
    br(Offset(size.width-m-cl,size.height-m), Offset(size.width-m,size.height-m),Offset(size.width-m,size.height-m-cl));
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}
