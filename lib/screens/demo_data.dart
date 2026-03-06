import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/providers.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

class DemoDataPage extends ConsumerStatefulWidget {
  const DemoDataPage({super.key});
  @override
  ConsumerState<DemoDataPage> createState() => _DemoDataState();
}

class _DemoDataState extends ConsumerState<DemoDataPage> {
  bool _busy = false;

  Future<void> _seed() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(currentUserProvider).asData?.value;
      final shopId = session?.shopId ?? '';
      if (shopId.isEmpty) return;
      final db = FirebaseDatabase.instance;

      await db.ref('shops/$shopId').update({
        'shopId': shopId,
        'shopName': 'TechFix Demo Shop',
        'ownerName': 'Demo Owner',
        'phone': '+91 90000 00000',
        'email': 'demo@techfixpro.app',
        'address': 'MG Road, Bangalore',
        'gstNumber': '29ABCDE1234F1Z5',
        'defaultTaxRate': 18.0,
        'invoicePrefix': 'INV',
        'requireIntakePhoto': true,
        'requireCompletionPhoto': false,
        'defaultWarrantyDays': 30,
        'darkMode': true,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final updates = <String, Object?>{};

      updates['users/demo_${shopId}_tech_1'] = {
        'userId': 'demo_${shopId}_tech_1',
        'displayName': 'Demo Technician',
        'phone': '+91 91111 11111',
        'email': 'tech@demo.com',
        'role': 'technician',
        'shopId': shopId,
        'specialization': 'Screen Repair',
        'isActive': true,
        'totalJobs': 5,
        'rating': 4.7,
        'demo': true,
        'createdAt': DateTime.now().toIso8601String(),
      };
      updates['users/demo_${shopId}_reception_1'] = {
        'userId': 'demo_${shopId}_reception_1',
        'displayName': 'Demo Reception',
        'phone': '+91 92222 22222',
        'email': 'reception@demo.com',
        'role': 'reception',
        'shopId': shopId,
        'specialization': 'Front Desk',
        'isActive': true,
        'totalJobs': 0,
        'rating': 4.5,
        'demo': true,
        'createdAt': DateTime.now().toIso8601String(),
      };

      updates['customers/c_demo_1'] = {
        'customerId': 'c_demo_1',
        'name': 'Rajesh Kumar',
        'phone': '+91 98765 43210',
        'email': 'rajesh@example.com',
        'address': 'Bangalore',
        'tier': 'Gold',
        'isVip': true,
        'isBlacklisted': false,
        'points': 1200,
        'repairsCount': 2,
        'totalSpend': 25000.0,
        'shopId': shopId,
        'demo': true,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      updates['products/p_demo_1'] = {
        'productId': 'p_demo_1',
        'sku': 'SCR-SAM-S24',
        'productName': 'Samsung S24 OLED Screen',
        'category': 'Spare Parts',
        'brand': 'Samsung',
        'description': 'OEM quality screen',
        'supplierName': 'Demo Supplier',
        'costPrice': 3200.0,
        'sellingPrice': 4200.0,
        'stockQty': 3,
        'reorderLevel': 5,
        'shopId': shopId,
        'demo': true,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      updates['jobs/j_demo_1'] = {
        'jobId': 'j_demo_1',
        'jobNumber': 'JOB-DEMO-0001',
        'customerId': 'c_demo_1',
        'customerName': 'Rajesh Kumar',
        'customerPhone': '+91 98765 43210',
        'brand': 'Samsung',
        'model': 'Galaxy S24',
        'imei': '352099001761481',
        'color': 'Black',
        'problem': 'Screen cracked',
        'notes': 'Demo job',
        'status': 'In Repair',
        'previousStatus': null,
        'holdReason': null,
        'priority': 'Normal',
        'technicianId': 'demo_${shopId}_tech_1',
        'technicianName': 'Demo Technician',
        'createdAt': DateTime.now().toIso8601String(),
        'estimatedEndDate': '2025-02-27',
        'laborCost': 500.0,
        'partsCost': 3500.0,
        'discountAmount': 0.0,
        'taxAmount': 18.0,
        'totalAmount': 4000.0,
        'notificationSent': false,
        'reopenCount': 0,
        'shopId': shopId,
        'demo': true,
        'timeline': [
          {
            'status': 'Job Created',
            'time': DateTime.now().toIso8601String(),
            'by': 'System',
            'type': 'flow',
            'note': 'Demo job seeded'
          }
        ]
      };

      await db.ref().update(updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Demo data seeded for $shopId',
            style: GoogleFonts.syne(fontWeight: FontWeight.w700),
          ),
          backgroundColor: C.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final session = ref.read(currentUserProvider).asData?.value;
      final shopId = session?.shopId ?? '';
      if (shopId.isEmpty) return;
      final db = FirebaseDatabase.instance;

      final custSnap = await db.ref('customers')
          .orderByChild('shopId')
          .equalTo(shopId)
          .get();
      for (final c in custSnap.children) {
        final v = c.value;
        if (v is Map && v['demo'] == true) {
          await c.ref.remove();
        }
      }

      final prodSnap = await db.ref('products')
          .orderByChild('shopId')
          .equalTo(shopId)
          .get();
      for (final p in prodSnap.children) {
        final v = p.value;
        if (v is Map && v['demo'] == true) {
          await p.ref.remove();
        }
      }

      final jobSnap = await db.ref('jobs')
          .orderByChild('shopId')
          .equalTo(shopId)
          .get();
      for (final j in jobSnap.children) {
        final v = j.value;
        if (v is Map && v['demo'] == true) {
          await j.ref.remove();
        }
      }

      await db.ref('users/demo_${shopId}_tech_1').remove();
      await db.ref('users/demo_${shopId}_reception_1').remove();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Demo data cleared for $shopId',
            style: GoogleFonts.syne(fontWeight: FontWeight.w700),
          ),
          backgroundColor: C.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          title: Text('Demo Data Tools',
              style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _infoBanner(
              'These tools are for testing only. They create or remove demo data '
              'for the current shop without affecting other shops.',
            ),
            const SizedBox(height: 16),
            SCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Seed Demo Data',
                      style: GoogleFonts.syne(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: C.white)),
                  const SizedBox(height: 6),
                  Text(
                    'Populate sample customers, jobs, products and staff for this shop.',
                    style: GoogleFonts.syne(
                        fontSize: 12, color: C.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  PBtn(
                    label: 'Seed demo data',
                    onTap: _busy ? null : _seed,
                    full: true,
                    color: C.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SCard(
              borderColor: C.red,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clear Demo Data',
                      style: GoogleFonts.syne(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: C.red)),
                  const SizedBox(height: 6),
                  Text(
                    'Remove demo customers, jobs, products and demo staff for this shop.',
                    style: GoogleFonts.syne(
                        fontSize: 12, color: C.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  PBtn(
                    label: 'Clear demo data',
                    onTap: _busy ? null : _clear,
                    full: true,
                    color: C.red,
                    outline: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

Widget _infoBanner(String text) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: C.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  GoogleFonts.syne(fontSize: 12, color: C.textMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
