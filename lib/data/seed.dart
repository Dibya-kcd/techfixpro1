import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ShopOnboarding  (v4 — all settings sub-objects captured)
//
//  WHAT CHANGED vs v3:
//  Previously the seed only wrote the "top-level" shop fields wired up in
//  providers.dart. The Settings screen has many sub-pages whose data was never
//  written to Firebase, so:
//    • On fresh install fields don't exist → UI falls back to hardcoded defaults
//    • Saves from sub-pages write fields DB has never seen (no rules issue, but
//      providers.dart won't deserialise them back without matching loadFromFirebase)
//
//  New shop-level sub-objects added:
//    invoiceSettings   — template style, QR, logo, T&C, footer text
//    taxSettings       — taxType (GST/VAT/No Tax), priceInclusive flag
//    warrantyRules     — per-repair-type warranty days
//    whatsapp          — credentials + auto-send toggles + templates
//    sms               — provider, credentials, triggers
//    pushNotifications — per-alert-type enabled map
//    emailSettings     — SMTP config + triggers
//    paymentGateway    — gateway + credentials + testMode
//    supplier          — API URL + auto-reorder toggles
//    aiDiagnostics     — API key + feature toggles
//    appLock           — PIN/biometric/auto-lock policy
//    backup            — schedule + location
//    accounting        — connected integrations flags
//
//  WHY 3 STEPS (unchanged from v3):
//    Step 1: registrations/$ownerUid            (no dependencies)
//    Step 2: shops/$shopId + users/$ownerUid    (shops needs registrations ✅)
//    Step 3: staff/$ownerUid              (needs registrations ✅)
// ─────────────────────────────────────────────────────────────────────────────

class ShopOnboarding {
  /// Returns the shopId that was used (generated internally if empty string passed).
  static Future<String> initialize({
    String shopId = '',        // pass '' to auto-generate (recommended)
    required String ownerUid,
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
    required String shopName,
    required String ownerPin,
    String plan = 'free',
  }) async {
    final db = FirebaseDatabase.instance;
    final now = DateTime.now().toIso8601String();

    // ── Generate shopId if not provided ──────────────────────────────────────
    // SINGLE source of truth: generated here once, written to registrations/
    // in Step 1, and reused by resumeSetup via registrations/ read.
    // auth_signup must NOT generate its own shopId — pass '' and use return value.
    final resolvedShopId = shopId.isNotEmpty
        ? shopId
        : db.ref('shops').push().key!;

    // ── STEP 1 — registrations/{uid} ─────────────────────────────────────────
    try {
      await db.ref('registrations/$ownerUid').set({
        'uid':          ownerUid,
        'shopId':       resolvedShopId,
        'email':        ownerEmail,
        'ownerName':    ownerName,   // saved so resume can pre-fill shop doc
        'phone':        ownerPhone,  // saved so resume can pre-fill shop doc
        'shopName':     shopName,
        'status':       plan == 'free' ? 'active' : 'trial',
        'plan':         plan,
        'registeredAt': now,
      });
      debugPrint('✅ Step 1 — registrations/$ownerUid written');
    } catch (e) {
      // Non-fatal — registrations/ is only a resume fallback
      debugPrint('⚠️ Step 1 skipped (registrations) — $e');
    }

    // ── STEP 2a — users/{ownerUid} first ────────────────────────────────────
    // MUST write users/ before shops/ — the shops write rule verifies
    // users/{uid}.isActive + isOwner + resolvedShopId at evaluation time.
    try {
      await db.ref('users/$ownerUid').set({
        'uid':              ownerUid,
        'shopId':           resolvedShopId,
        'displayName':      ownerName,
        'email':            ownerEmail,
        'role':             'admin',
        'isOwner':          true,
        'pin':              ownerPin,
        'pin_hash':         '',
        'phone':            ownerPhone,
        'isActive':         true,
        'biometricEnabled': false,
        'specialization':   'Management',
        'totalJobs':        0,
        'completedJobs':    0,
        'rating':           5.0,
        'joinedAt':         now,
        'lastLoginAt':      now,
        'createdAt':        now,
      });
      debugPrint('✅ Step 2a — users/$ownerUid written');
    } catch (e) {
      debugPrint('❌ Step 2a failed (users): $e');
      rethrow;
    }

    // ── STEP 2b — shops/{resolvedShopId} ─────────────────────────────────────────────
    try {
      await db.ref('shops/$resolvedShopId').set(_buildShopDoc(
        shopId:    resolvedShopId,
        shopName:  shopName,
        ownerUid:  ownerUid,
        ownerName: ownerName,
        ownerEmail:ownerEmail,
        ownerPhone:ownerPhone,
        plan:      plan,
        now:       now,
      ));
      debugPrint('✅ Step 2b — shops/$resolvedShopId written');
    } catch (e) {
      debugPrint('❌ Step 2b failed (shops): $e');
      rethrow;
    }

    // ── STEP 3 — merge performance stats into users/{ownerUid} ──────────────
    // staff/ and technicians/ nodes removed — all data lives in users/ only.
    try {
      await db.ref('users/$ownerUid').update({
        'uid':          ownerUid,
        'totalJobs':    0,
        'completedJobs':0,
        'rating':       5.0,
        'joinedAt':     now,
      });
      debugPrint('✅ Step 3 — users/$ownerUid stats initialised');
    } catch (e) {
      debugPrint('❌ Step 3 failed (users stats): $e');
      rethrow;
    }

    debugPrint('🎉 Shop onboarding complete — shopId: $resolvedShopId  owner: $ownerUid');
    return resolvedShopId;
  }


