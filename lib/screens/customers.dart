import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/providers.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import 'cust_form.dart';
import 'add_repair.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustState();
}

class _CustState extends ConsumerState<CustomersScreen> {
  String? _tierFilter;
  bool _synced = false;
  bool _syncing = false;
  String? _syncError;

  Future<void> _syncFromFirebase(String shopId) async {
    try {
      final db = FirebaseDatabase.instance;
      final snap = await db.ref('customers')
          .orderByChild('shopId')
          .equalTo(shopId)
          .get();
      final list = <Customer>[];
      if (snap.exists && snap.children.isNotEmpty) {
        for (final child in snap.children) {
          final key = child.key;
          final value = child.value;
          if (key == null || value is! Map) continue;
          final data = Map<String, dynamic>.from(value);
          list.add(Customer(
            customerId: key,
            name: (data['name'] as String?) ?? '',
            phone: (data['phone'] as String?) ?? '',
            email: (data['email'] as String?) ?? '',
            address: (data['address'] as String?) ?? '',
            tier: (data['tier'] as String?) ?? 'Bronze',
            points: (data['points'] as int?) ?? 0,
            repairsCount: (data['repairsCount'] as int?) ?? 0,
            totalSpend: (data['totalSpend'] as num?)?.toDouble() ?? 0,
            isVip: (data['isVip'] as bool?) ?? false,
            isBlacklisted: (data['isBlacklisted'] as bool?) ?? false,
            shopId: (data['shopId'] as String?) ?? shopId,
            createdAt: (data['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
            updatedAt: (data['updatedAt'] as String?) ?? DateTime.now().toIso8601String(),
          ));
        }
      }
      ref.read(customersProvider.notifier).setAll(list);
      if (mounted) {
        setState(() {
          _syncError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncError = 'Failed to sync customers from cloud: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final jobs = ref.watch(jobsProvider);
    final search = ref.watch(searchCustProvider);
    final sessionAsync = ref.watch(currentUserProvider);
    final session = sessionAsync.asData?.value;
    final isSuperAdmin = session?.role == 'super_admin';

    if (!_synced && !_syncing && session != null && session.shopId.isNotEmpty) {
      _syncing = true;
      _syncFromFirebase(session.shopId).whenComplete(() {
        if (mounted) {
          setState(() {
            _synced = true;
            _syncing = false;
          });
        }
      });
    }

    final filtered = customers.where((c) {
      final s = search.toLowerCase();
      final ms = s.isEmpty || c.name.toLowerCase().contains(s)
          || c.phone.contains(s) || c.email.toLowerCase().contains(s);
      final mt = _tierFilter == null || c.tier == _tierFilter;
      return ms && mt;
    }).toList();

    assert(() {
      debugPrint(
        '[CustomersScreen] search="$search" tier=$_tierFilter total=${customers.length} filtered=${filtered.length} jobs=${jobs.length}',
      );
      return true;
    }());

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(children: [
        // Search + filter header
        Container(
          color: C.bgElevated,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            Row(children: [
              Expanded(child: TextField(
                onChanged: (v) => ref.read(searchCustProvider.notifier).state = v,
                style: GoogleFonts.syne(fontSize: 13, color: C.text),
                decoration: const InputDecoration(
                  hintText: 'Search name, phone, email...',
                  prefixIcon: Icon(Icons.search, color: C.textMuted, size: 20),
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              )),
              const SizedBox(width: 10),
              PopupMenuButton<String?>(
                color: C.bgElevated,
                initialValue: _tierFilter,
                onSelected: (v) => setState(() => _tierFilter = v),
                icon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _tierFilter != null ? C.primary.withValues(alpha: 0.2) : C.bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _tierFilter != null ? C.primary : C.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.filter_list, size: 16,
                        color: _tierFilter != null ? C.primary : C.textMuted),
                    const SizedBox(width: 4),
                    Text(_tierFilter ?? 'Tier', style: GoogleFonts.syne(fontSize: 12,
                        color: _tierFilter != null ? C.primary : C.textMuted,
                        fontWeight: FontWeight.w700)),
                  ]),
                ),
                itemBuilder: (_) => [
                  PopupMenuItem(value: null, child: Text('All Tiers',
                      style: GoogleFonts.syne(color: C.text))),
                  ...['Bronze', 'Silver', 'Gold', 'Platinum'].map((t) => PopupMenuItem(
                    value: t,
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(
                          color: C.tierColor(t), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(t, style: GoogleFonts.syne(color: C.tierColor(t),
                          fontWeight: FontWeight.w700)),
                    ]),
                  )),
                ],
              ),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${filtered.length} customer${filtered.length == 1 ? "" : "s"}',
                  style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: ['Gold', 'Platinum'].map((t) {
                  final cnt = customers.where((c) => c.tier == t).length;
                  if (cnt == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Pill('$cnt $t', color: C.tierColor(t), small: true),
                  );
                }).toList()),
              ),
            ]),
            if (_syncError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: C.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _syncError!,
                          style: GoogleFonts.syne(
                              fontSize: 11, color: C.red),
                        ),
                      ),
                      if (!_syncing && session?.shopId.isNotEmpty == true)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _synced = false;
                            });
                          },
                          child: Text(
                            'Retry',
                            style: GoogleFonts.syne(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: C.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (isSuperAdmin && customers.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final shopId = session?.shopId ?? '';
                    if (shopId.isEmpty) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final db = FirebaseDatabase.instance;
                    for (final c in customers) {
                      await db.ref('customers/${c.customerId}').set({
                        'name': c.name,
                        'phone': c.phone,
                        'email': c.email,
                        'address': c.address,
                        'tier': c.tier,
                        'isVip': c.isVip,
                        'isBlacklisted': c.isBlacklisted,
                        'points': c.points,
                        'repairsCount': c.repairsCount,
                        'totalSpend': c.totalSpend,
                        'shopId': shopId,
                        'createdAt': c.createdAt,
                        'updatedAt': DateTime.now().toIso8601String(),
                      });
                    }
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Customers migrated to cloud for $shopId',
                            style: GoogleFonts.syne(
                                fontWeight: FontWeight.w700),
                          ),
                          backgroundColor: C.green,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                      setState(() {
                        _synced = false;
                      });
                    }
                  },
                  child: Text(
                    'Migrate customers to cloud',
                    style: GoogleFonts.syne(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: C.primary,
                    ),
                  ),
                ),
              ),
          ]),
        ),

        Expanded(
          child: filtered.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('👤', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text('No customers found', style: GoogleFonts.syne(fontSize: 16,
                      fontWeight: FontWeight.w700, color: C.textMuted)),
                  const SizedBox(height: 8),
                  PBtn(label: '+ Add Customer', onTap: () => _openForm(context),
                      small: true),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final tc = C.tierColor(c.tier);
                    final custJobs = jobs.where((j) => j.customerId == c.customerId).toList();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SCard(
                        onTap: () => _showDetail(context, c, custJobs),
                        child: Row(children: [
                          Stack(clipBehavior: Clip.none, children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: C.primary.withValues(alpha: 0.2),
                              child: Text(c.name[0], style: GoogleFonts.syne(
                                  fontWeight: FontWeight.w800, color: C.primary, fontSize: 16)),
                            ),
                            if (c.isVip) const Positioned(bottom: -2, right: -4,
                                child: Text('👑', style: TextStyle(fontSize: 14))),
                          ]),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(c.name, style: GoogleFonts.syne(
                                  fontWeight: FontWeight.w700, fontSize: 15, color: C.white),
                                  overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 6),
                              Pill(c.tier, color: tc, small: true),
                            ]),
                            const SizedBox(height: 2),
                            Text(c.phone, style: GoogleFonts.syne(fontSize: 13, color: C.textMuted)),
                            const SizedBox(height: 6),
                            Row(children: [
                              _stat('🔧', '${custJobs.length} repairs'),
                              const SizedBox(width: 12),
                              _stat('💰', '₹${(c.totalSpend / 1000).toStringAsFixed(1)}k'),
                              const SizedBox(width: 12),
                              _stat('⭐', '${c.points} pts'),
                            ]),
                          ])),
                          const Icon(Icons.chevron_right, color: C.textDim),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_customers',
        onPressed: () => _openForm(context),
        backgroundColor: C.primary,
        foregroundColor: C.bg,
        icon: const Icon(Icons.person_add),
        label: Text('Add Customer', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _stat(String icon, String val) => Row(children: [
    Text(icon, style: const TextStyle(fontSize: 12)),
    const SizedBox(width: 3),
    Text(val, style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
  ]);

  void _openForm(BuildContext context, [Customer? c]) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CustomerFormScreen(customer: c)));

  void _showDetail(BuildContext context, Customer cust, List<Job> custJobs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.95,
      ),
      builder: (_) => _CustomerDetailSheet(
        cust: cust,
        custJobs: custJobs,
        onEdit: () {
          Navigator.of(context).pop();
          _openForm(context, cust);
        },
        onNewJob: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AddRepairScreen(preselectedCustomer: cust)));
        },
      ),
    );
  }
}

