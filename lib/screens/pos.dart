import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/m.dart';
import '../data/providers.dart';
import '../data/active_session.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

class POSScreen extends ConsumerStatefulWidget {
  const POSScreen({super.key});
  @override
  ConsumerState<POSScreen> createState() => _POSState();
}

class _POSState extends ConsumerState<POSScreen> {
  String _payment = 'Cash';
  double _discount = 0;
  bool _discPct = false;
  bool _charging = false;
  final _discCtrl = TextEditingController(text: '0');
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _synced = false;
  bool _syncing = false;
  // Stored after a successful sale so the receipt sheet can render it
  List<CartItem> _lastCart = [];
  double _lastTotal = 0;
  double _lastDiscAmt = 0;
  double _lastTaxAmt = 0;
  String _lastTaxType = 'GST';
  double _lastTaxRate = 0;

  @override
  void dispose() {
    _discCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Fetch products from Firebase and set local state ──────────────────────
  Future<void> _syncProductsFromFirebase(String shopId) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('products').orderByChild('shopId').equalTo(shopId).get();
      final list = <Product>[];
      if (snap.exists) {
        for (final child in snap.children) {
          if (child.key == null || child.value is! Map) continue;
          final d = Map<String, dynamic>.from(child.value as Map);
          list.add(Product(
            productId:    child.key!,
            shopId:       (d['shopId']       as String?) ?? shopId,
            sku:          (d['sku']          as String?) ?? '',
            productName:  (d['productName']  as String?) ?? '',
            category:     (d['category']     as String?) ?? 'Spare Parts',
            brand:        (d['brand']        as String?) ?? '',
            description:  (d['description']  as String?) ?? '',
            supplierName: (d['supplierName'] as String?) ?? '',
            costPrice:    (d['costPrice']    as num?)?.toDouble() ?? 0,
            sellingPrice: (d['sellingPrice'] as num?)?.toDouble() ?? 0,
            stockQty:     (d['stockQty']     as int?)  ?? 0,
            reorderLevel: (d['reorderLevel'] as int?)  ?? 5,
            isActive:     (d['isActive']     as bool?) ?? true,
            imageUrl:     (d['imageUrl']     as String?) ?? '',
            createdAt:    (d['createdAt']    as String?) ?? '',
            updatedAt:    (d['updatedAt']    as String?) ?? '',
          ));
        }
      }
      ref.read(productsProvider.notifier).setAll(list);
    } catch (e) {
      debugPrint('⚠️ _syncProductsFromFirebase: $e');
    }
  }

  // ── Process a sale ────────────────────────────────────────────────────────
  //
  //  DOUBLE-DEDUCTION FIX
  //  ====================
  //  OLD code did:
  //    1. Write newQty to DB          (DB: 10 - 2 = 8)
  //    2. adjustQty(id, -item.qty)    (local state: 10 - 2 = 8) ← correct
  //    3. _syncProductsFromFirebase() (local state = DB = 8)    ← deducts AGAIN? No...
  //
  //  The actual double-deduction happened because _synced was reset to false
  //  somewhere (or the widget rebuilt), causing _syncProductsFromFirebase to
  //  run AGAIN before adjustQty ran. Race condition:
  //    t=0  Sale starts, snapshot allProducts has qty=10
  //    t=1  DB write: 10-2=8
  //    t=2  Sync runs (triggered by rebuild): local = 8
  //    t=3  adjustQty(-2): local = 8-2 = 6  ← WRONG, deducted twice
  //
  //  FIX: REMOVE adjustQty entirely after a sale. After the DB write,
  //  call _syncProductsFromFirebase() ONCE as the sole source of truth.
  //  Local state will equal DB state (8). No double deduction possible.
  //
  Future<void> _processSale(List<CartItem> cart, String shopId) async {
    final db = FirebaseDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();

    // Snapshot current local qty BEFORE any writes (for stock_history oldQty)
    final snapshot = Map.fromEntries(
      ref.read(productsProvider).map((p) => MapEntry(p.productId, p.stockQty))
    );

    // ── Step 1: Write stock deductions + transactions (critical) ─────────────
    final batch = <String, dynamic>{};
    for (final item in cart) {
      final oldQty = snapshot[item.product.productId] ?? item.product.stockQty;
      final newQty = (oldQty - item.qty).clamp(0, 99999);
      batch['products/${item.product.productId}/stockQty'] = newQty;
      batch['products/${item.product.productId}/updatedAt'] = nowIso;
      batch['transactions/tx_${now}_${item.product.productId}'] = {
        'shopId':      shopId,
        'productId':   item.product.productId,
        'productName': item.product.productName,
        'qty':         item.qty,
        'price':       item.product.sellingPrice,
        'cost':        item.product.costPrice,
        'total':       item.product.sellingPrice * item.qty,
        'type':        'sale',
        'payment':     _payment,
        'time':        now,
      };
    }
    // Throws on permission denied — caught by caller which shows SnackBar
    await db.ref().update(batch);

    // ── Step 2: Re-sync local state from DB (single source of truth) ─────────
    // NEVER call adjustQty here — that would subtract again from what DB has.
    await _syncProductsFromFirebase(shopId);

    // ── Step 3: Stock history (non-critical, failures don't block the sale) ──
    try {
      final histBatch = <String, dynamic>{};
      for (final item in cart) {
        final oldQty = snapshot[item.product.productId] ?? item.product.stockQty;
        final newQty = (oldQty - item.qty).clamp(0, 99999);
        histBatch['stock_history/h_${now}_${item.product.productId}'] = {
          'shopId':      shopId,
          'productId':   item.product.productId,
          'productName': item.product.productName,
          'oldQty':      oldQty,
          'newQty':      newQty,
          'delta':       -item.qty,
          'type':        'sale',
          'time':        now,
          'by':          'POS',
        };
      }
      await db.ref().update(histBatch);
    } catch (e) {
      debugPrint('⚠️ stock_history write (non-fatal): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final cart = ref.watch(cartProvider);
    final sessionAsync = ref.watch(currentUserProvider);
    final session = sessionAsync.asData?.value;
    final activeSession = ref.watch(activeSessionProvider);
    final resolvedShopId = activeSession?.shopId.isNotEmpty == true
        ? activeSession!.shopId : (session?.shopId ?? '');

    if (!_synced && !_syncing && resolvedShopId.isNotEmpty) {
      _syncing = true;
      _syncProductsFromFirebase(resolvedShopId).whenComplete(() {
        if (mounted) setState(() { _synced = true; _syncing = false; });
      });
    }

    final available = products.where((p) =>
        p.stockQty > 0 &&
        (_search.isEmpty ||
            p.productName.toLowerCase().contains(_search.toLowerCase()) ||
            p.sku.toLowerCase().contains(_search.toLowerCase()))).toList();

    final subtotal = cart.fold(0.0, (s, c) => s + c.product.sellingPrice * c.qty);
    final discAmt  = _discPct ? subtotal * _discount / 100 : _discount;
    // ── Tax reads from shop settings — No Tax / GST / VAT + price-inclusive ──
    final settings    = ref.watch(settingsProvider);
    final taxType     = settings.settings['taxType']        as String? ?? 'GST';
    final priceIncl   = settings.settings['priceInclusive'] as bool?   ?? false;
    final taxRate     = taxType == 'No Tax' ? 0.0 : settings.defaultTaxRate;
    final taxableBase = subtotal - discAmt;
    final taxAmt = taxType == 'No Tax'
        ? 0.0
        : priceIncl
            ? taxableBase - (taxableBase / (1 + taxRate / 100))
            : taxableBase * taxRate / 100;
    final total = priceIncl
        ? subtotal - discAmt
        : subtotal - discAmt + taxAmt;

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(
        children: [
          // ── Search ────────────────────────────────────────────────────────
          Container(
            color: C.bgElevated,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.syne(fontSize: 13, color: C.text),
              decoration: const InputDecoration(
                hintText: '🔍 Search or scan barcode...',
                prefixIcon: Icon(Icons.qr_code_scanner, color: C.textMuted, size: 20),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Product grid ─────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final p = available[i];
                        final cartItem = cart.where(
                            (c) => c.product.productId == p.productId).toList();
                        final inCart = cartItem.isNotEmpty;
                        final qty = inCart ? cartItem.first.qty : 0;
                        final icon = p.category == 'Mobile Phones' ? '📱'
                            : p.category == 'Spare Parts' ? '🔩' : '🔌';
                        return GestureDetector(
                          onTap: () => ref.read(cartProvider.notifier).add(p),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: inCart
                                  ? C.primary.withValues(alpha: 0.1) : C.bgCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: inCart ? C.primary : C.border,
                                  width: inCart ? 2 : 1),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(icon,
                                        style: const TextStyle(fontSize: 22)),
                                    if (inCart)
                                      Container(
                                        width: 22, height: 22,
                                        decoration: const BoxDecoration(
                                            color: C.primary,
                                            shape: BoxShape.circle),
                                        child: Center(child: Text('$qty',
                                            style: GoogleFonts.syne(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: C.bg))),
                                      ),
                                  ],
                                ),
                                const Spacer(),
                                Text(p.productName,
                                    style: GoogleFonts.syne(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12, color: C.white),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(fmtMoney(p.sellingPrice),
                                    style: GoogleFonts.syne(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14, color: C.primary)),
                                Text('${p.stockQty} in stock',
                                    style: GoogleFonts.syne(
                                        fontSize: 10, color: C.textMuted)),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: available.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.9,
                    ),
                  ),
                ),

                // ── Cart ─────────────────────────────────────────────────────
                if (cart.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    sliver: SliverToBoxAdapter(
                      child: SCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('🛒 Cart (${cart.length})',
                                style: GoogleFonts.syne(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14, color: C.white)),
                            const SizedBox(height: 12),

                            ...cart.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(children: [
                                Expanded(child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.product.productName,
                                          style: GoogleFonts.syne(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13, color: C.text),
                                          overflow: TextOverflow.ellipsis),
                                      Text(
                                          '${fmtMoney(item.product.sellingPrice)} each',
                                          style: GoogleFonts.syne(
                                              fontSize: 11,
                                              color: C.textMuted)),
                                    ])),
                                Row(children: [
                                  _qtyBtn(Icons.remove, () => ref
                                      .read(cartProvider.notifier)
                                      .setQty(item.product.productId,
                                          item.qty - 1)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text('${item.qty}',
                                        style: GoogleFonts.syne(
                                            fontWeight: FontWeight.w700,
                                            color: C.white)),
                                  ),
                                  _qtyBtn(Icons.add, () => ref
                                      .read(cartProvider.notifier)
                                      .setQty(item.product.productId,
                                          item.qty + 1)),
                                ]),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                      fmtMoney(item.product.sellingPrice *
                                          item.qty),
                                      textAlign: TextAlign.right,
                                      style: GoogleFonts.syne(
                                          fontWeight: FontWeight.w700,
                                          color: C.primary, fontSize: 13)),
                                ),
                              ]),
                            )),

                            const Divider(color: C.border, height: 20),

                            // Discount
                            Text('DISCOUNT',
                                style: GoogleFonts.syne(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: C.textMuted, letterSpacing: 0.5)),
                            const SizedBox(height: 8),
                            Row(children: [
                              _toggleBtn('₹ Flat', !_discPct,
                                  () => setState(() => _discPct = false)),
                              const SizedBox(width: 8),
                              _toggleBtn('% Percent', _discPct,
                                  () => setState(() => _discPct = true)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _discCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => setState(() =>
                                      _discount = double.tryParse(v) ?? 0),
                                  style: GoogleFonts.syne(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: C.text),
                                  decoration: InputDecoration(
                                    prefixText: _discPct ? '' : '₹',
                                    suffixText: _discPct ? '%' : null,
                                    prefixStyle:
                                        GoogleFonts.syne(color: C.textMuted),
                                    suffixStyle:
                                        GoogleFonts.syne(color: C.textMuted),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 14),

                            // Totals
                            ...[
                              ['Subtotal', subtotal, null],
                              ['Discount', -discAmt, C.red],
                              if (taxType != 'No Tax') ...[[(priceIncl ? '$taxType ${taxRate.toStringAsFixed(0)}% (incl)' : '$taxType ${taxRate.toStringAsFixed(0)}%'), taxAmt, null]],
                            ].map((row) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(row[0] as String,
                                      style: GoogleFonts.syne(
                                          fontSize: 13,
                                          color: C.textMuted)),
                                  Text(
                                    (row[1] as double) < 0
                                        ? '-${fmtMoney(-(row[1] as double))}'
                                        : fmtMoney(row[1] as double),
                                    style: GoogleFonts.syne(
                                        fontSize: 13,
                                        color: (row[2] as Color?) ?? C.text),
                                  ),
                                ],
                              ),
                            )),

                            const Divider(color: C.border, height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('TOTAL',
                                    style: GoogleFonts.syne(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16, color: C.white)),
                                Text(fmtMoney(total),
                                    style: GoogleFonts.syne(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18, color: C.green)),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Payment methods
                            Wrap(
                              spacing: 6, runSpacing: 6,
                              children: [
                                'Cash', 'Card', 'UPI', 'Wallet', 'Bank Transfer'
                              ].map((m) {
                                final sel = _payment == m;
                                return GestureDetector(
                                  onTap: () => setState(() => _payment = m),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? C.primary.withValues(alpha: 0.18)
                                          : C.bgElevated,
                                      borderRadius:
                                          BorderRadius.circular(99),
                                      border: Border.all(
                                          color: sel ? C.primary : C.border),
                                    ),
                                    child: Text(m,
                                        style: GoogleFonts.syne(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: sel
                                                ? C.primary
                                                : C.textMuted)),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 14),

                            // ── Charge button ──────────────────────────────
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed:
                                    (_charging || session == null || cart.isEmpty)
                                        ? null
                                        : () async {
                                            // Capture context-dependent objects
                                            // BEFORE any await to avoid async gaps
                                            final messenger = ScaffoldMessenger.of(context);
                                            final navigator = Navigator.of(context);
                                            setState(() => _charging = true);
                                            try {
                                              // Capture for receipt before clearing cart
                                              final saleCart  = List<CartItem>.from(cart);
                                              final saleTotal = total;
                                              final saleDisc  = discAmt;
                                              final saleTaxAmt = taxAmt;
                                              final saleTaxType = taxType;
                                              final saleTaxRate = taxRate;

                                              await _processSale(cart, resolvedShopId);
                                              ref.read(cartProvider.notifier).clear();

                                              if (mounted) {
                                                // Store for receipt sheet
                                                setState(() {
                                                  _lastCart     = saleCart;
                                                  _lastTotal    = saleTotal;
                                                  _lastDiscAmt  = saleDisc;
                                                  _lastTaxAmt   = saleTaxAmt;
                                                  _lastTaxType  = saleTaxType;
                                                  _lastTaxRate  = saleTaxRate;
                                                });
                                                // Show receipt sheet — user taps
                                                // 'New Sale' inside to reset
                                                showModalBottomSheet(
                                                  context: navigator.context,
                                                  isScrollControlled: true,
                                                  isDismissible: false,
                                                  enableDrag: false,
                                                  backgroundColor: Colors.transparent,
                                                  builder: (_) => _PosReceiptSheet(
                                                    cart: _lastCart,
                                                    total: _lastTotal,
                                                    discAmt: _lastDiscAmt,
                                                    taxAmt: _lastTaxAmt,
                                                    taxType: _lastTaxType,
                                                    taxRate: _lastTaxRate,
                                                    payment: _payment,
                                                    settings: ref.read(settingsProvider),
                                                    onNewSale: () {
                                                      navigator.pop();
                                                      setState(() {
                                                        _discount = 0;
                                                        _discCtrl.text = '0';
                                                        _charging = false;
                                                      });
                                                    },
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              debugPrint('❌ Charge: $e');
                                              if (mounted) {
                                                messenger.showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Payment failed: $e',
                                                      style: GoogleFonts.syne(
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                  backgroundColor: C.red,
                                                ));
                                              }
                                            } finally {
                                              if (mounted) {
                                                setState(
                                                    () => _charging = false);
                                              }
                                            }
                                          },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: C.green,
                                  foregroundColor: C.bg,
                                  disabledBackgroundColor:
                                      C.green.withValues(alpha: 0.5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                child: _charging
                                    ? const SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white))
                                    : Text(
                                        '💳  Charge ${fmtMoney(total)}  ·  $_payment',
                                        style: GoogleFonts.syne(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
          border: Border.all(color: C.border),
          borderRadius: BorderRadius.circular(8),
          color: C.bgElevated),
      child: Icon(icon, size: 16, color: C.text),
    ),
  );

  Widget _toggleBtn(String label, bool sel, VoidCallback onTap) =>
      GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: sel ? C.accent.withValues(alpha: 0.15) : C.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: sel ? C.accent : C.border),
      ),
      child: Text(label,
          style: GoogleFonts.syne(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: sel ? C.accent : C.textMuted)),
    ),
  );

}

