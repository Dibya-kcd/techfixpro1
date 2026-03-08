import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/repair_tool.dart';
import 'theme/t.dart';
import 'data/providers.dart';
import 'widgets/w.dart';
import 'models/m.dart';
import 'screens/dash.dart';
import 'screens/repairs.dart';
import 'screens/customers.dart';
import 'screens/inventory.dart';
import 'screens/pos.dart';
import 'screens/reports.dart';
import 'screens/settings.dart';
import 'screens/repair_detail.dart';
import 'screens/staff_lock_screen.dart';
import 'data/active_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyDe-XjqOon900QGyA81CsgCgsz0_41i5pQ',
          authDomain: 'techfixv1.firebaseapp.com',
          databaseURL: 'https://techfixv1-default-rtdb.firebaseio.com',
          projectId: 'techfixv1',
          storageBucket: 'techfixv1.firebasestorage.app',
          messagingSenderId: '709235793243',
          appId: '1:709235793243:web:0d6ed7c436e01a2dec8e7e',
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
    if (!kIsWeb) {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
    }
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  runApp(const ProviderScope(child: TechFixApp()));
}

class TechFixApp extends StatelessWidget {
  const TechFixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TechFix Pro',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  String _ownerUid    = '';
  String _ownerShopId = '';
  bool   _repairDone  = false;  // ensures repair dialog only shows once

  @override
  void initState() {
    super.initState();
    _loadOwnerInfo();
  }

  /// Read owner uid from FirebaseAuth and shopId from SharedPreferences.
  /// Both are available instantly after login (no extra DB call needed here).
  Future<void> _loadOwnerInfo() async {
    try {
      final user   = FirebaseAuth.instance.currentUser;
      final prefs  = await SharedPreferences.getInstance();
      final shopId = prefs.getString('shopId') ?? '';
      final uid    = user?.uid ?? '';

      if (mounted) {
        setState(() {
          _ownerUid    = uid;
          _ownerShopId = shopId;
        });

        // Trigger staff reload now that we have a real shopId.
        // reloadIfEmpty is a no-op if staff are already in state.
        if (shopId.isNotEmpty) {
          ref.read(staffProvider.notifier).reloadIfEmpty(shopId);
        }

        // Check for incomplete onboarding — partial users/ record with no shopId.
        // Shows "Complete Setup" dialog automatically for stuck owners.
        _maybeRepair();
      }
    } catch (_) {
      // ignore load errors — app will show login screen
    }
  }

