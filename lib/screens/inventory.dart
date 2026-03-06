import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import '../models/m.dart';
import '../data/providers.dart';
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
    if (!_synced && !_syncing && session != null && session.shopId.isNotEmpty) {
      _syncing = true;
      _syncProductsFromFirebase(session.shopId).whenComplete(() {
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_inventory',
        onPressed: () => _openProductForm(context, null),
        backgroundColor: C.primary,
        foregroundColor: C.bg,
        icon: const Icon(Icons.add),
        label: Text('Add Product', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
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
      final session = ref.read(currentUserProvider).asData?.value;
      final shopId = session?.shopId ?? '';
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
        'by': session?.displayName ?? 'Admin',
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
  const ProductFormScreen({super.key, this.product});
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
    final p = widget.product;
    _name        = TextEditingController(text: p?.productName ?? '');
    _sku         = TextEditingController(text: p?.sku ?? '');
    _brand       = TextEditingController(text: p?.brand ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _supplier    = TextEditingController(text: p?.supplierName ?? '');
    _cost        = TextEditingController(text: p?.costPrice.toStringAsFixed(0) ?? '');
    _price       = TextEditingController(text: p?.sellingPrice.toStringAsFixed(0) ?? '');
    _qty         = TextEditingController(text: p?.stockQty.toString() ?? '0');
    _reorder     = TextEditingController(text: p?.reorderLevel.toString() ?? '5');
    _cat         = p?.category ?? 'Spare Parts';
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
    // Open full-screen scanner
    final result = await Navigator.of(context).push<_ScanResult>(
      MaterialPageRoute(builder: (_) => const _BarcodeScannerScreen()),
    );
    if (result == null || !mounted) return;

    // Always fill the SKU field
    setState(() => _sku.text = result.barcode);

    // Show a loading indicator while we fetch product info
    if (result.productInfo != null) {
      final info = result.productInfo!;
      setState(() {
        if (info.name.isNotEmpty && _name.text.isEmpty) _name.text = info.name;
        if (info.brand.isNotEmpty && _brand.text.isEmpty) _brand.text = info.brand;
        if (info.description.isNotEmpty && _description.text.isEmpty) {
          _description.text = info.description;
        }
        if (info.category.isNotEmpty) _cat = info.category;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('✅ ', style: TextStyle(fontSize: 16)),
            Expanded(child: Text(
              'Found: ${info.name.isNotEmpty ? info.name : result.barcode}',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            )),
          ]),
          backgroundColor: C.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '📦 Barcode ${result.barcode} scanned — fill details manually',
            style: GoogleFonts.syne(fontWeight: FontWeight.w700),
          ),
          backgroundColor: C.bgElevated,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final notifier = ref.read(productsProvider.notifier);
    final existing = widget.product;
    final id = existing?.productId ?? 'p${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    
    final session = ref.read(currentUserProvider).asData?.value;
    final shopId = session?.shopId ?? '';

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
//  BARCODE SCANNER DATA MODELS
// ═══════════════════════════════════════════════════════════════

/// Holds a scanned barcode + any product info fetched from the internet
class _ScanResult {
  final String barcode;
  final _ProductLookup? productInfo;
  const _ScanResult({required this.barcode, this.productInfo});
}

/// Normalised product data from any lookup API
class _ProductLookup {
  final String name;
  final String brand;
  final String description;
  final String category;

  const _ProductLookup({
    this.name = '',
    this.brand = '',
    this.description = '',
    this.category = '',
  });
}

// ═══════════════════════════════════════════════════════════════
//  BARCODE LOOKUP SERVICE
//  Tries Open Food Facts first, then falls back to UPC Item DB.
//  Both are free, no API key required.
// ═══════════════════════════════════════════════════════════════
class _BarcodeLookupService {
  /// Returns null if nothing found or on network error.
  static Future<_ProductLookup?> lookup(String barcode) async {
    // ── Try 1: Open Food Facts (great for consumer electronics too) ──────────
    try {
      final uri = Uri.parse(
          'https://world.openfoodfacts.org/api/v0/product/$barcode.json');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        if ((json['status'] as int?) == 1) {
          final p = json['product'] as Map<String, dynamic>? ?? {};
          final name = (p['product_name'] as String?) ?? '';
          final brand = (p['brands'] as String?) ?? '';
          final desc = (p['generic_name'] as String?)
              ?? (p['ingredients_text'] as String?)?.split(',').take(3).join(', ')
              ?? '';
          if (name.isNotEmpty || brand.isNotEmpty) {
            return _ProductLookup(
              name: name,
              brand: brand.split(',').first.trim(),
              description: desc,
              category: _guessCategory(name, brand),
            );
          }
        }
      }
    } catch (_) {}

    // ── Try 2: UPC Item DB ───────────────────────────────────────────────────
    try {
      final uri = Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$barcode');
      final res = await http.get(uri,
          headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final items = (json['items'] as List<dynamic>?) ?? [];
        if (items.isNotEmpty) {
          final item = items.first as Map<String, dynamic>;
          final name = (item['title'] as String?) ?? '';
          final brand = (item['brand'] as String?) ?? '';
          final desc = (item['description'] as String?) ?? '';
          if (name.isNotEmpty) {
            return _ProductLookup(
              name: name,
              brand: brand,
              description: desc,
              category: _guessCategory(name, brand),
            );
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Guess a category from name/brand keywords
  static String _guessCategory(String name, String brand) {
    final lower = '${name.toLowerCase()} ${brand.toLowerCase()}';
    if (lower.contains('iphone') || lower.contains('samsung') ||
        lower.contains('pixel') || lower.contains('oneplus') ||
        lower.contains('phone') || lower.contains('mobile')) {
      return 'Mobile Phones';
    }
    if (lower.contains('ipad') || lower.contains('tablet')) return 'Tablets';
    if (lower.contains('watch') || lower.contains('band') ||
        lower.contains('earbuds') || lower.contains('airpods')) {
      return 'Wearables';
    }
    if (lower.contains('charger') || lower.contains('cable') ||
        lower.contains('case') || lower.contains('cover') ||
        lower.contains('screen protector') || lower.contains('adapter')) {
      return 'Accessories';
    }
    if (lower.contains('screen') || lower.contains('battery') ||
        lower.contains('speaker') || lower.contains('camera') ||
        lower.contains('flex') || lower.contains('connector')) {
      return 'Spare Parts';
    }
    return 'Spare Parts'; // sensible default for a repair shop
  }
}

// ═══════════════════════════════════════════════════════════════
//  FULL-SCREEN BARCODE SCANNER SCREEN
// ═══════════════════════════════════════════════════════════════
class _BarcodeScannerScreen extends StatefulWidget {
  const _BarcodeScannerScreen();

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _ctrl;
  bool _torchOn = false;
  bool _scanning = true;   // lock after first valid scan
  bool _looking = false;   // true while API lookup is in flight
  String? _lastBarcode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _ctrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      _ctrl.start();
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning || _looking) return;
    final barcodes = capture.barcodes
        .where((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
        .toList();
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue!;
    if (rawValue == _lastBarcode) return; // debounce same code
    _lastBarcode = rawValue;

    // Haptic feedback
    HapticFeedback.mediumImpact();

    setState(() { _scanning = false; _looking = true; });
    await _ctrl.stop();

    // Show "looking up…" UI, then fetch
    _ProductLookup? info;
    try {
      info = await _BarcodeLookupService.lookup(rawValue);
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop(_ScanResult(
        barcode: rawValue,
        productInfo: info,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Live camera ───────────────────────────────────────
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
          ),

          // ── Dark vignette overlay ─────────────────────────────
          CustomPaint(painter: _ScanOverlayPainter()),

          // ── Top bar ───────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Back
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                  const Spacer(),
                  // Title
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('Scan Barcode',
                        style: GoogleFonts.syne(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  const Spacer(),
                  // Torch toggle
                  GestureDetector(
                    onTap: () async {
                      await _ctrl.toggleTorch();
                      setState(() => _torchOn = !_torchOn);
                    },
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _torchOn
                            ? Colors.amber.withValues(alpha: 0.8)
                            : Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _torchOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white, size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Scan-box label ────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).size.height * 0.28,
            left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'Align barcode within the frame',
                  style: GoogleFonts.syne(
                      fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
          ),

          // ── Lookup spinner / result ───────────────────────────
          if (_looking)
            Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text('Looking up product…',
                        style: GoogleFonts.syne(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 6),
                    Text(_lastBarcode ?? '',
                        style: GoogleFonts.syne(
                            fontSize: 12, color: Colors.white60)),
                  ],
                ),
              ),
            ),

          // ── Bottom hint — manual entry ────────────────────────
          if (!_looking)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.of(context).padding.bottom + 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Can\'t scan? Enter manually',
                        style: GoogleFonts.syne(
                            fontSize: 12, color: Colors.white54)),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _manualEntry(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Text('⌨️  Type Barcode / SKU',
                            style: GoogleFonts.syne(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _manualEntry(BuildContext context) async {
    final ctrl = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enter Barcode / SKU',
            style: GoogleFonts.syne(
                fontWeight: FontWeight.w800, color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.text,
          style: GoogleFonts.syne(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. 012345678905 or SCR-SAM-S24',
            hintStyle: GoogleFonts.syne(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.syne(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C2FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Look Up',
                style: GoogleFonts.syne(
                    fontWeight: FontWeight.w800, color: Colors.black)),
          ),
        ],
      ),
    );

    if (entered != null && entered.isNotEmpty && mounted) {
      setState(() { _scanning = false; _looking = true; _lastBarcode = entered; });
      await _ctrl.stop();
      _ProductLookup? info;
      try {
        info = await _BarcodeLookupService.lookup(entered);
      } catch (_) {}
      if (mounted) {
        // ignore: use_build_context_synchronously
        Navigator.of(context).pop(_ScanResult(
          barcode: entered,
          productInfo: info,
        ));
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  SCAN FRAME OVERLAY PAINTER
//  Draws a clear rectangle in the middle and darkens the rest
// ═══════════════════════════════════════════════════════════════
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanW = size.width * 0.72;
    final scanH = scanW * 0.55;
    final left   = (size.width - scanW) / 2;
    final top    = size.height * 0.35;
    final right  = left + scanW;
    final bottom = top + scanH;
    final scanRect = Rect.fromLTRB(left, top, right, bottom);

    // Darken everything except the scan box
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(14)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    // Corner brackets
    const cornerLen = 22.0;
    const cornerW   = 3.5;
    final cornerPaint = Paint()
      ..color = const Color(0xFF00C2FF)
      ..strokeWidth = cornerW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final corners = [
      // Top-left
      [Offset(left, top + cornerLen), Offset(left, top), Offset(left + cornerLen, top)],
      // Top-right
      [Offset(right - cornerLen, top), Offset(right, top), Offset(right, top + cornerLen)],
      // Bottom-left
      [Offset(left, bottom - cornerLen), Offset(left, bottom), Offset(left + cornerLen, bottom)],
      // Bottom-right
      [Offset(right - cornerLen, bottom), Offset(right, bottom), Offset(right, bottom - cornerLen)],
    ];

    for (final pts in corners) {
      canvas.drawLine(pts[0], pts[1], cornerPaint);
      canvas.drawLine(pts[1], pts[2], cornerPaint);
    }

    // Scanning line animation — static line in middle (no AnimationController needed)
    final linePaint = Paint()
      ..color = const Color(0xFF00C2FF).withValues(alpha: 0.7)
      ..strokeWidth = 2;
    final midY = top + scanH / 2;
    canvas.drawLine(Offset(left + 8, midY), Offset(right - 8, midY), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