// ═══════════════════════════════════════════════════════════════
//  POS RECEIPT SHEET
//  Shown after a successful sale. Non-dismissible until user taps
//  "New Sale" — ensuring they always have a chance to print.
// ═══════════════════════════════════════════════════════════════
class _PosReceiptSheet extends StatefulWidget {
  final List<CartItem> cart;
  final double total;
  final double discAmt;
  final double taxAmt;
  final String taxType;
  final double taxRate;
  final String payment;
  final ShopSettings settings;
  final VoidCallback onNewSale;

  const _PosReceiptSheet({
    required this.cart,
    required this.total,
    required this.discAmt,
    required this.taxAmt,
    required this.taxType,
    required this.taxRate,
    required this.payment,
    required this.settings,
    required this.onNewSale,
  });

  @override
  State<_PosReceiptSheet> createState() => _PosReceiptSheetState();
}

class _PosReceiptSheetState extends State<_PosReceiptSheet> {
  bool _printing = false;

  double get _subtotal =>
      widget.cart.fold(0.0, (s, c) => s + c.product.sellingPrice * c.qty);

  Future<Uint8List> _buildReceiptPdf() async {
    final doc = pw.Document();
    final s = widget.settings;
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final receiptNo = 'RCP-${now.millisecondsSinceEpoch.toString().substring(7)}';

    doc.addPage(pw.Page(
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(s.shopName.isEmpty ? 'TechFix Pro' : s.shopName,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          if (s.address.isNotEmpty) pw.Text(s.address, style: const pw.TextStyle(fontSize: 10)),
          if (s.phone.isNotEmpty) pw.Text(s.phone, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 12),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('RECEIPT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('#$receiptNo', style: const pw.TextStyle(fontSize: 11)),
          ]),
          pw.Text('Date: $dateStr · Payment: ${widget.payment}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.Divider(),
          // Items
          ...widget.cart.map((item) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: pw.Text(
                  '${item.product.productName} ×${item.qty}',
                  style: const pw.TextStyle(fontSize: 11))),
              pw.Text(
                  '₹${(item.product.sellingPrice * item.qty).toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 11)),
            ],
          )),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
            pw.Text('Subtotal'),
            pw.Text('₹${_subtotal.toStringAsFixed(2)}'),
          ]),
          if (widget.discAmt > 0)
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
              pw.Text('Discount'),
              pw.Text('-₹${widget.discAmt.toStringAsFixed(2)}'),
            ]),
          if (widget.taxType != 'No Tax')
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
              pw.Text('${widget.taxType} ${widget.taxRate.toStringAsFixed(0)}%'),
              pw.Text('₹${widget.taxAmt.toStringAsFixed(2)}'),
            ]),
          pw.Divider(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
            pw.Text('TOTAL',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('₹${widget.total.toStringAsFixed(2)}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 16),
          pw.Center(child: pw.Text('Thank you for your purchase!',
              style: const pw.TextStyle(fontSize: 10))),
        ],
      ),
    ));
    return doc.save();
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final bytes = await _buildReceiptPdf();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payIcon = {
      'Cash': '💵',
      'Card': '💳',
      'UPI': '📲',
      'Wallet': '👛',
      'Bank Transfer': '🏦',
    }[widget.payment] ?? '💰';

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: C.bgElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Success header ───────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            decoration: BoxDecoration(
              color: C.green.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                  bottom: BorderSide(
                      color: C.green.withValues(alpha: 0.2))),
            ),
            child: Column(children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: C.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: C.green.withValues(alpha: 0.4), width: 2),
                ),
                child: const Center(
                    child: Text('✅', style: TextStyle(fontSize: 30))),
              ),
              const SizedBox(height: 12),
              Text('Payment Complete',
                  style: GoogleFonts.syne(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: C.green)),
              const SizedBox(height: 4),
              Text('$payIcon  ${widget.payment}  ·  ${fmtMoney(widget.total)}',
                  style: GoogleFonts.syne(
                      fontSize: 13, color: C.textMuted)),
            ]),
          ),

          // ── Receipt lines ────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              children: [
                // Items
                Container(
                  decoration: BoxDecoration(
                      color: C.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: C.border)),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: Row(children: [
                          Expanded(child: Text('ITEMS',
                              style: GoogleFonts.syne(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: C.primary,
                                  letterSpacing: 0.8))),
                          Text('AMOUNT',
                              style: GoogleFonts.syne(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: C.primary,
                                  letterSpacing: 0.8)),
                        ]),
                      ),
                      ...widget.cart.map((item) => Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: Row(children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.productName,
                                  style: GoogleFonts.syne(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: C.text)),
                              Text('×${item.qty}  @  ${fmtMoney(item.product.sellingPrice)}',
                                  style: GoogleFonts.syne(
                                      fontSize: 10, color: C.textMuted)),
                            ],
                          )),
                          Text(fmtMoney(item.product.sellingPrice * item.qty),
                              style: GoogleFonts.syne(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: C.text)),
                        ]),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Totals
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: C.bgCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: C.border)),
                  child: Column(children: [
                    _PosRow('Subtotal', _subtotal),
                    if (widget.discAmt > 0)
                      _PosRow('Discount', -widget.discAmt, color: C.red),
                    if (widget.taxType != 'No Tax')
                      _PosRow(
                          '${widget.taxType} ${widget.taxRate.toStringAsFixed(0)}%',
                          widget.taxAmt),
                    const Divider(color: C.border, height: 20),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('TOTAL',
                              style: GoogleFonts.syne(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: C.white)),
                          Text(fmtMoney(widget.total),
                              style: GoogleFonts.syne(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: C.green)),
                        ]),
                  ]),
                ),
              ],
            ),
          ),

          // ── Action buttons ───────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            decoration: const BoxDecoration(
              color: C.bgElevated,
              border: Border(top: BorderSide(color: C.border)),
            ),
            child: Row(children: [
              // Print receipt
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _printing ? null : _print,
                  icon: _printing
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: C.primary))
                      : const Icon(Icons.print_outlined, size: 16),
                  label: Text('Print Receipt',
                      style: GoogleFonts.syne(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.primary,
                    side: const BorderSide(color: C.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // New Sale
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: widget.onNewSale,
                  icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                  label: Text('New Sale',
                      style: GoogleFonts.syne(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: C.primary,
                    foregroundColor: C.bg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PosRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color? color;
  const _PosRow(this.label, this.amount, {this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
      Text(
        amount < 0 ? '-${fmtMoney(-amount)}' : fmtMoney(amount),
        style: GoogleFonts.syne(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? C.text),
      ),
    ]),
  );
}