  // ── Resume an interrupted registration ────────────────────────────────────
  // Called by auth_login.dart when users/{uid} is missing but
  // registrations/{uid} exists — meaning Step 2 previously failed.
  // Skips Step 1 (registrations already written), re-runs Steps 2 & 3.
  static Future<void> resumeSetup({
    required String shopId,
    required String ownerUid,
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
    required String shopName,
    String plan = 'free',
    String ownerPin = '0000',  // default PIN — owner can change in settings
  }) async {
    debugPrint('🔄 Resuming interrupted setup for $ownerUid / $shopId');
    final db = FirebaseDatabase.instance;
    final now = DateTime.now().toIso8601String();

    // ── Read current state ────────────────────────────────────────────────────
    final shopSnap = await db.ref('shops/$shopId').get();
    final userSnap = await db.ref('users/$ownerUid').get();

    // A partial users/ record (e.g. only lastLoginAt written by auth listener)
    // must be treated as incomplete. Check for shopId as the completeness signal.
    final userMap = userSnap.exists && userSnap.value is Map
        ? Map<String, dynamic>.from(userSnap.value as Map)
        : <String, dynamic>{};
    final userComplete = (userMap['shopId'] as String?)?.isNotEmpty == true
        && userMap['isActive'] == true;

    debugPrint('  shopExists=${shopSnap.exists}  userComplete=$userComplete  userKeys=${userMap.keys.toList()}');

    // ── Write users/ FIRST ────────────────────────────────────────────────────
    // shops/ write rule checks users/{uid}.isActive + isOwner + shopId,
    // so users/ must exist and be complete before shops/ can be written.
    if (!userComplete) {
      await db.ref('users/$ownerUid').set({
        'uid':              ownerUid,
        'shopId':           shopId,
        'displayName':      ownerName,
        'email':            ownerEmail,
        'role':             'admin',
        'isOwner':          true,
        'pin':              ownerPin,
        'pin_hash':         '',
        'phone':            ownerPhone,
        'isActive':         true,
        'biometricEnabled': false,
        'specialization':   'Management',
        'totalJobs':        userMap['totalJobs'] ?? 0,
        'completedJobs':    userMap['completedJobs'] ?? 0,
        'rating':           userMap['rating'] ?? 5.0,
        'joinedAt':         userMap['joinedAt'] ?? now,
        'lastLoginAt':      userMap['lastLoginAt'] ?? now,
        'createdAt':        userMap['createdAt'] ?? now,
      });
      debugPrint('✅ Resume — users/$ownerUid written (was partial=${ userSnap.exists })');
    } else {
      debugPrint('  → users/$ownerUid complete, skipping');
    }

    // ── Write shops/ SECOND ───────────────────────────────────────────────────
    // Pass existing shop data (if any) so _buildShopDoc merges rather than blanks
    final existingShop = shopSnap.exists && shopSnap.value is Map
        ? Map<String, dynamic>.from(shopSnap.value as Map)
        : <String, dynamic>{};

    if (!shopSnap.exists) {
      await db.ref('shops/$shopId').set(_buildShopDoc(
        shopId:    shopId,
        shopName:  shopName,
        ownerUid:  ownerUid,
        ownerName: ownerName,
        ownerEmail:ownerEmail,
        ownerPhone:ownerPhone,
        plan:      plan,
        now:       now,
        existing:  existingShop,
      ));
      debugPrint('✅ Resume — shops/$shopId written');
    } else {
      // Shop exists but may have blank fields — patch missing ones only
      final patches = <String, dynamic>{};
      void patch(String key, String val) {
        final cur = (existingShop[key] as String?) ?? '';
        if (cur.isEmpty && val.isNotEmpty) patches['shops/$shopId/$key'] = val;
      }
      patch('shopName',  shopName);
      patch('ownerName', ownerName);
      patch('ownerEmail',ownerEmail);
      patch('phone',     ownerPhone);
      patch('email',     ownerEmail);
      if (patches.isNotEmpty) {
        await db.ref().update(patches);
        debugPrint('✅ Resume — patched \${patches.keys.length} missing fields in shops/$shopId');
      } else {
        debugPrint('  → shops/$shopId already complete, skipping');
      }
    }

    if (!userComplete || !shopSnap.exists) {
      debugPrint('✅ Resume complete — $ownerUid');
    } else {
      debugPrint('ℹ️  Nothing to resume — all records already complete');
    }
  }

