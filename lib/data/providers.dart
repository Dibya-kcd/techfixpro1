import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:flutter_riverpod/legacy.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/m.dart';
import 'active_session.dart';
import 'seed.dart';

String _ts() {
  final n = DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${p(n.month)}-${p(n.day)} ${p(n.hour)}:${p(n.minute)}';
}

// ─────────────────────────────────────────────────────────────────────────────
//  SESSION
// ─────────────────────────────────────────────────────────────────────────────

final currentUserProvider = StreamProvider<SessionUser?>((ref) {
  return FirebaseAuth.instance.authStateChanges().asyncMap((firebaseUser) async {
    if (firebaseUser == null) return null;

    // Retry up to 5x with 800ms delay — handles race where auth fires before
    // onboarding DB write of users/$uid completes (shows wrong 'technician' role)
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        final snap = await FirebaseDatabase.instance
            .ref('users/${firebaseUser.uid}').get();
        if (snap.exists && snap.value is Map) {
          final d = Map<String, dynamic>.from(snap.value as Map);
          // Only write lastLoginAt if the record is COMPLETE (has shopId).
          // A partial record (only lastLoginAt) is created during registration
          // before onboarding finishes — writing here would poison the
          // !data.exists() rule check in seed.dart Step 2.
          final hasShopId = (d['shopId'] as String?)?.isNotEmpty == true;
          if (hasShopId) {
            FirebaseDatabase.instance
                .ref('users/${firebaseUser.uid}/lastLoginAt')
                .set(_ts())
                .catchError((_) {});
          }
          return SessionUser(
            uid:              firebaseUser.uid,
            email:            (d['email']       as String?) ?? firebaseUser.email ?? '',
            displayName:      (d['displayName'] as String?) ?? firebaseUser.displayName ?? 'User',
            role:             (d['role']        as String?) ?? 'technician',
            shopId:           (d['shopId']      as String?) ?? '',
            phone:            (d['phone']       as String?) ?? '',
            pinHash:          (d['pin_hash']    as String?) ?? '',
            biometricEnabled: (d['biometricEnabled'] as bool?) ?? false,
            isActive:         (d['isActive']    as bool?) ?? true,
            isOwner:          (d['isOwner']     as bool?) ?? false,
            lastLoginAt:      (d['lastLoginAt'] as String?) ?? '',
            createdAt:        (d['createdAt']   as String?) ?? '',
          );
        }
        debugPrint('⏳ users/${firebaseUser.uid} not ready, retry ${attempt + 1}/5');
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        debugPrint('⚠️ currentUserProvider attempt ${attempt + 1}: $e');
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    // ── Auto-resume interrupted registration ──────────────────────────────
    // users/{uid} missing after 5 retries — check if registrations/{uid}
    // exists and complete the setup automatically.
    debugPrint('⚠️ currentUserProvider: users/${firebaseUser.uid} missing — checking registrations/');
    try {
      final regSnap = await FirebaseDatabase.instance
          .ref('registrations/${firebaseUser.uid}').get();
      if (regSnap.exists && regSnap.value is Map) {
        final reg = Map<String, dynamic>.from(regSnap.value as Map);
        final shopId    = (reg['shopId']    as String?) ?? '';
        final shopName  = (reg['shopName']  as String?) ?? '';
        final plan      = (reg['plan']      as String?) ?? 'free';
        // Read all available fields from registrations/ so the shop doc
        // is pre-filled with real data, not empty defaults
        final regPhone  = (reg['phone']     as String?) ?? '';
        final regName   = (reg['ownerName'] as String?)
            ?? firebaseUser.displayName
            ?? firebaseUser.email!.split('@').first;
        if (shopId.isNotEmpty) {
          debugPrint('🔄 Auto-resuming setup for \${firebaseUser.uid} / \$shopId');
          await ShopOnboarding.resumeSetup(
            shopId:     shopId,
            ownerUid:   firebaseUser.uid,
            ownerName:  regName,
            ownerEmail: firebaseUser.email ?? '',
            ownerPhone: regPhone,
            shopName:   shopName,
            plan:       plan,
          );
          // Re-read the now-created users/ record
          final snap2 = await FirebaseDatabase.instance
              .ref('users/${firebaseUser.uid}').get();
          if (snap2.exists && snap2.value is Map) {
            final d = Map<String, dynamic>.from(snap2.value as Map);
            debugPrint('✅ Auto-resume complete for ${firebaseUser.uid}');
            FirebaseDatabase.instance
                .ref('users/${firebaseUser.uid}/lastLoginAt')
                .set(_ts())
                .catchError((_) {});
            return SessionUser(
              uid:              firebaseUser.uid,
              email:            (d['email']       as String?) ?? firebaseUser.email ?? '',
              displayName:      (d['displayName'] as String?) ?? firebaseUser.displayName ?? 'User',
              role:             (d['role']        as String?) ?? 'admin',
              shopId:           (d['shopId']      as String?) ?? shopId,
              phone:            (d['phone']       as String?) ?? '',
              pinHash:          (d['pin_hash']    as String?) ?? '',
              biometricEnabled: (d['biometricEnabled'] as bool?) ?? false,
              isActive:         (d['isActive']    as bool?) ?? true,
              isOwner:          (d['isOwner']     as bool?) ?? true,
              lastLoginAt:      (d['lastLoginAt'] as String?) ?? '',
              createdAt:        (d['createdAt']   as String?) ?? '',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Auto-resume failed: $e');
    }

    // True fallback — no registration record found either
    debugPrint('⚠️ currentUserProvider: using fallback for ${firebaseUser.uid}');
    return SessionUser(
      uid: firebaseUser.uid, email: firebaseUser.email ?? '',
      displayName: firebaseUser.displayName ?? 'User',
      role: 'technician', shopId: '', isActive: true, isOwner: false, createdAt: '',
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
//  SHOP SETTINGS
// ─────────────────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<ShopSettings> {
  SettingsNotifier() : super(ShopSettings());

  void update(ShopSettings s) => state = s;
  void reset() => state = ShopSettings();  // clears to defaults on sign-out

  Future<void> loadFromFirebase(String shopId) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('shops/$shopId').get();
      if (!snap.exists || snap.value is! Map) return;
      final d = Map<String, dynamic>.from(snap.value as Map);

      state = state.copyWith(
        shopId:                 shopId,
        shopName:               d['shopName']    as String? ?? state.shopName,
        ownerUid:               d['ownerUid']    as String? ?? state.ownerUid,
        ownerName:              d['ownerName']   as String? ?? state.ownerName,
        ownerEmail:             d['ownerEmail']  as String? ?? state.ownerEmail,
        phone:                  d['phone']       as String? ?? state.phone,
        email:                  d['email']       as String? ?? state.email,
        address:                d['address']     as String? ?? state.address,
        gstNumber:              d['gstNumber']   as String? ?? state.gstNumber,
        logoUrl:                d['logoUrl']     as String? ?? state.logoUrl,
        invoicePrefix:          d['invoicePrefix'] as String? ?? state.invoicePrefix,
        defaultTaxRate:        (d['defaultTaxRate'] as num?)?.toDouble() ?? state.defaultTaxRate,
        defaultWarrantyDays:    d['defaultWarrantyDays'] as int?
                             ?? d['warrantyDays']        as int?
                             ?? state.defaultWarrantyDays,
        requireIntakePhoto:     d['requireIntakePhoto']    as bool? ?? state.requireIntakePhoto,
        requireCompletionPhoto: d['requireCompletionPhoto'] as bool? ?? state.requireCompletionPhoto,
        // settings map: restore taxType, priceInclusive etc.
        settings: () {
          final base = d['settings'] != null
              ? Map<String, dynamic>.from(d['settings'] as Map)
              : Map<String, dynamic>.from(state.settings);
          return base;
        }(),
        createdAt:              d['createdAt'] as String? ?? state.createdAt,
        plan:                   d['plan']      as String? ?? state.plan,
        planExpiresAt:          d['planExpiresAt'] as String?,
        // Always read isActive from DB — if missing default true
        isActive:               d['isActive']  as bool? ?? true,
        darkMode:               d['darkMode']  as bool? ?? state.darkMode,
        enabledPayments:        d['enabledPayments'] != null
                                ? List<String>.from(d['enabledPayments'] as List)
                                : state.enabledPayments,
        workflowStages:         d['workflowStages'] != null
                                ? (d['workflowStages'] as List)
                                    .map((e) => Map<String, String>.from(e as Map))
                                    .toList()
                                : state.workflowStages,
      );
    } catch (e) {
      debugPrint('⚠️ loadFromFirebase error: $e');
    }
  }

  Future<void> saveToFirebase(String shopId) async {
    // ── Pre-flight: isActive MUST exist in DB — cannot be fixed from client ──
    // The shops write rule requires data.child('isActive').val() == true
    // on the EXISTING document. If missing, ALL writes fail including a write
    // to isActive itself. Fix: Firebase Console → shops/$shopId → isActive = true
    try {
      final snap = await FirebaseDatabase.instance
          .ref('shops/$shopId/isActive').get();
      if (!snap.exists || snap.value != true) {
        throw Exception(
          'shops/$shopId is missing isActive=true.\n'
          'Fix in Firebase Console:\n'
          '  Realtime Database → Data → shops → $shopId\n'
          '  Hover → (+) → name: isActive  type: Boolean  value: true',
        );
      }
    } catch (e) { if (e is Exception) rethrow; }

    try {
      final s = state;
      // Persist taxType & priceInclusive in settings map (no model field needed)
      final settingsMap = Map<String, dynamic>.from(s.settings)
        ..['taxType']        = s.settings['taxType']        ?? 'GST'
        ..['priceInclusive'] = s.settings['priceInclusive'] ?? false;

      await FirebaseDatabase.instance.ref('shops/$shopId').update({
        'shopName':               s.shopName,
        'ownerName':              s.ownerName,
        'ownerEmail':             s.ownerEmail,
        'phone':                  s.phone,
        'email':                  s.email,
        'address':                s.address,
        'gstNumber':              s.gstNumber,
        'logoUrl':                s.logoUrl,
        'invoicePrefix':          s.invoicePrefix,
        'defaultTaxRate':         s.defaultTaxRate,
        'defaultWarrantyDays':    s.defaultWarrantyDays,
        'requireIntakePhoto':     s.requireIntakePhoto,
        'requireCompletionPhoto': s.requireCompletionPhoto,
        'settings':               settingsMap,
        'plan':                   s.plan,
        'isActive':               true,   // always true — see note above
        'darkMode':               s.darkMode,
        'enabledPayments':        s.enabledPayments,
        'workflowStages':         s.workflowStages,
      });
      debugPrint('✅ Settings saved to shops/$shopId');
    } catch (e) {
      debugPrint('❌ saveToFirebase error: $e');
      rethrow;
    }
  }

  void toggle(String field) {
    switch (field) {
      case 'requireIntakePhoto':
        state = state.copyWith(requireIntakePhoto: !state.requireIntakePhoto);
        break;
      case 'requireCompletionPhoto':
        state = state.copyWith(requireCompletionPhoto: !state.requireCompletionPhoto);
        break;
      case 'darkMode':
        state = state.copyWith(darkMode: !state.darkMode);
        break;
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, ShopSettings>((_) => SettingsNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  STAFF  (single source of truth — users/ node only)
//
//  ARCHITECTURE: staff/ and technicians/ nodes are removed.
//  All fields now live in users/$uid including:
//    totalJobs, completedJobs, rating, joinedAt
// ─────────────────────────────────────────────────────────────────────────────

class StaffNotifier extends StateNotifier<List<StaffMember>> {
  StaffNotifier() : super([]);

  void setAll(List<StaffMember> list) => state = list;
  void add(StaffMember s) => state = [s, ...state];
  void update(StaffMember updated) =>
      state = state.map((s) => s.uid == updated.uid ? updated : s).toList();

  Future<void> loadFromFirebase(String shopId) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final snap = await FirebaseDatabase.instance
            .ref('users').orderByChild('shopId').equalTo(shopId).get();
        if (!snap.exists || snap.value is! Map) {
          debugPrint('⚠️ StaffNotifier: no users for shopId=$shopId (attempt ${attempt+1})');
          if (attempt < 2) { await Future.delayed(const Duration(milliseconds: 600)); continue; }
          return;
        }
        final map = Map<String, dynamic>.from(snap.value as Map);
        final loaded = <StaffMember>[];
        for (final e in map.entries) {
          try {
            final d = Map<String, dynamic>.from(e.value as Map);
            d['uid'] = e.key; // always inject uid from node key
            loaded.add(StaffMember.fromMap(e.key, d));
          } catch (parseErr) {
            debugPrint('⚠️ StaffMember parse error for ${e.key}: $parseErr');
          }
        }
        state = loaded
          ..sort((a, b) {
            if (a.isOwner) return -1;
            if (b.isOwner) return 1;
            return a.displayName.compareTo(b.displayName);
          });
        debugPrint('✅ StaffNotifier: loaded ${state.length} members for $shopId');
        return;
      } catch (e) {
        debugPrint('⚠️ StaffNotifier.loadFromFirebase attempt ${attempt+1}: $e');
        if (attempt < 2) await Future.delayed(const Duration(milliseconds: 600));
      }
    }
  }

  Future<void> reloadIfEmpty(String shopId) async {
    if (state.isEmpty) await loadFromFirebase(shopId);
  }

  Future<void> addToFirebase({
    required String uid, required String shopId,
    required String displayName, required String email,
    required String phone, required String role, required String pin,
    String specialization = 'General',
  }) async {
    try {
      final db = FirebaseDatabase.instance;
      final now = DateTime.now().toIso8601String();
      final member = StaffMember(
        uid: uid, shopId: shopId, displayName: displayName,
        email: email, phone: phone, role: role, isOwner: false,
        pin: pin, specialization: specialization, createdAt: now,
      );
      // Single write — users/ only. No staff/ or technicians/ node.
      final userMap = member.toMap()
        ..['uid']           = uid
        ..['totalJobs']     = 0
        ..['completedJobs'] = 0
        ..['rating']        = 5.0
        ..['joinedAt']      = now;
      await db.ref('users/$uid').set(userMap);
      add(member);
    } catch (e) {
      debugPrint('❌ addToFirebase: $e');
      rethrow;
    }
  }

  Future<void> toggleActive(String uid, String shopId) async {
    final member = state.firstWhere((s) => s.uid == uid,
        orElse: () => throw Exception('Staff not found'));
    if (member.isOwner) return;
    final newActive = !member.isActive;
    await FirebaseDatabase.instance.ref('users/$uid/isActive').set(newActive);
    update(member.copyWith(isActive: newActive));
  }

  /// Hard-deletes a staff member from Firebase AND removes from local state
  /// immediately — UI updates instantly without waiting for a reload.
  Future<void> removeFromFirebase(String uid) async {
    // 1. Remove from local state immediately so UI updates without waiting
    state = state.where((s) => s.uid != uid).toList();
    // 2. Hard-delete from Firebase (removes the entire users/$uid node)
    await FirebaseDatabase.instance.ref('users/$uid').remove();
  }

  Future<void> changeRole(String uid, String newRole) async {
    final member = state.firstWhere((s) => s.uid == uid,
        orElse: () => throw Exception('Staff not found'));
    if (member.isOwner) return;
    await FirebaseDatabase.instance.ref('users/$uid/role').set(newRole);
    update(member.copyWith(role: newRole));
  }

  Future<void> resetPin(String uid, String newPin) async {
    final member = state.firstWhere((s) => s.uid == uid,
        orElse: () => throw Exception('Staff not found'));
    if (member.isOwner) return;
    await FirebaseDatabase.instance.ref().update({
      'users/$uid/pin': newPin,
      'users/$uid/pin_hash': '',
    });
    update(member.copyWith(pin: newPin));
  }

  Future<void> updateStats(String uid, {
    required int totalJobs,
    required int completedJobs,
    required double rating,
  }) async {
    await FirebaseDatabase.instance.ref().update({
      'users/$uid/totalJobs':     totalJobs,
      'users/$uid/completedJobs': completedJobs,
      'users/$uid/rating':        rating,
    });
    final idx = state.indexWhere((s) => s.uid == uid);
    if (idx >= 0) {
      final list = [...state];
      list[idx] = list[idx].copyWith(
        totalJobs: totalJobs, completedJobs: completedJobs, rating: rating,
      );
      state = list;
    }
  }

  void clear() => state = [];
}

final staffProvider =
    StateNotifierProvider<StaffNotifier, List<StaffMember>>((_) => StaffNotifier());
final activeStaffProvider = Provider<List<StaffMember>>(
    (ref) => ref.watch(staffProvider).where((s) => s.isActive).toList());
final activeTechsProvider = Provider<List<StaffMember>>((ref) =>
    ref.watch(staffProvider)
        .where((s) => s.isActive && (s.role == 'technician' || s.role == 'manager'))
        .toList());

// ─────────────────────────────────────────────────────────────────────────────
//  techsProvider — compatibility shim (derived from staffProvider)
//
//  The old staff/ and technicians/ DB nodes are gone. techsProvider is now
//  a read-only computed view of staffProvider so all existing call-sites
//  (StaffPage, job assignment, reports) work without changes.
// ─────────────────────────────────────────────────────────────────────────────
final techsProvider = Provider<List<Technician>>((ref) {
  return ref.watch(staffProvider)
      .where((s) => !s.isOwner)
      .map((s) => Technician(
            techId:         s.uid,
            shopId:         s.shopId,
            name:           s.displayName,
            phone:          s.phone,
            specialization: s.specialization,
            totalJobs:      s.totalJobs,
            completedJobs:  s.completedJobs,
            rating:         s.rating,
            isActive:       s.isActive,
            joinedAt:       s.joinedAt.isNotEmpty ? s.joinedAt : s.createdAt,
            pin:            s.pin,
            role:           s.role,
          ))
      .toList();
});

// Stub notifier — kept for source compatibility. techsProvider is now a
// derived Provider<List<Technician>> (not StateNotifierProvider), so this
// class is never instantiated. All writes go through staffProvider.
// ignore: must_be_immutable
class TechsNotifier extends StateNotifier<List<Technician>> {
  TechsNotifier() : super([]);
  // ignore: no-op stub
  void setAll(List<Technician> list) {}
  void add(Technician t) {}
  void update(Technician u) {}
  void delete(String id) {}
}

// ─────────────────────────────────────────────────────────────────────────────
//  PRODUCTS
// ─────────────────────────────────────────────────────────────────────────────
class ProductsNotifier extends StateNotifier<List<Product>> {
  ProductsNotifier() : super([]);
  void setAll(List<Product> list) => state = list;
  void add(Product p) => state = [p, ...state];
  void update(Product u) =>
      state = state.map((p) => p.productId == u.productId ? u : p).toList();
  void delete(String id) =>
      state = state.where((p) => p.productId != id).toList();
  void adjustQty(String id, int delta) {
    state = state.map((p) {
      if (p.productId != id) return p;
      return p.copyWith(stockQty: (p.stockQty + delta).clamp(0, 99999));
    }).toList();
  }
}
final productsProvider =
    StateNotifierProvider<ProductsNotifier, List<Product>>((_) => ProductsNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  CUSTOMERS
// ─────────────────────────────────────────────────────────────────────────────
class CustomersNotifier extends StateNotifier<List<Customer>> {
  CustomersNotifier() : super([]);
  void setAll(List<Customer> list) => state = list;
  void add(Customer c) => state = [c, ...state];
  void update(Customer u) =>
      state = state.map((c) => c.customerId == u.customerId ? u : c).toList();
  void delete(String id) =>
      state = state.where((c) => c.customerId != id).toList();
}
final customersProvider =
    StateNotifierProvider<CustomersNotifier, List<Customer>>((_) => CustomersNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  JOBS
// ─────────────────────────────────────────────────────────────────────────────
class JobsNotifier extends StateNotifier<List<Job>> {
  JobsNotifier() : super([]);
  void setAll(List<Job> list) => state = list;
  void addJob(Job j) => state = [j, ...state];
  void updateJob(Job u) =>
      state = state.map((j) => j.jobId == u.jobId ? u : j).toList();
  // ── addTimelineNote ──────────────────────────────────────────
  Future<void> addTimelineNote(String id, String note, String by) async {
    final now = DateTime.now().toIso8601String();
    Job? updated;
    state = state.map((j) {
      if (j.jobId != id) return j;
      updated = j.copyWith(
        timeline: [
          ...j.timeline,
          TimelineEntry(status: j.status, time: now, by: by, note: note, type: 'note'),
        ],
        updatedAt: now,
      );
      return updated!;
    }).toList();
    if (updated == null) return;
    try {
      await FirebaseDatabase.instance.ref('jobs/$id').update({
        'timeline': updated!.timeline.map((e) => {
          'status': e.status, 'time': e.time, 'by': e.by,
          'note': e.note, 'type': e.type,
        }).toList(),
        'updatedAt': now,
      });
    } catch (_) {}
  }

  // ── updateStatus ─────────────────────────────────────────────
  Future<void> updateStatus(String id, String newStatus, String by,
      {String note = '', String type = 'flow',
       String? holdReason, int? reopenCount}) async {
    final now = DateTime.now().toIso8601String();
    Job? updated;
    state = state.map((j) {
      if (j.jobId != id) return j;
      final entry = TimelineEntry(
          status: newStatus, time: now, by: by, note: note, type: type);
      updated = j.copyWith(
        status: newStatus,
        previousStatus: j.status,
        holdReason: holdReason,
        timeline: [...j.timeline, entry],
        reopenCount: reopenCount ?? j.reopenCount,
        updatedAt: now,
      );
      return updated!;
    }).toList();
    if (updated == null) return;
    try {
      await FirebaseDatabase.instance.ref('jobs/$id').update({
        'status':         newStatus,
        'previousStatus': updated!.previousStatus,
        'holdReason':     holdReason,
        'reopenCount':    updated!.reopenCount,
        'timeline': updated!.timeline.map((e) => {
          'status': e.status, 'time': e.time, 'by': e.by,
          'note': e.note, 'type': e.type,
        }).toList(),
        'updatedAt': now,
      });
    } catch (_) {}
  }

  // ── markNotified ─────────────────────────────────────────────
  Future<void> markNotified(String id, String via) async {
    final now = DateTime.now().toIso8601String();
    Job? updated;
    state = state.map((j) {
      if (j.jobId != id) return j;
      updated = j.copyWith(
        notificationSent: true,
        notificationChannel: via,
        timeline: [...j.timeline,
          TimelineEntry(status: j.status, time: now,
              by: 'System', note: 'Pickup notification sent via $via', type: 'note'),
        ],
        updatedAt: now,
      );
      return updated!;
    }).toList();
    if (updated == null) return;
    try {
      await FirebaseDatabase.instance.ref('jobs/$id').update({
        'notificationSent':    true,
        'notificationChannel': via,
        'timeline': updated!.timeline.map((e) => {
          'status': e.status, 'time': e.time, 'by': e.by,
          'note': e.note, 'type': e.type,
        }).toList(),
        'updatedAt': now,
      });
    } catch (_) {}
  }

  // ── Convenience wrappers ─────────────────────────────────────
  Future<void> putOnHold(String id, String reason, String by) =>
      updateStatus(id, 'On Hold', by,
          note: reason, type: 'flow', holdReason: reason);

  Future<void> cancel(String id, String reason, String by) =>
      updateStatus(id, 'Cancelled', by,
          note: reason, type: 'flow', holdReason: null);

  Future<void> reopen(String id, String reason, String by) {
    final job = state.firstWhere((j) => j.jobId == id,
        orElse: () => throw StateError('Job $id not found'));
    return updateStatus(id, 'In Repair', by,
        note: reason, type: 'flow',
        holdReason: null,
        reopenCount: job.reopenCount + 1);
  }

  Future<void> resumeFromHold(String id, String by) =>
      updateStatus(id, 'In Repair', by,
          type: 'flow', holdReason: null);

  // ── collectPayment ───────────────────────────────────────────
  /// Marks a repair job as paid. Writes to jobs/, invoices/ (if saved),
  /// and transactions/ so Dashboard + Reports KPIs update automatically.
  Future<void> collectPayment({
    required String jobId,
    required String shopId,
    required double amount,
    required String method,       // 'Cash' | 'UPI' | 'Card' | 'Bank Transfer'
    required String collectedBy,
    String? invoiceId,
  }) async {
    final now    = DateTime.now();
    final nowIso = now.toIso8601String();
    final db     = FirebaseDatabase.instance;
    final txId   = 'repair_tx_${now.millisecondsSinceEpoch}';

    final batch = <String, dynamic>{
      'jobs/$jobId/paymentStatus': 'Paid',
      'jobs/$jobId/paymentMethod': method,
      'jobs/$jobId/amountPaid':    amount,
      'jobs/$jobId/paidAt':        nowIso,
      'jobs/$jobId/status':        'Delivered',
      'jobs/$jobId/updatedAt':     nowIso,
      'transactions/$txId': {
        'shopId':      shopId,
        'jobId':       jobId,
        'type':        'repair',
        'productId':   '',
        'productName': 'Repair Service',
        'qty':         1,
        'price':       amount,
        'cost':        0.0,
        'total':       amount,
        'payment':     method,
        'time':        now.millisecondsSinceEpoch,
        'collectedBy': collectedBy,
      },
    };
    if (invoiceId != null && invoiceId.isNotEmpty) {
      batch['invoices/$invoiceId/paymentStatus'] = 'Paid';
      batch['invoices/$invoiceId/paymentMethod'] = method;
      batch['invoices/$invoiceId/amountPaid']    = amount;
      batch['invoices/$invoiceId/balanceDue']    = 0.0;
      batch['invoices/$invoiceId/paidAt']        = nowIso;
    }
    await db.ref().update(batch);

    state = state.map((j) {
      if (j.jobId != jobId) return j;
      return j.copyWith(
        paymentStatus: 'Paid',
        paymentMethod: method,
        amountPaid:    amount,
        paidAt:        nowIso,
        status:        'Delivered',
        previousStatus: j.status,
        timeline: [
          ...j.timeline,
          TimelineEntry(
            status: 'Delivered', time: nowIso, by: collectedBy,
            note: 'Payment collected · $method · ₹${amount.toStringAsFixed(0)}',
            type: 'flow',
          ),
        ],
        updatedAt: nowIso,
      );
    }).toList();
  }

  void reapplyTaxToActiveJobs(double taxRatePct, {bool priceInclusive = false}) {
    state = state.map((j) {
      if (j.status == 'Cancelled' || j.status == 'Completed') return j;
      final taxable = j.subtotal - j.discountAmount;
      final tax = priceInclusive
          ? taxable - (taxable / (1 + taxRatePct / 100))
          : taxable * taxRatePct / 100;
      final total = priceInclusive ? j.subtotal - j.discountAmount : taxable + tax;
      return j.copyWith(taxAmount: tax, totalAmount: total,
          updatedAt: DateTime.now().toIso8601String());
    }).toList();
  }
}
final jobsProvider =
    StateNotifierProvider<JobsNotifier, List<Job>>((_) => JobsNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  CART (POS)
// ─────────────────────────────────────────────────────────────────────────────

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void add(Product p) {
    final i = state.indexWhere((c) => c.product.productId == p.productId);
    if (i >= 0) {
      final updated = [...state];
      updated[i] = CartItem(product: updated[i].product, qty: updated[i].qty + 1);
      state = updated;
    } else {
      state = [...state, CartItem(product: p)];
    }
  }

  void setQty(String id, int qty) {
    if (qty <= 0) {
      state = state.where((c) => c.product.productId != id).toList();
    } else {
      state = state.map((c) => c.product.productId != id
          ? c : CartItem(product: c.product, qty: qty)).toList();
    }
  }

  void removeItem(String id) => setQty(id, 0);
  void updateQty(String id, int qty) => setQty(id, qty);
  void clear() => state = [];
}

final cartProvider =
    StateNotifierProvider<CartNotifier, List<CartItem>>((_) => CartNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  IN-APP STAFF SWITCHER
// ─────────────────────────────────────────────────────────────────────────────

class ActiveStaffSwitchNotifier extends StateNotifier<Technician?> {
  ActiveStaffSwitchNotifier() : super(null);
  void setStaff(Technician tech) => state = tech;
  void clear() => state = null;
}

final currentStaffProvider =
    StateNotifierProvider<ActiveStaffSwitchNotifier, Technician?>(
        (_) => ActiveStaffSwitchNotifier());

// ─────────────────────────────────────────────────────────────────────────────
//  MISC
// ─────────────────────────────────────────────────────────────────────────────

final transactionsProvider =
    StateProvider<List<Map<String, dynamic>>>((_) => []);

final searchJobProvider       = StateProvider<String>((_) => '');
final searchCustProvider      = StateProvider<String>((_) => '');
final searchInvProvider       = StateProvider<String>((_) => '');
final searchStaffProvider     = StateProvider<String>((_) => '');
final jobTabProvider          = StateProvider<String>((_) => 'All');
final staffRoleFilterProvider = StateProvider<String>((_) => 'All');
final repairTabIndexProvider  = StateProvider.family<int, String>((_, __) => 0);

final filteredStaffProvider = Provider<List<StaffMember>>((ref) {
  final all    = ref.watch(staffProvider);
  final search = ref.watch(searchStaffProvider).toLowerCase();
  final role   = ref.watch(staffRoleFilterProvider);
  return all.where((s) {
    final matchSearch = search.isEmpty ||
        s.displayName.toLowerCase().contains(search) ||
        s.email.toLowerCase().contains(search) ||
        s.phone.contains(search);
    final matchRole = role == 'All' || s.role == role;
    return matchSearch && matchRole;
  }).toList();
});

// ─────────────────────────────────────────────────────────────────────────────
//  APP UTILS — sign-out / provider cleanup
// ─────────────────────────────────────────────────────────────────────────────

/// Clears all local provider state and signs out of Firebase.
///
/// IMPORTANT — how to call this correctly:
///
///   await AppUtils.signOut(ref, context);
///
/// DO NOT call ref.invalidate(currentUserProvider) inside here.
/// currentUserProvider is a StreamProvider backed by FirebaseAuth.authStateChanges().
/// Invalidating it does NOT sign out — it just re-subscribes the stream.
/// Worse, if something reacts to the re-subscription by calling clearAll again,
/// you get infinite recursion (RangeError: Maximum call stack size exceeded).
///
/// The correct pattern:
///   1. Clear all StateNotifier / StateProvider state (local data only)
///   2. Call FirebaseAuth.signOut() ONCE — the stream auto-emits null,
///      which causes every ref.watch(currentUserProvider) to get null,
///      which causes the UI to navigate to the login screen automatically.
class AppUtils {
  AppUtils._();

  // Guard: prevents re-entrant calls if something rebuilds mid-clear
  static bool _clearing = false;

  static Future<void> signOut(WidgetRef ref) async {
    if (_clearing) return;
    _clearing = true;
    try {
      _clearProviders(ref);
      // Clear active session before Firebase signout
      try { ref.read(activeSessionProvider.notifier).clear(); } catch (_) {}
      await FirebaseAuth.instance.signOut();
    } finally {
      _clearing = false;
    }
  }

  /// Staff-only logout — clears active session WITHOUT touching Firebase Auth.
  /// Firebase stays connected. DB streams remain live.
  /// The lock screen (StaffLockScreen) will be shown again automatically.
  static void staffLogout(WidgetRef ref) {
    try { ref.read(activeSessionProvider.notifier).logoutStaff(); } catch (_) {}
  }

  /// Convenience alias — same as signOut, kept for compatibility with any
  /// existing call-sites that use clearAllProvidersOnSignOut(ref).
  static Future<void> clearAllProvidersOnSignOut(WidgetRef ref) async {
    await signOut(ref);
  }

  static void _clearProviders(WidgetRef ref) {
    // Clear all StateNotifier providers (local in-memory data)
    // DO NOT invalidate currentUserProvider — it's a StreamProvider that
    // auto-updates from FirebaseAuth. Invalidating it causes re-subscription
    // which can trigger this function again → infinite recursion.
    try { ref.read(settingsProvider.notifier).reset(); } catch (_) {}
    try { ref.read(jobsProvider.notifier).setAll([]); } catch (_) {}
    try { ref.read(customersProvider.notifier).setAll([]); } catch (_) {}
    try { ref.read(productsProvider.notifier).setAll([]); } catch (_) {}
    try { ref.read(staffProvider.notifier).clear(); } catch (_) {}
    try { ref.read(cartProvider.notifier).clear(); } catch (_) {}
    try { ref.read(currentStaffProvider.notifier).clear(); } catch (_) {}
    // StateProviders — reset to defaults
    try { ref.read(transactionsProvider.notifier).state = []; } catch (_) {}
    try { ref.read(searchJobProvider.notifier).state = ''; } catch (_) {}
    try { ref.read(searchCustProvider.notifier).state = ''; } catch (_) {}
    try { ref.read(searchInvProvider.notifier).state = ''; } catch (_) {}
    try { ref.read(searchStaffProvider.notifier).state = ''; } catch (_) {}
    try { ref.read(jobTabProvider.notifier).state = 'All'; } catch (_) {}
    try { ref.read(staffRoleFilterProvider.notifier).state = 'All'; } catch (_) {}
  }
}