  /// Show repair dialog once if Firebase user exists but shop setup is incomplete.
  Future<void> _maybeRepair() async {
    if (_repairDone) return;
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Only run if no active session yet (not already logged in as owner/staff)
    final active = ref.read(activeSessionProvider);
    if (active != null) return;

    _repairDone = true; // prevent double-show
    final repaired = await repairIfNeeded(context, ref);
    if (repaired && mounted) {
      // repairIfNeeded already called loginAsOwner — _AuthGate will rebuild to RootShell
      debugPrint('✅ Repair complete — navigating to app');
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = ref.watch(activeSessionProvider);

    // Also react to Firebase auth changes (e.g. token refresh, new login)
    // so ownerUid/shopId stay in sync without requiring a hot restart.
    ref.listen(currentUserProvider, (_, next) {
      final session = next.asData?.value;
      if (session != null && session.shopId.isNotEmpty) {
        if (_ownerShopId != session.shopId || _ownerUid != session.uid) {
          setState(() {
            _ownerUid    = session.uid;
            _ownerShopId = session.shopId;
          });
          ref.read(staffProvider.notifier).reloadIfEmpty(session.shopId);
        }
      }
    });

    if (activeSession == null) {
      return StaffLockScreen(
        ownerUid:    _ownerUid,
        ownerShopId: _ownerShopId,
      );
    }
    return const RootShell();
  }
}

// ═══════════════════════════════════════════════════════════════
//  ROOT SHELL – bottom nav + indexed stack
// ═══════════════════════════════════════════════════════════════
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _idx = 0;
  bool _initialized = false;
  String _initializedShopId = '';
  String? _cachedShopId;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _loadCachedShop();
  }

  @override
  void dispose() {
    for (final sub in _subs) { sub.cancel(); }
    _subs.clear();
    super.dispose();
  }

  Future<void> _loadCachedShop() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('shopId');
      if (mounted) setState(() => _cachedShopId = id);
    } catch (_) {}
  }

  static const _navItems = [
    _NavItem(index: 0, icon: Icons.home_outlined,        activeIcon: Icons.home,            label: 'Home'),
    _NavItem(index: 1, icon: Icons.build_outlined,       activeIcon: Icons.build,           label: 'Repairs'),
    _NavItem(index: 2, icon: Icons.people_outline,       activeIcon: Icons.people,          label: 'Customers'),
    _NavItem(index: 4, icon: Icons.point_of_sale_outlined,activeIcon: Icons.point_of_sale, label: 'POS'),
    _NavItem(index: -1, icon: Icons.menu,                activeIcon: Icons.menu_open,       label: 'More'),
  ];

  Future<void> _initAppData(String shopId) async {
    if (_initialized && _initializedShopId == shopId) return;
    _initialized = true;
    _initializedShopId = shopId;
    try {
      final db = FirebaseDatabase.instance;

      // Real-time settings listener
      _subs.add(db.ref('shops/$shopId').onValue.listen((event) {
        if (!mounted) return;
        if (event.snapshot.exists) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          ref.read(settingsProvider.notifier).update(
            ref.read(settingsProvider).copyWith(
              shopId: shopId,
              shopName: (data['shopName'] as String?) ?? (data['name'] as String?) ?? 'TechFix Pro',
              ownerName: (data['ownerName'] as String?) ?? (data['owner'] as String?) ?? 'Admin',
              email: (data['email'] as String?) ?? '',
              phone: (data['phone'] as String?) ?? '',
              address: (data['address'] as String?) ?? '',
              gstNumber: (data['gstNumber'] as String?) ?? '',
              invoicePrefix: (data['invoicePrefix'] as String?) ?? 'INV',
              defaultTaxRate: (data['defaultTaxRate'] as num?)?.toDouble() ?? 18.0,
              darkMode: (data['darkMode'] as bool?) ?? true,
              requireIntakePhoto: (data['requireIntakePhoto'] as bool?) ?? false,
              requireCompletionPhoto: (data['requireCompletionPhoto'] as bool?) ?? false,
            )
          );
        }
      }));

      // Real-time staff listener — feeds staffProvider (ALL roles).
      _subs.add(db.ref('users')
          .orderByChild('shopId')
          .equalTo(shopId)
          .onValue.listen((event) {
        if (!mounted) return;
        final staffList = <StaffMember>[];
        if (event.snapshot.exists) {
          for (final child in event.snapshot.children) {
            final d = Map<String, dynamic>.from(child.value as Map);
            staffList.add(StaffMember(
              uid:              child.key!,
              shopId:           shopId,
              displayName:      (d['displayName'] as String?) ?? '',
              email:            (d['email']       as String?) ?? '',
              phone:            (d['phone']       as String?) ?? '',
              role:             (d['role']        as String?) ?? 'technician',
              isOwner:          (d['isOwner']     as bool?)   ?? false,
              isActive:         (d['isActive']    as bool?)   ?? true,
              biometricEnabled: (d['biometricEnabled'] as bool?) ?? false,
              specialization:   (d['specialization'] as String?) ?? 'General',
              pin:              (d['pin']         as String?) ?? '',
              pinHash:          (d['pin_hash']    as String?) ?? '',
              lastLoginAt:      (d['lastLoginAt'] as String?) ?? '',
              createdAt:        (d['createdAt']   as String?) ?? '',
              joinedAt:         (d['joinedAt']    as String?) ?? (d['createdAt'] as String?) ?? '',
              totalJobs:        (d['totalJobs']   as int?)    ?? 0,
              completedJobs:    (d['completedJobs'] as int?)  ?? 0,
              rating:           (d['rating']      as num?)?.toDouble() ?? 5.0,
            ));
          }
        }
        staffList.sort((a, b) {
          if (a.isOwner) return -1;
          if (b.isOwner) return 1;
          return a.displayName.compareTo(b.displayName);
        });
        ref.read(staffProvider.notifier).setAll(staffList);
      }));

      // Real-time products listener
      _subs.add(db.ref('products')
          .orderByChild('shopId')
          .equalTo(shopId)
          .onValue.listen((event) {
        if (!mounted) return;
        final products = <Product>[];
        if (event.snapshot.exists) {
          for (final child in event.snapshot.children) {
            final data = Map<String, dynamic>.from(child.value as Map);
            products.add(Product(
              productId: child.key!,
              shopId: shopId,
              sku: (data['sku'] as String?) ?? '',
              productName: (data['productName'] as String?) ?? (data['name'] as String?) ?? '',
              category: (data['category'] as String?) ?? (data['cat'] as String?) ?? 'Accessories',
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
        ref.read(productsProvider.notifier).setAll(products);
      }));

      // Real-time jobs listener
      _subs.add(db.ref('jobs')
          .orderByChild('shopId')
          .equalTo(shopId)
          .onValue.listen((event) {
        if (!mounted) return;
        final jobs = <Job>[];
        if (event.snapshot.exists) {
          for (final child in event.snapshot.children) {
            final data = Map<String, dynamic>.from(child.value as Map);
            jobs.add(Job.fromMap(data));
          }
          jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        ref.read(jobsProvider.notifier).setAll(jobs);
      }));

      // Real-time customers listener
      _subs.add(db.ref('customers')
          .orderByChild('shopId')
          .equalTo(shopId)
          .onValue.listen((event) {
        if (!mounted) return;
        final customers = <Customer>[];
        if (event.snapshot.exists) {
          for (final child in event.snapshot.children) {
            final data = Map<String, dynamic>.from(child.value as Map);
            customers.add(Customer.fromMap(data));
          }
        }
        ref.read(customersProvider.notifier).setAll(customers);
      }));

      // Real-time transactions listener — feeds Dashboard, Sales & Finance KPIs.
      // Was MISSING — this is why all revenue/transaction cards showed zero.
      _subs.add(db.ref('transactions')
          .orderByChild('shopId')
          .equalTo(shopId)
          .onValue.listen((event) {
        if (!mounted) return;
        final txs = <Map<String, dynamic>>[];
        if (event.snapshot.exists) {
          for (final child in event.snapshot.children) {
            final data = Map<String, dynamic>.from(child.value as Map);
            txs.add(data);
          }
          // Sort newest-first so reports see most-recent entries first
          txs.sort((a, b) {
            final at = (a['time'] as num?)?.toInt() ?? 0;
            final bt = (b['time'] as num?)?.toInt() ?? 0;
            return bt.compareTo(at);
          });
        }
        ref.read(transactionsProvider.notifier).state = txs;
      }));

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error initializing app data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync    = ref.watch(currentUserProvider);
    final session      = userAsync.asData?.value;
    ref.watch(activeSessionProvider); // watched for rebuild; role consumed per-widget

    // Kick off DB streams — re-run if shopId changes (e.g. after lock screen PIN)
    final activeSession = ref.watch(activeSessionProvider);
    final effectiveShopId = (activeSession?.shopId.isNotEmpty == true)
        ? activeSession!.shopId
        : (session?.shopId.isNotEmpty == true ? session!.shopId : (_cachedShopId ?? ''));
    if (effectiveShopId.isNotEmpty && _initializedShopId != effectiveShopId) {
      _initAppData(effectiveShopId);
    }

    final jobs = ref.watch(jobsProvider);
    final overdue = jobs.where((j) => j.isOverdue).length;
    final ready   = jobs.where((j) => j.status == 'Ready for Pickup').length;
    final onHold  = jobs.where((j) => j.isOnHold).length;
    final settings = ref.watch(settingsProvider);
     final cart = ref.watch(cartProvider);
    final cartCount = cart.fold<int>(0, (s, c) => s + c.qty);

    // Build screens – use callbacks so DashScreen can switch tabs
    final screens = <Widget>[
      DashScreen(
        onRepairs: () => setState(() => _idx = 1),
        onInventory: () => setState(() => _idx = 3),
        onOpenJob: (jobId) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RepairDetailScreen(jobId: jobId),
            ),
          );
        },
      ),
      const RepairsScreen(),
      const CustomersScreen(),
      const InventoryScreen(),
      const POSScreen(),
      const ReportsScreen(),
      const SettingsScreen(),
    ];

    final shopName = settings.shopName.isEmpty ? 'TechFix Pro' : settings.shopName;
    final appBarTitle = switch (_idx) {
      0 => shopName,
      1 => 'Repairs',
      2 => 'Customers',
      3 => 'Inventory',
      4 => 'POS',
      5 => 'Reports',
      6 => 'Settings',
      _ => shopName,
    };

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bgElevated,
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [C.primary, C.primaryDark],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('T', style: GoogleFonts.syne(
                  fontWeight: FontWeight.w900, fontSize: 18, color: C.bg)),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              appBarTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.syne(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
        ]),
        actions: [
          // Overdue badge
          if (overdue > 0)
            _AppBarBadge(icon: '⏰', count: overdue, color: C.red,
                onTap: () {
                  setState(() => _idx = 1);
                  ref.read(jobTabProvider.notifier).state = 'Active';
                }),
          // On Hold badge
          if (onHold > 0)
            _AppBarBadge(icon: '⏸️', count: onHold, color: C.yellow,
                onTap: () {
                  setState(() => _idx = 1);
                  ref.read(jobTabProvider.notifier).state = 'On Hold';
                }),
          // Ready for pickup badge
          if (ready > 0)
            _AppBarBadge(icon: '✅', count: ready, color: C.green,
                onTap: () {
                  setState(() => _idx = 1);
                  ref.read(jobTabProvider.notifier).state = 'Ready';
                }),
          if (_idx == 4)
            _CartAction(
              count: cartCount,
              onTap: () => _openCart(cart),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _idx, children: screens),
      bottomNavigationBar: _buildBottomNav(),
      endDrawer: _CartDrawer(onGoToPos: _goToPosFromCart),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: C.bgElevated,
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _navItems.map((item) {
              final sel = item.index >= 0
                  ? _idx == item.index
                  : _idx == 3 || _idx == 5 || _idx == 6;
              return GestureDetector(
                onTap: () {
                  if (item.index >= 0) {
                    setState(() => _idx = item.index);
                  } else {
                    _openMoreSheet();
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? C.primary.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(sel ? item.activeIcon : item.icon,
                        color: sel ? C.primary : C.textDim,
                        size: 22),
                    const SizedBox(height: 3),
                    Text(item.label, style: GoogleFonts.syne(
                        fontSize: 9,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                        color: sel ? C.primary : C.textDim,
                        letterSpacing: 0.2)),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
  
  void _openMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.bgElevated,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined, color: C.text),
              title: const Text('Stock'),
              onTap: () { setState(() => _idx = 3); Navigator.of(ctx).pop(); },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined, color: C.text),
              title: const Text('Reports'),
              onTap: () { setState(() => _idx = 5); Navigator.of(ctx).pop(); },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: C.text),
              title: const Text('Settings'),
              onTap: () { setState(() => _idx = 6); Navigator.of(ctx).pop(); },
            ),
            const Divider(color: C.border, height: 1),
            // Role logout is in Settings → Sign Out (logs out of role only).
            // Firebase sign out is in the hidden admin screen (5-tap logo).
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: C.textMuted),
              title: Text('Sign out of role',
                  style: GoogleFonts.syne(color: C.textMuted)),
              subtitle: Text('Go to Settings → Sign Out',
                  style: GoogleFonts.syne(fontSize: 11, color: C.textDim)),
              onTap: () {
                Navigator.of(ctx).pop();
                setState(() => _idx = 6); // open Settings
              },
            ),
          ],
        ),
      ),
    );
  }

  void _goToPosFromCart() {
    Navigator.of(context).maybePop();
    setState(() => _idx = 4);
  }

  void _openCart(List<CartItem> cart) {
    final width = MediaQuery.of(context).size.width;
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cart is empty', style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.bgElevated,
        ),
      );
      return;
    }
    if (width < 700) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CartSheet(onGoToPos: _goToPosFromCart),
      );
    } else {
      Scaffold.of(context).openEndDrawer();
    }
  }
}