  // ── Build the full shop document ────────────────────────────────────────────
  static Map<String, dynamic> _buildShopDoc({
    required String shopId,
    required String shopName,
    required String ownerUid,
    required String ownerName,
    required String ownerEmail,
    required String ownerPhone,
    required String plan,
    required String now,
    // Optional: existing shop data to merge over (for partial updates)
    Map<String, dynamic> existing = const {},
  }) {
    // Helper: prefer existing non-empty value, fall back to provided param
    String resolveField(String key, String param) {
      final v = (existing[key] as String?) ?? '';
      return v.isNotEmpty ? v : param;
    }

    return {
      // ── Core identity ────────────────────────────────────────────────────
      'shopId':    shopId,
      'shopName':  resolveField('shopName',  shopName),
      'ownerUid':  ownerUid,
      'ownerName': resolveField('ownerName', ownerName),
      'ownerEmail':resolveField('ownerEmail', ownerEmail),
      'phone':     resolveField('phone',     ownerPhone),
      'email':     resolveField('email',     ownerEmail),
      'address':   resolveField('address',   ''),
      'gstNumber': resolveField('gstNumber', ''),
      'logoUrl':   resolveField('logoUrl',   ''),
      'createdAt': resolveField('createdAt', now),
      'plan':      resolveField('plan',      plan),
      'isActive':  true,   // ← NEVER omit or set false

      // ── Quick-toggle top-level booleans ──────────────────────────────────
      'darkMode':               existing['darkMode']               as bool? ?? false,
      'requireIntakePhoto':     existing['requireIntakePhoto']     as bool? ?? false,
      'requireCompletionPhoto': existing['requireCompletionPhoto'] as bool? ?? false,

      // ── Invoice ──────────────────────────────────────────────────────────
      'invoicePrefix': resolveField('invoicePrefix', 'INV'),
      'invoiceSettings': existing['invoiceSettings'] != null
          ? Map<String, dynamic>.from(existing['invoiceSettings'] as Map)
          : {
              'template':   'Standard',
              'showQR':     true,
              'showLogo':   true,
              'showTerms':  false,
              'footerText': 'Thank you for choosing us!',
            },

      // ── Tax — top-level + settings map (providers.dart reads both) ────────
      'defaultTaxRate': (existing['defaultTaxRate'] as num?)?.toDouble() ?? 18.0,

      // ── Settings map — flat structure matching providers.dart reads ───────
      // providers.dart: d['settings']['taxType'], d['settings']['priceInclusive']
      // providers.dart: d['settings']['warranty_screen_replacement'] etc.
      'settings': () {
        final s = existing['settings'] != null
            ? Map<String, dynamic>.from(existing['settings'] as Map)
            : <String, dynamic>{};
        return {
          'taxType':        s['taxType']        ?? 'GST',
          'priceInclusive': s['priceInclusive'] ?? false,
          // Warranty days keyed by warranty_* (snake_case) — matches providers.dart
          'warranty_screen_replacement':   s['warranty_screen_replacement']   ?? 90,
          'warranty_battery_replacement':  s['warranty_battery_replacement']  ?? 180,
          'warranty_water_damage_repair':  s['warranty_water_damage_repair']  ?? 30,
          'warranty_charging_port_repair': s['warranty_charging_port_repair'] ?? 60,
          'warranty_software_repair':      s['warranty_software_repair']      ?? 7,
          'warranty_camera_repair':        s['warranty_camera_repair']        ?? 60,
          'warranty_speaker_mic_repair':   s['warranty_speaker_mic_repair']   ?? 45,
          'warranty_back_glass_repair':    s['warranty_back_glass_repair']    ?? 30,
        };
      }(),

      // ── Payment methods ───────────────────────────────────────────────────
      'enabledPayments': existing['enabledPayments'] != null
          ? List<String>.from(existing['enabledPayments'] as List)
          : ['Cash', 'UPI (GPay/PhonePe)'],

      // ── Workflow stages ───────────────────────────────────────────────────
      'workflowStages': existing['workflowStages'] ?? _defaultWorkflowStages(),

      // ── Warranty (top-level for backward-compat) ──────────────────────────
      'defaultWarrantyDays': (existing['defaultWarrantyDays'] as int?) ?? 30,


    };
  }