// ─── Customer Detail Bottom Sheet ─────────────────────────────
class _CustomerDetailSheet extends StatelessWidget {
  final Customer cust;
  final List<Job> custJobs;
  final VoidCallback onEdit;
  final VoidCallback onNewJob;
  const _CustomerDetailSheet({required this.cust, required this.custJobs,
      required this.onEdit, required this.onNewJob});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,   // ← critical: tells sheet it is inside showModalBottomSheet
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: C.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(controller: ctrl,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: C.border,
                    borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 12),

            // Header gradient card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A5F), Color(0xFF0099CC)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                Stack(alignment: Alignment.center, children: [
                  CircleAvatar(radius: 32, backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: Text(cust.name[0],
                          style: GoogleFonts.syne(fontWeight: FontWeight.w800,
                              fontSize: 26, color: Colors.white))),
                  if (cust.isVip) const Positioned(bottom: 0, right: 0,
                      child: Text('👑', style: TextStyle(fontSize: 18))),
                ]),
                const SizedBox(height: 10),
                Text(cust.name, style: GoogleFonts.syne(fontWeight: FontWeight.w800,
                    fontSize: 20, color: Colors.white)),
                Text(cust.phone, style: GoogleFonts.syne(fontSize: 14, color: Colors.white70)),
                if (cust.email.isNotEmpty)
                  Text(cust.email, style: GoogleFonts.syne(fontSize: 12, color: Colors.white54)),
                if (cust.address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('📍 ${cust.address}',
                        style: GoogleFonts.syne(fontSize: 11, color: Colors.white54),
                        textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Pill(cust.tier, color: C.tierColor(cust.tier)),
                  if (cust.isVip) ...[const SizedBox(width: 8), const Pill('VIP', color: C.yellow)],
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            // Stats
            Row(children: [
              Expanded(child: _statCard('👑', cust.tier, 'Tier', C.tierColor(cust.tier))),
              const SizedBox(width: 8),
              Expanded(child: _statCard('💰',
                  cust.totalSpend > 0 ? '₹${(cust.totalSpend / 1000).toStringAsFixed(1)}k' : '₹0',
                  'Spent', C.green)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('⭐', '${cust.points}', 'Points', C.yellow)),
            ]),
            const SizedBox(height: 16),

            // Quick actions
            Row(children: [
              Expanded(child: PBtn(
                  label: '✏️ Edit', onTap: onEdit, outline: true, full: true, color: C.primary)),
              const SizedBox(width: 10),
              Expanded(child: PBtn(
                  label: '🔧 New Job', onTap: onNewJob, full: true, color: C.green)),
            ]),
            const SizedBox(height: 16),

            // Repair history
            SCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🔧 Repair History (${custJobs.length})',
                  style: GoogleFonts.syne(fontWeight: FontWeight.w700,
                      fontSize: 14, color: C.white)),
              const SizedBox(height: 10),
              if (custJobs.isEmpty)
                Center(child: Column(children: [
                  const Text('📭', style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 6),
                  Text('No repairs yet', style: GoogleFonts.syne(
                      fontSize: 13, color: C.textDim)),
                ]))
              else ...custJobs.map((j) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: C.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: C.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: C.statusColor(j.status),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(10),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(children: [
                            Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${j.brand} ${j.model}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.syne(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: C.text)),
                                  Text('${j.jobNumber} · ${j.createdAt.split('T')[0]}', style: GoogleFonts.syne(
                                      fontSize: 11, color: C.textMuted)),
                                ])),
                            // ConstrainedBox: long status pill never overflows on SE
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 110),
                              child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Pill('${C.statusIcon(j.status)} ${j.status}',
                                    color: C.statusColor(j.status), small: true),
                                const SizedBox(height: 4),
                                Text(fmtMoney(j.totalAmount), style: GoogleFonts.syne(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: C.primary)),
                              ],
                            ),
                            ),  // end ConstrainedBox
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String icon, String val, String label, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: C.bgCard, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.border)),
    child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 4),
      Text(val, style: GoogleFonts.syne(fontWeight: FontWeight.w800,
          fontSize: 14, color: color)),
      Text(label, style: GoogleFonts.syne(fontSize: 10, color: C.textMuted)),
    ]),
  );
}