class _NavItem {
  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.index, required this.icon, required this.activeIcon, required this.label});
}

// ── App bar badge widget ───────────────────────────────────────
class _AppBarBadge extends StatelessWidget {
  final String icon;
  final int count;
  final Color color;
  final VoidCallback onTap;
  const _AppBarBadge({required this.icon, required this.count,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text('$count', style: GoogleFonts.syne(
            fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      ]),
    ),
  );
}

class _CartAction extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _CartAction({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasItems = count > 0;
    return Semantics(
      label: hasItems ? 'Cart, $count item(s)' : 'Cart, empty',
      button: true,
      child: IconButton(
        onPressed: onTap,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.shopping_cart_outlined, color: C.textDim),
            if (hasItems)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: C.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Center(
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: GoogleFonts.syne(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: C.bg,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartDrawer extends ConsumerWidget {
  final VoidCallback onGoToPos;
  const _CartDrawer({required this.onGoToPos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final total = cart.fold<double>(0, (s, c) => s + c.product.sellingPrice * c.qty);
    return Drawer(
      backgroundColor: C.bgElevated,
      child: SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cart', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
                      IconButton(
                        icon: const Icon(Icons.close, color: C.textDim),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (cart.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'Your cart is empty',
                          style: GoogleFonts.syne(fontSize: 13, color: C.textMuted),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: cart.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = cart[i];
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: C.bgCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: C.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.product.productName,
                                        style: GoogleFonts.syne(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: C.text,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${fmtMoney(item.product.sellingPrice)} each',
                                        style: GoogleFonts.syne(fontSize: 11, color: C.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        ref.read(cartProvider.notifier).setQty(
                                          item.product.productId,
                                          item.qty - 1,
                                        );
                                      },
                                      icon: const Icon(Icons.remove, size: 18, color: C.textDim),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Text(
                                        '${item.qty}',
                                        style: GoogleFonts.syne(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: C.white,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => ref.read(cartProvider.notifier).updateQty(item.product.productId, item.qty + 1),
                                      icon: const Icon(Icons.add, size: 18, color: C.textDim),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  fmtMoney(item.product.sellingPrice * item.qty),
                                  style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700, color: C.primary),
                                ),
                                IconButton(
                                  onPressed: () {
                                    ref.read(cartProvider.notifier).setQty(item.product.productId, 0);
                                  },
                                  icon: const Icon(Icons.close, size: 18, color: C.textDim),
                                  padding: const EdgeInsets.only(left: 4),
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  if (cart.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: GoogleFonts.syne(fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
                        Text(fmtMoney(total), style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.w800, color: C.green)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PBtn(
                      label: 'Go to POS',
                      onTap: onGoToPos,
                      full: true,
                      color: C.primary,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: C.bgElevated,
                            title: Text(
                              'Clear cart?',
                              style: GoogleFonts.syne(
                                fontWeight: FontWeight.w800,
                                color: C.white,
                              ),
                            ),
                            content: Text(
                              'This will remove all items from the cart.',
                              style: GoogleFonts.syne(color: C.textMuted, fontSize: 13),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.syne(color: C.textMuted),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: Text(
                                  'Clear',
                                  style: GoogleFonts.syne(color: C.red, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          ref.read(cartProvider.notifier).clear();
                        }
                      },
                      child: Text(
                        'Clear cart',
                        style: GoogleFonts.syne(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: C.textMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CartSheet extends ConsumerWidget {
  final VoidCallback onGoToPos;
  const _CartSheet({required this.onGoToPos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final total = cart.fold<double>(0, (s, c) => s + c.product.sellingPrice * c.qty);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: C.bgElevated,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.border),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cart', style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.w800, color: C.white)),
                  IconButton(
                    icon: const Icon(Icons.close, color: C.textDim),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (cart.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Your cart is empty',
                    style: GoogleFonts.syne(fontSize: 13, color: C.textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = cart[i];
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.product.productName,
                                  style: GoogleFonts.syne(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: C.text,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${fmtMoney(item.product.sellingPrice)} each',
                                  style: GoogleFonts.syne(fontSize: 11, color: C.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  ref.read(cartProvider.notifier).setQty(
                                    item.product.productId,
                                    item.qty - 1,
                                  );
                                },
                                icon: const Icon(Icons.remove, size: 18, color: C.textDim),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  '${item.qty}',
                                  style: GoogleFonts.syne(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: C.white,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  ref.read(cartProvider.notifier).setQty(
                                    item.product.productId,
                                    item.qty + 1,
                                  );
                                },
                                icon: const Icon(Icons.add, size: 18, color: C.textDim),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Text(
                            fmtMoney(item.product.sellingPrice * item.qty),
                            style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700, color: C.primary),
                          ),
                          IconButton(
                            onPressed: () {
                              ref.read(cartProvider.notifier).setQty(item.product.productId, 0);
                            },
                            icon: const Icon(Icons.close, size: 18, color: C.textDim),
                            padding: const EdgeInsets.only(left: 4),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              if (cart.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: GoogleFonts.syne(fontSize: 14, fontWeight: FontWeight.w700, color: C.text)),
                    Text(fmtMoney(total), style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.w800, color: C.green)),
                  ],
                ),
                const SizedBox(height: 12),
                PBtn(
                  label: 'Go to POS',
                  onTap: onGoToPos,
                  full: true,
                  color: C.primary,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: C.bgElevated,
                        title: Text(
                          'Clear cart?',
                          style: GoogleFonts.syne(
                            fontWeight: FontWeight.w800,
                            color: C.white,
                          ),
                        ),
                        content: Text(
                          'This will remove all items from the cart.',
                          style: GoogleFonts.syne(color: C.textMuted, fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.syne(color: C.textMuted),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text(
                              'Clear',
                              style: GoogleFonts.syne(color: C.red, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      ref.read(cartProvider.notifier).clear();
                    }
                  },
                  child: Text(
                    'Clear cart',
                    style: GoogleFonts.syne(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: C.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
