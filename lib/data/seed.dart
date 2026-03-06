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
  static Future<void> initialize({
    required String shopId,
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

    // ── STEP 1 — registrations/{uid} ─────────────────────────────────────────
    try {
      await db.ref('registrations/$ownerUid').set({
        'uid':          ownerUid,
        'shopId':       shopId,
        'email':        ownerEmail,
        'shopName':     shopName,
        'status':       plan == 'free' ? 'active' : 'trial',
        'plan':         plan,
        'registeredAt': now,
      });
      debugPrint('✅ Step 1 — registrations/$ownerUid written');
    } catch (e) {
      debugPrint('❌ Step 1 failed (registrations): $e');
      rethrow;
    }

    // ── STEP 2 — shops/{shopId} + users/{ownerUid} ───────────────────────────
    try {
      await db.ref().update({
        'shops/$shopId': _buildShopDoc(
          shopId:    shopId,
          shopName:  shopName,
          ownerUid:  ownerUid,
          ownerName: ownerName,
          ownerEmail:ownerEmail,
          ownerPhone:ownerPhone,
          plan:      plan,
          now:       now,
        ),
        'users/$ownerUid': {
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
          'lastLoginAt':      now,
          'createdAt':        now,
        },
      });
      debugPrint('✅ Step 2 — shops/$shopId + users/$ownerUid written');
    } catch (e) {
      debugPrint('❌ Step 2 failed (shops/users): $e');
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

    debugPrint('🎉 Shop onboarding complete — shopId: $shopId  owner: $ownerUid');
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

    // Check if shop already exists (partial write) — use update not set
    final shopSnap = await db.ref('shops/$shopId').get();
    final userSnap = await db.ref('users/$ownerUid').get();

    final updates = <String, dynamic>{};

    if (!shopSnap.exists) {
      updates['shops/$shopId'] = _buildShopDoc(
        shopId:    shopId,
        shopName:  shopName,
        ownerUid:  ownerUid,
        ownerName: ownerName,
        ownerEmail:ownerEmail,
        ownerPhone:ownerPhone,
        plan:      plan,
        now:       now,
      );
      debugPrint('  → will create shops/$shopId');
    } else {
      debugPrint('  → shops/$shopId already exists, skipping');
    }

    if (!userSnap.exists) {
      updates['users/$ownerUid'] = {
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
        'totalJobs':        0,
        'completedJobs':    0,
        'rating':           5.0,
        'joinedAt':         now,
        'lastLoginAt':      now,
        'createdAt':        now,
      };
      debugPrint('  → will create users/$ownerUid');
    } else {
      debugPrint('  → users/$ownerUid already exists, skipping');
    }

    if (updates.isNotEmpty) {
      await db.ref().update(updates);
      debugPrint('✅ Resume complete — $ownerUid');
    } else {
      debugPrint('ℹ️  Nothing to resume — both records already exist');
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
  }) {
    return {
      // ── Core identity ────────────────────────────────────────────────────
      'shopId':    shopId,
      'shopName':  shopName,
      'ownerUid':  ownerUid,
      'ownerName': ownerName,
      'ownerEmail':ownerEmail,
      'phone':     ownerPhone,
      'email':     ownerEmail,
      'address':   '',
      'gstNumber': '',
      'logoUrl':   '',
      'createdAt': now,
      'plan':      plan,
      'isActive':  true,   // ← NEVER omit or set false

      // ── Quick-toggle top-level booleans ──────────────────────────────────
      'darkMode':               false,
      'requireIntakePhoto':     false,
      'requireCompletionPhoto': false,

      // ─────────────────────────────────────────────────────────────────────
      // 2. INVOICE & RECEIPTS
      // ─────────────────────────────────────────────────────────────────────
      // Top-level invoicePrefix retained for backward-compat with providers.dart
      'invoicePrefix': 'INV',
      'invoiceSettings': {
        // Template style shown in InvoicePage
        'template':   'Standard',   // Standard | Branded | Minimal | Thermal Print
        // Invoice option toggles (InvoicePage INVOICE OPTIONS section)
        'showQR':     true,         // Show payment QR on invoice
        'showLogo':   true,         // Display shop logo at top
        'showTerms':  false,        // Show T&C section
        'footerText': 'Thank you for choosing $shopName!',
      },

      // ─────────────────────────────────────────────────────────────────────
      // 3. TAX & GST
      // ─────────────────────────────────────────────────────────────────────
      // Top-level defaultTaxRate retained for backward-compat
      'defaultTaxRate': 18.0,
      'taxSettings': {
        'taxType':        'GST',   // GST | VAT | No Tax
        'priceInclusive': false,   // true = tax extracted from selling price
      },

      // ─────────────────────────────────────────────────────────────────────
      // 4. PAYMENT METHODS (POS)
      // ─────────────────────────────────────────────────────────────────────
      'enabledPayments': ['Cash', 'UPI (GPay/PhonePe)'],

      // ─────────────────────────────────────────────────────────────────────
      // 5 / 6. TECHNICIANS + WORKFLOW STAGES
      // ─────────────────────────────────────────────────────────────────────
      'workflowStages': _defaultWorkflowStages(),

      // ─────────────────────────────────────────────────────────────────────
      // 7. WARRANTY RULES
      // ─────────────────────────────────────────────────────────────────────
      // Top-level defaultWarrantyDays retained for backward-compat
      'defaultWarrantyDays': 30,
      'warrantyRules': {
        'Screen Replacement':   90,
        'Battery Replacement':  180,
        'Water Damage Repair':  30,
        'Charging Port Repair': 60,
        'Software Repair':      7,
        'Camera Repair':        60,
        'Speaker / Mic Repair': 45,
        'Back Glass Repair':    30,
      },

      // ─────────────────────────────────────────────────────────────────────
      // 9. WHATSAPP BUSINESS
      // ─────────────────────────────────────────────────────────────────────
      'whatsapp': {
        'apiKey':           '',
        'phoneNumberId':    '',
        'connected':        false,
        // Auto-send triggers (WhatsappPage toggles)
        'autoPickupReady':  true,
        'autoStatusUpdate': false,
        'autoReminder':     true,
        // Message templates (editable in WhatsappPage)
        'templates': {
          'pickupReady':
              'Hi {name}! 👋 Your {device} ({job_num}) is ready for collection.\n'
              'Amount due: ₹{amount}. Open Mon–Sat 10am–7pm. 📍 {shop_address}',
          'jobUpdate':
              'Hi {name}! Update on your {device}: Status changed to {status}. '
              'Questions? Call us at {phone}.',
          'pickupReminder':
              'Hi {name}, reminder: your {device} has been ready for {days} days. '
              'Please collect at your earliest convenience.',
        },
      },

      // ─────────────────────────────────────────────────────────────────────
      // 10. SMS GATEWAY
      // ─────────────────────────────────────────────────────────────────────
      'sms': {
        'provider':       'MSG91',   // MSG91 | Twilio | TextLocal | Fast2SMS
        'apiKey':         '',
        'senderId':       'TECHFX',
        'onPickupReady':  true,
        'onStatusUpdate': false,
      },

      // ─────────────────────────────────────────────────────────────────────
      // 11. PUSH NOTIFICATIONS
      // ─────────────────────────────────────────────────────────────────────
      'pushNotifications': {
        'Job Overdue Alert':        true,
        'Low Stock Warning':        true,
        'New Job Created':          false,
        'Job Status Changed':       true,
        'Daily Summary (8am)':      false,
        'Customer Pickup Reminder': true,
        'Payment Received':         true,
        'Warranty Expiring Soon':   false,
      },

      // ─────────────────────────────────────────────────────────────────────
      // 12. EMAIL / SMTP
      // ─────────────────────────────────────────────────────────────────────
      'emailSettings': {
        'smtpHost':                 'smtp.gmail.com',
        'smtpPort':                 587,
        'fromAddress':              '',
        // Never store raw passwords in plaintext in production;
        // use Firebase Functions / Secret Manager. This field is
        // a placeholder so the schema exists on first load.
        'appPassword':              '',
        'displayName':              shopName,
        'sendInvoiceOnCompletion':  true,
        'sendPickupReady':          true,
      },

      // ─────────────────────────────────────────────────────────────────────
      // 13. PAYMENT GATEWAY (online collection)
      // ─────────────────────────────────────────────────────────────────────
      'paymentGateway': {
        'provider':  '',     // razorpay | stripe | paytm | instamojo
        'apiKey':    '',
        'apiSecret': '',
        'testMode':  true,
      },

      // ─────────────────────────────────────────────────────────────────────
      // 15. SUPPLIER INTEGRATION
      // ─────────────────────────────────────────────────────────────────────
      'supplier': {
        'apiUrl':      '',
        'apiKey':      '',
        'autoReorder': false,
        'emailPO':     true,
      },

      // ─────────────────────────────────────────────────────────────────────
      // 16. AI DIAGNOSTICS
      // ─────────────────────────────────────────────────────────────────────
      'aiDiagnostics': {
        'anthropicApiKey':  '',
        'diagnosisEnabled': true,
        'pricingEnabled':   false,
        'partsEnabled':     false,
      },

      // ─────────────────────────────────────────────────────────────────────
      // 17. APP LOCK & BIOMETRICS
      // ─────────────────────────────────────────────────────────────────────
      // Stores the shop-level default policy.
      // Per-user biometricEnabled is in users/$uid/biometricEnabled.
      // Actual PINs are in users/$uid/pin — NOT here.
      'appLock': {
        'pinEnabled':       false,
        'biometricEnabled': false,
        'autoLock':         true,
        'lockAfterMinutes': 2,
      },

      // ─────────────────────────────────────────────────────────────────────
      // 19. CLOUD BACKUP
      // ─────────────────────────────────────────────────────────────────────
      'backup': {
        'frequency': 'Daily',         // Daily | Weekly | Manual
        'location':  'Google Drive',  // Google Drive | iCloud | Local Storage
      },

      // ─────────────────────────────────────────────────────────────────────
      // 14. ACCOUNTING INTEGRATIONS
      // ─────────────────────────────────────────────────────────────────────
      'accounting': {
        'tally':       false,
        'zoho':        false,
        'quickbooks':  false,
      },

      // ── Misc / future-use ────────────────────────────────────────────────
      'settings': {},
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