  // ── Add a staff member ──────────────────────────────────────────────────────
  static Future<void> addStaffMember({
    required String uid,
    required String shopId,
    required String displayName,
    required String email,
    required String phone,
    required String role,
    required String pin,
    String specialization = 'General',
    // ignore: Kept for call-site compatibility — all roles now stored in users/ only
    bool addToTechnicians = false,
  }) async {
    try {
      final db = FirebaseDatabase.instance;
      final now = DateTime.now().toIso8601String();

      // Single write — users/$uid only. staff/ and technicians/ nodes removed.
      await db.ref('users/$uid').set({
        'uid':              uid,
        'shopId':           shopId,
        'displayName':      displayName,
        'email':            email,
        'role':             role,
        'isOwner':          false,
        'pin':              pin,
        'pin_hash':         '',
        'phone':            phone,
        'isActive':         true,
        'biometricEnabled': false,
        'specialization':   specialization,
        'totalJobs':        0,
        'completedJobs':    0,
        'rating':           5.0,
        'joinedAt':         now,
        'lastLoginAt':      '',
        'createdAt':        now,
        'updatedAt':        now,
      });

      debugPrint('✅ Staff added: $displayName ($role) to shop $shopId');
    } catch (e) {
      debugPrint('❌ Add staff failed: $e');
      rethrow;
    }
  }

  // ── Default workflow stages ──────────────────────────────────────────────────
  static List<Map<String, String>> _defaultWorkflowStages() => [
    {'icon': '📥', 'title': 'Checked In',       'desc': 'Device received at counter'},
    {'icon': '🔍', 'title': 'Diagnosed',         'desc': 'Issue identified by technician'},
    {'icon': '⏳', 'title': 'Awaiting Approval', 'desc': 'Waiting for customer quote approval'},
    {'icon': '⚙️', 'title': 'In Repair',         'desc': 'Work currently being performed'},
    {'icon': '📦', 'title': 'Awaiting Parts',    'desc': 'Waiting for spare parts to arrive'},
    {'icon': '🧪', 'title': 'Quality Check',     'desc': 'Testing device after repair'},
    {'icon': '✅', 'title': 'Ready for Pickup',  'desc': 'Customer notified, device ready'},
    {'icon': '🎉', 'title': 'Delivered',         'desc': 'Device handed over to customer'},
    {'icon': '🚫', 'title': 'Cancelled',         'desc': 'Repair cancelled or rejected'},
  ];
}
