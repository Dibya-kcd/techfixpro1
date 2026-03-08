import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../data/providers.dart';
import '../data/notification_service.dart';
import '../data/active_session.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import '../data/photo_service.dart';

Future<void> _shopSave(BuildContext context, WidgetRef ref,
    Future<void> Function() fn, {String successMsg = '✅ Saved'}) async {
  try {
    await fn();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(successMsg, style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
        backgroundColor: C.green, behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2)));
    }
  } catch (e) {
    final msg = e.toString().replaceAll('Exception: ', '');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ ${msg.length > 110 ? msg.substring(0,110) : msg}',
            style: GoogleFonts.syne(fontWeight: FontWeight.w600, fontSize: 12)),
        backgroundColor: C.red, behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5)));
    }
  }
}

// ─────────────────────────────────────────────────────────────
// CONSISTENT PAGE SCAFFOLD
// ─────────────────────────────────────────────────────────────
class _Page extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? fab;
  final List<Widget>? actions;

  const _Page({
    required this.title,
    this.subtitle,
    required this.children,
    this.fab,
    this.actions,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    appBar: AppBar(
      backgroundColor: C.bgElevated,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: C.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.syne(
              fontWeight: FontWeight.w800, fontSize: 16, color: C.white)),
          if (subtitle != null)
            Text(subtitle!, style: GoogleFonts.syne(
                fontSize: 11, color: C.textMuted)),
        ],
      ),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: C.border),
      ),
    ),
    floatingActionButton: fab,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: children,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Consistent Save Button with loading state
// ─────────────────────────────────────────────────────────────
class _SaveBtn extends StatefulWidget {
  final VoidCallback onSave;
  final String label;
  const _SaveBtn({required this.onSave, this.label = '💾  Save Changes'});

  @override
  State<_SaveBtn> createState() => _SaveBtnState();
}

class _SaveBtnState extends State<_SaveBtn> {
  bool _loading = false;
  bool _done = false;

  Future<void> _handle() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    widget.onSave();
    setState(() { _loading = false; _done = true; });
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      onPressed: _loading ? null : _handle,
      style: ElevatedButton.styleFrom(
        backgroundColor: _done ? C.green : C.primary,
        foregroundColor: C.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: _loading
          ? const SizedBox(width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: C.bg))
          : Text(_done ? '✅  Saved!' : widget.label,
              style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Consistent info banner
// ─────────────────────────────────────────────────────────────
Widget _infoBanner(String text, {Color color = C.primary}) => Container(
  padding: const EdgeInsets.all(12),
  margin: const EdgeInsets.only(bottom: 16),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: color.withValues(alpha: 0.3)),
  ),
  child: Text(text, style: GoogleFonts.syne(fontSize: 12, color: color, height: 1.5)),
);

// ─────────────────────────────────────────────────────────────
// MAIN SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final userAsync = ref.watch(currentUserProvider);
    final session = userAsync.asData?.value;
    // Role comes from activeSessionProvider (who is operating NOW),
    // NOT from currentUserProvider (which is always the Firebase owner account).
    final activeSession = ref.watch(activeSessionProvider);
    final role = activeSession?.role ?? session?.role ?? 'technician';
    final isAdmin = role == 'admin';
    final isManager = role == 'manager';
    final isReception = role == 'reception';
    final isTechnician = role == 'technician';
    final canManageShopSettings = isAdmin || isManager;
    final canSeeUserRoles = isAdmin || isManager;
    final roleLabel = isAdmin
        ? 'Admin'
        : isManager
            ? 'Manager'
            : isReception
                ? 'Reception'
                : isTechnician
                    ? 'Technician'
                    : 'Staff';

    // Use activeSession.shopId — always current (set on PIN entry).
    // currentUserProvider may be stale when owner resumes via lock screen.
    final buildShopId = activeSession?.shopId.isNotEmpty == true
        ? activeSession!.shopId
        : (session?.shopId ?? '');
    if (buildShopId.isNotEmpty && s.shopId != buildShopId) {
      ref.read(settingsProvider.notifier).loadFromFirebase(buildShopId);
    }

    void go(Widget page) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      backgroundColor: C.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [

          // ── Profile card ─────────────────────────────────────
          GestureDetector(
            onTap: () => go(const ShopProfilePage()),
            child: SCard(
              glowColor: C.primary,
              child: Row(children: [
                Container(
                  width: 58, height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [C.primary, C.primaryDark],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(
                        color: C.primary.withValues(alpha: 0.3), blurRadius: 12)],
                  ),
                  child: Center(child: Text(
                    (() {
                      final name = activeSession?.displayName.isNotEmpty == true
                          ? activeSession!.displayName : s.ownerName;
                      return (name.isEmpty ? 'A' : name[0]).toUpperCase();
                    })(),
                    style: GoogleFonts.syne(fontWeight: FontWeight.w900,
                        fontSize: 24, color: C.bg),
                  )),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    activeSession?.displayName.isNotEmpty == true
                        ? activeSession!.displayName
                        : s.ownerName.isEmpty ? 'Admin User' : s.ownerName,
                    style: GoogleFonts.syne(fontWeight: FontWeight.w800,
                        fontSize: 17, color: C.white)),
                  Text(s.shopName.isEmpty ? 'TechFix Pro' : s.shopName,
                      style: GoogleFonts.syne(fontSize: 13, color: C.primary)),
                  Text(s.email.isEmpty ? 'Tap to set up profile →' : s.email,
                      style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
                  const SizedBox(height: 6),
                  Pill(roleLabel, small: true),
                ])),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: C.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.edit_outlined, color: C.primary, size: 18),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // ── Quick toggles ────────────────────────────────────
          SettingsGroup(title: 'QUICK CONTROLS', tiles: [
            SettingsTile(
              icon: '🌙', title: 'Dark Mode',
              subtitle: s.darkMode ? 'Currently using dark theme' : 'Currently using light theme',
              trailing: Switch(value: s.darkMode,
                  onChanged: (_) => ref.read(settingsProvider.notifier).toggle('darkMode')),
            ),
            SettingsTile(
              icon: '📸', title: 'Require Intake Photos',
              subtitle: s.requireIntakePhoto ? 'Mandatory at job check-in' : 'Optional at check-in',
              trailing: Switch(value: s.requireIntakePhoto,
                  onChanged: (_) => ref.read(settingsProvider.notifier).toggle('requireIntakePhoto')),
            ),
            SettingsTile(
              icon: '🏁', title: 'Require Completion Photos',
              subtitle: s.requireCompletionPhoto ? 'Mandatory before pickup' : 'Optional before pickup',
              trailing: Switch(value: s.requireCompletionPhoto,
                  onChanged: (_) => ref.read(settingsProvider.notifier).toggle('requireCompletionPhoto')),
            ),
          ]),

          if (canManageShopSettings)
            SettingsGroup(title: 'SHOP', tiles: [
              SettingsTile(icon: '🏪', title: 'Shop Profile',
                  subtitle: s.shopName.isEmpty ? 'Not configured' : s.shopName,
                  onTap: () => go(const ShopProfilePage())),
              SettingsTile(icon: '🧾', title: 'Invoice & Receipts',
                  subtitle: 'Prefix: ${s.invoicePrefix}  ·  Format & logo',
                  onTap: () => go(const InvoicePage())),
              SettingsTile(icon: '📊', title: 'Tax & GST',
                  subtitle: 'Default rate: ${s.defaultTaxRate.toStringAsFixed(0)}%',
                  onTap: () => go(const TaxPage())),
              SettingsTile(icon: '💳', title: 'Payment Methods',
                  subtitle: 'Cash, Card, UPI, Wallet',
                  onTap: () => go(const PaymentMethodsPage())),
            ]),

          SettingsGroup(title: 'TEAM & WORKFLOW', tiles: [
            SettingsTile(icon: '👨‍🔧', title: 'Staff',
                subtitle: '${ref.watch(techsProvider).where((t) => t.isActive).length} active team members',
                onTap: () => go(const StaffPage())),
            if (!isTechnician)
              SettingsTile(icon: '🔄', title: 'Repair Workflow',
                  subtitle: '9 stages from check-in to completion',
                  onTap: () => go(const WorkflowPage())),
            if (!isTechnician)
              SettingsTile(icon: '🛡️', title: 'Warranty Rules',
                  subtitle: 'Default: ${s.defaultWarrantyDays} days post-repair',
                  onTap: () => go(const WarrantyPage())),
            if (canSeeUserRoles)
              SettingsTile(icon: '👥', title: 'User Roles & Access',
                  subtitle: 'Staff permissions and PIN access',
                  onTap: () => go(const UserRolesPage())),
          ]),

          // ── Notifications ────────────────────────────────────
          SettingsGroup(title: 'NOTIFICATIONS', tiles: [
            SettingsTile(icon: '💬', title: 'WhatsApp Business',
                subtitle: 'API key & message templates',
                onTap: () => go(const WhatsappPage())),
            SettingsTile(icon: '📱', title: 'SMS Gateway',
                subtitle: 'Twilio / MSG91 configuration',
                onTap: () => go(const SmsPage())),
            SettingsTile(icon: '🔔', title: 'Push Notifications',
                subtitle: 'Overdue alerts, low stock warnings',
                onTap: () => go(const PushNotifPage())),
            SettingsTile(icon: '📧', title: 'Email Settings',
                subtitle: 'SMTP configuration & templates',
                onTap: () => go(const EmailPage())),
          ]),

          // ── Integrations ─────────────────────────────────────
          SettingsGroup(title: 'INTEGRATIONS', tiles: [
            SettingsTile(icon: '💳', title: 'Payment Gateway',
                subtitle: 'Razorpay / Stripe / PayTM',
                onTap: () => go(const PaymentGatewayPage())),
            SettingsTile(icon: '📚', title: 'Accounting Export',
                subtitle: 'Tally, Zoho Books, QuickBooks',
                onTap: () => go(const AccountingPage())),
            SettingsTile(icon: '📦', title: 'Supplier Integration',
                subtitle: 'Auto-reorder on low stock',
                onTap: () => go(const SupplierPage())),
            SettingsTile(icon: '🤖', title: 'AI Diagnostics',
                subtitle: 'Claude AI for repair suggestions',
                onTap: () => go(const AiPage())),
          ]),

          // ── Data & Security ──────────────────────────────────
          SettingsGroup(title: 'DATA & SECURITY', tiles: [
            SettingsTile(icon: '🔒', title: 'App Lock & Biometrics',
                subtitle: 'PIN, fingerprint, Face ID',
                onTap: () => go(const AppLockPage())),
            SettingsTile(icon: '📋', title: 'Audit Logs',
                subtitle: 'Full activity & change history',
                onTap: () => go(const AuditLogsPage())),
            SettingsTile(icon: '☁️', title: 'Cloud Backup',
                subtitle: 'Auto-backup & restore',
                onTap: () => go(const BackupPage())),
            SettingsTile(icon: '📤', title: 'Export Data',
                subtitle: 'CSV / Excel / PDF reports',
                onTap: () => go(const ExportPage())),
            if (isAdmin || role == 'admin' || role == 'manager')
              SettingsTile(icon: '🧪', title: 'Demo Data Tools',
                  subtitle: 'Seed or clear demo data for this shop',
                  onTap: () => go(const DemoDataPage())),
            SettingsTile(icon: '🧪', title: 'Firebase Diagnostics',
                subtitle: 'Test connection and permissions',
                onTap: () => go(const FirebaseDiagnosticsPage())),
          ]),

          // ── About ────────────────────────────────────────────
          SettingsGroup(title: 'ABOUT', tiles: [
            SettingsTile(icon: '📄', title: 'Terms & Privacy Policy',
                subtitle: 'Legal information', onTap: () => _showInfoDialog(context,
                    'Terms & Privacy Policy',
                    'TechFix Pro stores all data locally on your device. '
                    'No data is sent to third parties without your explicit consent. '
                    'By using this app you agree to these terms.')),
            SettingsTile(icon: '💡', title: 'Send Feedback',
                subtitle: 'Help us improve the app',
                onTap: () => _showInfoDialog(context, 'Send Feedback',
                    'Email your feedback to: feedback@techfixpro.app\n'
                    'We read every message and aim to respond within 48 hours.')),
            const SettingsTile(icon: '📱', title: 'App Version',
                subtitle: 'v3.0.0  ·  Build 2025.02'),
          ]),

          // ── Sign out — role session only ─────────────────────
          // Logs out of the current role → back to staff PIN screen.
          // Firebase stays connected. DB streams stay live.
          // To sign out from Firebase, use the hidden admin screen (5-tap logo).
          GestureDetector(
            onTap: () => _confirmRoleSignOut(context, ref),
            child: SCard(
              borderColor: C.yellow.withValues(alpha: 0.3),
              child: Row(children: [
                Container(width: 42, height: 42,
                  decoration: BoxDecoration(color: C.yellow.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Center(child: Text('🔄', style: TextStyle(fontSize: 20)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Sign Out', style: GoogleFonts.syne(
                      fontWeight: FontWeight.w700, fontSize: 15, color: C.yellow)),
                  Text('Log out of current role  ·  Returns to staff PIN screen',
                      style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          Center(child: Text('TechFix Pro v3.0  ·  Made with ❤️ in India',
              style: GoogleFonts.syne(fontSize: 11, color: C.textDim))),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title, String body) =>
      showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: GoogleFonts.syne(
            fontWeight: FontWeight.w800, color: C.white)),
        content: Text(body, style: GoogleFonts.syne(
            fontSize: 13, color: C.textMuted, height: 1.6)),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.syne(
                color: C.primary, fontWeight: FontWeight.w700)))],
      ));

  /// Signs out of the current ROLE only — Firebase stays connected.
  /// Staff see PIN screen again. To sign out from Firebase, use hidden admin screen.
  void _confirmRoleSignOut(BuildContext context, WidgetRef ref) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: C.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Sign Out?', style: GoogleFonts.syne(
          fontWeight: FontWeight.w800, color: C.white)),
      content: Text(
        'You will be returned to the staff PIN screen. '
        'The app stays connected to the database.',
        style: GoogleFonts.syne(fontSize: 13, color: C.textMuted, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.syne(color: C.textMuted))),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            AppUtils.staffLogout(ref);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: C.yellow, foregroundColor: C.bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: Text('Sign Out', style: GoogleFonts.syne(fontWeight: FontWeight.w800))),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════
// 1. SHOP PROFILE
// ═════════════════════════════════════════════════════════════
class ShopProfilePage extends ConsumerStatefulWidget {
  const ShopProfilePage({super.key});
  @override
  ConsumerState<ShopProfilePage> createState() => _ShopProfileState();
}

class _ShopProfileState extends ConsumerState<ShopProfilePage> {
  late final TextEditingController _shopName, _owner, _phone, _email, _address, _gst;
  String? _existingLogoUrl;  // already-uploaded URL from Firebase
  Uint8List? _logoBytes;      // newly picked bytes (not yet uploaded)
  bool _uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _shopName        = TextEditingController(text: s.shopName);
    _owner           = TextEditingController(text: s.ownerName);
    _phone           = TextEditingController(text: s.phone);
    _email           = TextEditingController(text: s.email);
    _address         = TextEditingController(text: s.address);
    _gst             = TextEditingController(text: s.gstNumber);
    _existingLogoUrl = s.logoUrl.isNotEmpty ? s.logoUrl : null;
  }

  @override
  void dispose() {
    for (final c in [_shopName, _owner, _phone, _email, _address, _gst]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final effectiveShopId = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');
    if (effectiveShopId.isEmpty) return;

    String logoUrl = _existingLogoUrl ?? '';

    // Upload new logo bytes if user picked one
    if (_logoBytes != null) {
      setState(() => _uploadingLogo = true);
      try {
        final uploaded = await PhotoService.uploadBytes(
          _logoBytes!,
          'logos/$effectiveShopId',
        );
        if (uploaded != null) {
          logoUrl = uploaded;
          setState(() {
            _existingLogoUrl = uploaded;
            _logoBytes = null;   // clear preview — now stored in Firebase
          });
        }
      } finally {
        if (mounted) setState(() => _uploadingLogo = false);
      }
    }

    if (!mounted) return;
    ref.read(settingsProvider.notifier).update(
        ref.read(settingsProvider).copyWith(
          shopName: _shopName.text.trim(),
          ownerName: _owner.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          address: _address.text.trim(),
          gstNumber: _gst.text.trim(),
          logoUrl: logoUrl,
        ));
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToFirebase(effectiveShopId));
  }

  // Priority: newly-picked bytes → existing URL → placeholder
  Widget _buildLogoPreview() {
    if (_logoBytes != null) {
      return Image.memory(_logoBytes!, fit: BoxFit.cover);
    }
    if (_existingLogoUrl != null && _existingLogoUrl!.isNotEmpty) {
      return Image.network(
        _existingLogoUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: C.primary)),
        errorBuilder: (_, __, ___) => _logoPlaceholder(),
      );
    }
    return _logoPlaceholder();
  }

  Widget _logoPlaceholder() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.store_outlined, color: C.primary, size: 34),
      const SizedBox(height: 4),
      Text('Shop Logo', style: GoogleFonts.syne(fontSize: 10, color: C.textMuted)),
    ],
  );

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Shop Profile', subtitle: 'Business info shown on invoices',
    children: [
      // ── Logo picker ────────────────────────────────────────────
      Center(child: Column(children: [
        Stack(alignment: Alignment.bottomRight, children: [
          GestureDetector(
            onTap: _uploadingLogo ? null : () async {
              final bytes = await pickPhoto(context);
              if (bytes != null) setState(() => _logoBytes = bytes);
            },
            child: Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: C.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: C.primary.withValues(alpha: 0.5), width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _buildLogoPreview(),
              ),
            ),
          ),
          // Edit badge
          if (!_uploadingLogo)
            Positioned(
              bottom: 2, right: 2,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                    color: C.primary, shape: BoxShape.circle,
                    border: Border.all(color: C.bgCard, width: 2)),
                child: const Icon(Icons.edit, color: Colors.white, size: 12),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        if (_uploadingLogo)
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: C.primary),
          )
        else
          TextButton.icon(
            onPressed: () async {
              final bytes = await pickPhoto(context);
              if (bytes != null) setState(() => _logoBytes = bytes);
            },
            icon: const Icon(Icons.upload_outlined, size: 16, color: C.primary),
            label: Text(
              _existingLogoUrl != null ? 'Change Logo' : 'Upload Logo',
              style: GoogleFonts.syne(
                  fontSize: 13, color: C.primary, fontWeight: FontWeight.w700)),
          ),
        if (_logoBytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Unsaved — tap Save to upload',
                style: GoogleFonts.syne(fontSize: 11, color: C.yellow)),
          ),
      ])),
      const SizedBox(height: 8),
      const SLabel('BUSINESS DETAILS'),
      AppField(label: 'Shop Name', controller: _shopName, required: true,
          hint: 'e.g. TechFix Pro'),
      AppField(label: 'Owner / Manager Name', controller: _owner, required: true,
          hint: 'Your full name'),
      AppField(label: 'Business Phone', controller: _phone,
          keyboardType: TextInputType.phone, hint: '+91 XXXXX XXXXX'),
      AppField(label: 'Business Email', controller: _email,
          keyboardType: TextInputType.emailAddress, hint: 'shop@email.com'),
      AppField(label: 'Full Address', controller: _address,
          maxLines: 3, hint: 'Shop number, Street, Area, City, PIN'),
      const SLabel('GST & LEGAL'),
      AppField(label: 'GSTIN Number', controller: _gst,
          hint: '29ABCDE1234F1Z5'),
      _infoBanner('GSTIN will appear on all invoices and receipts.'),
      _SaveBtn(onSave: _save),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 21. DEMO DATA TOOLS
// ═════════════════════════════════════════════════════════════
class DemoDataPage extends ConsumerStatefulWidget {
  const DemoDataPage({super.key});
  @override
  ConsumerState<DemoDataPage> createState() => _DemoDataState();
}

class _DemoDataState extends ConsumerState<DemoDataPage> {
  bool _seeding = false;
  bool _clearing = false;

  Future<void> _seed() async {
    final session = ref.read(currentUserProvider).asData?.value;
    final active = ref.read(activeSessionProvider);
    final shopId = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (session?.shopId ?? '');
    
    setState(() => _seeding = true);
    try {
      await FirebaseDatabase.instance
          .ref('diagnostics/seed/${DateTime.now().millisecondsSinceEpoch}')
          .set({'shopId': shopId, 'status': 'requested'});
    } catch (_) {}
    if (mounted) {
      setState(() => _seeding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Seed data populated successfully!'), backgroundColor: C.green)
      );
    }
  }

  Future<void> _clear() async {
    final session = ref.read(currentUserProvider).asData?.value;
    final active = ref.read(activeSessionProvider);
    final shopId = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (session?.shopId ?? '');
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.bgCard,
        title: Text('Clear All Data?', style: GoogleFonts.syne(fontWeight: FontWeight.w800, color: C.white)),
        content: Text('This will delete all jobs, customers, products, and transactions for this shop. This action cannot be undone.',
            style: GoogleFonts.syne(fontSize: 13, color: C.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: C.red, foregroundColor: C.white),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _clearing = true);
      try {
        final db = FirebaseDatabase.instance;
        final nodes = ['jobs', 'customers', 'products', 'transactions', 'stock_history'];
        final batch = <String, dynamic>{};
        
        for (final node in nodes) {
          final snap = await db.ref(node).orderByChild('shopId').equalTo(shopId).get();
          if (snap.exists) {
            for (final child in snap.children) {
              batch['$node/${child.key}'] = null;
            }
          }
        }
        
        if (batch.isNotEmpty) {
          await db.ref().update(batch);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🗑️ All shop data cleared!'), backgroundColor: C.primary)
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Clear failed: $e'), backgroundColor: C.red)
          );
        }
      } finally {
        if (mounted) setState(() => _clearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Demo Data Tools',
    subtitle: 'Manage test data for your shop',
    children: [
      _infoBanner('Use these tools to quickly populate your shop with sample data for testing features, or to reset your shop data.'),
      
      SCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🌱 Seed Sample Data', style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 15, color: C.white)),
            const SizedBox(height: 8),
            Text('Populates your shop with 3+ samples for every feature: staff, products, customers, jobs, and transactions.',
                style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _seeding ? null : _seed,
                icon: _seeding 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.bg))
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(_seeding ? 'Seeding...' : 'Generate Demo Data', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(backgroundColor: C.primary, foregroundColor: C.bg),
              ),
            ),
          ],
        ),
      ),
      
      const SizedBox(height: 16),
      
      SCard(
        borderColor: C.red.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⚠️ Danger Zone', style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 15, color: C.red)),
            const SizedBox(height: 8),
            Text('Permanently remove all records associated with your shop. Use this to reset before going live.',
                style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _clearing ? null : _clear,
                icon: _clearing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.red))
                  : const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(_clearing ? 'Clearing...' : 'Clear All Shop Data', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(foregroundColor: C.red, side: const BorderSide(color: C.red)),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 2. INVOICE & RECEIPTS
// ═════════════════════════════════════════════════════════════
class InvoicePage extends ConsumerStatefulWidget {
  const InvoicePage({super.key});
  @override
  ConsumerState<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends ConsumerState<InvoicePage> {
  late final TextEditingController _prefix, _footer;
  String _template = 'Standard';
  bool _showQR = true, _showLogo = true, _showTerms = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _prefix   = TextEditingController(text: s.invoicePrefix);
    _template = s.settings['invoiceTemplate'] as String? ?? 'Standard';
    _showQR   = s.settings['invoiceShowQR']   as bool?   ?? true;
    _showLogo = s.settings['invoiceShowLogo'] as bool?   ?? true;
    _showTerms= s.settings['invoiceShowTerms'] as bool?  ?? false;
    _footer   = TextEditingController(
        text: s.settings['invoiceFooter'] as String? ?? 'Thank you for choosing TechFix Pro!');
  }

  @override
  void dispose() { _prefix.dispose(); _footer.dispose(); super.dispose(); }

  Future<void> _save() async {
    final current = ref.read(settingsProvider);
    final newSettings = Map<String, dynamic>.from(current.settings)
      ..['invoiceTemplate'] = _template
      ..['invoiceShowQR']   = _showQR
      ..['invoiceShowLogo'] = _showLogo
      ..['invoiceShowTerms']= _showTerms
      ..['invoiceFooter']   = _footer.text.trim();
    ref.read(settingsProvider.notifier).update(
        current.copyWith(invoicePrefix: _prefix.text.trim(), settings: newSettings));
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final effectiveShopId = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');
    if (effectiveShopId.isEmpty) return;
    if (!mounted) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToFirebase(effectiveShopId),
        successMsg: '✅ Invoice settings saved');
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Invoice & Receipts', subtitle: 'Customise invoice appearance',
    children: [
      const SLabel('NUMBER FORMAT'),
      AppField(label: 'Invoice Number Prefix', controller: _prefix, hint: 'INV'),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.bgElevated,
            borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 16, color: C.textMuted),
          const SizedBox(width: 8),
          Text('Preview: ${_prefix.text.isEmpty ? "INV" : _prefix.text}-2025-0042',
              style: GoogleFonts.syne(fontSize: 13, color: C.text,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
      const SLabel('TEMPLATE STYLE'),
      ...['Standard', 'Branded', 'Minimal', 'Thermal Print'].map((t) {
        final sel = _template == t;
        return GestureDetector(
          onTap: () => setState(() => _template = t),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sel ? C.primary.withValues(alpha: 0.08) : C.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(_templateIcon(t), style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(t, style: GoogleFonts.syne(fontWeight: FontWeight.w700,
                    fontSize: 14, color: sel ? C.primary : C.white)),
                Text(_templateDesc(t), style: GoogleFonts.syne(
                    fontSize: 12, color: C.textMuted)),
              ])),
              if (sel) const Icon(Icons.check_circle, color: C.primary, size: 22),
            ]),
          ),
        );
      }),
      const SLabel('INVOICE OPTIONS'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '📱', title: 'Show QR Code',
            subtitle: 'Payment QR on invoice',
            trailing: Switch(value: _showQR,
                onChanged: (v) => setState(() => _showQR = v))),
        SettingsTile(icon: '🖼️', title: 'Show Shop Logo',
            subtitle: 'Display logo at top',
            trailing: Switch(value: _showLogo,
                onChanged: (v) => setState(() => _showLogo = v))),
        SettingsTile(icon: '📝', title: 'Show T&C',
            subtitle: 'Terms and conditions section',
            trailing: Switch(value: _showTerms,
                onChanged: (v) => setState(() => _showTerms = v))),
      ]),
      AppField(label: 'Invoice Footer Text', controller: _footer, maxLines: 2,
          hint: 'Thank you message or return policy'),
      _SaveBtn(onSave: _save),
    ],
  );

  String _templateIcon(String t) =>
      {'Standard': '📄', 'Branded': '🎨', 'Minimal': '📋', 'Thermal Print': '🖨️'}[t] ?? '📄';
  String _templateDesc(String t) => {
    'Standard': 'Clean professional layout with all details',
    'Branded': 'With shop logo, colors and custom header',
    'Minimal': 'Simple list — fast to print and read',
    'Thermal Print': '58mm/80mm thermal printer compatible',
  }[t] ?? '';
}

// ═════════════════════════════════════════════════════════════
// 3. TAX & GST
// ═════════════════════════════════════════════════════════════
class TaxPage extends ConsumerStatefulWidget {
  const TaxPage({super.key});
  @override
  ConsumerState<TaxPage> createState() => _TaxPageState();
}

class _TaxPageState extends ConsumerState<TaxPage> {
  late final TextEditingController _rate;
  String _taxType = 'GST';
  bool _priceInclusive = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _rate           = TextEditingController(
        text: s.defaultTaxRate.toStringAsFixed(0));
    // taxType & priceInclusive live in the settings sub-map — no model change needed
    _taxType        = s.settings['taxType']        as String? ?? 'GST';
    _priceInclusive = s.settings['priceInclusive'] as bool?   ?? false;
  }
  @override
  void dispose() { _rate.dispose(); super.dispose(); }

  double get _half => (double.tryParse(_rate.text) ?? 18) / 2;

  Future<void> _save() async {
    // No Tax → always 0.0; otherwise use the field value (never fall back to 18)
    final rate = _taxType == 'No Tax' ? 0.0 : (double.tryParse(_rate.text) ?? 0.0);
    final current = ref.read(settingsProvider);
    final newSettings = Map<String, dynamic>.from(current.settings)
      ..['taxType']        = _taxType
      ..['priceInclusive'] = _priceInclusive;

    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final effectiveShopId = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');
    if (effectiveShopId.isEmpty) return;
    // Step 1: Update local settings state immediately so UI reacts at once
    ref.read(settingsProvider.notifier).update(
        current.copyWith(defaultTaxRate: rate, settings: newSettings));

    // Step 2: Push new tax to every active job (local state + Firebase batch write).
    // Past jobs (Delivered / Cancelled) are untouched.
    ref.read(jobsProvider.notifier).reapplyTaxToActiveJobs(
      rate,
      priceInclusive: _priceInclusive,
    );

    // Step 3: Save shop settings to Firebase
    if (!mounted) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToFirebase(effectiveShopId),
        successMsg: '✅ Tax saved — all active job totals updated');
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Tax & GST', subtitle: 'Applied to all repair jobs and POS sales',
    children: [
      const SLabel('TAX TYPE'),
      Row(children: ['GST', 'VAT', 'No Tax'].map((t) {
        final sel = _taxType == t;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: t == 'No Tax' ? 0 : 8),
          child: GestureDetector(
            onTap: () => setState(() => _taxType = t),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: sel ? C.primary.withValues(alpha: 0.15) : C.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
              ),
              child: Column(children: [
                Text(t == 'GST' ? '🇮🇳' : t == 'VAT' ? '💶' : '🚫',
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text(t, style: GoogleFonts.syne(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: sel ? C.primary : C.textMuted)),
              ]),
            ),
          ),
        ));
      }).toList()),
      const SizedBox(height: 16),
      if (_taxType != 'No Tax') ...[
        AppField(label: 'Default Tax Rate (%)', controller: _rate,
            keyboardType: TextInputType.number,
            hint: '18', suffix: const Icon(Icons.percent, size: 16, color: C.textMuted),
            onChanged: (_) => setState(() {})),
        SettingsGroup(title: '', tiles: [
          SettingsTile(icon: '💰', title: 'Prices are tax-inclusive',
              subtitle: 'Tax is extracted from selling price',
              trailing: Switch(value: _priceInclusive,
                  onChanged: (v) => setState(() => _priceInclusive = v))),
        ]),
        SCard(child: Column(children: [
          _taxRow('CGST (Central)',  '$_half%', _half),
          const Divider(color: C.border, height: 16),
          _taxRow('SGST (State)',    '$_half%', _half),
          const Divider(color: C.border, height: 16),
          _taxRow('Total GST',      '${_rate.text}%',
              double.tryParse(_rate.text) ?? 18,  bold: true),
        ])),
        const SizedBox(height: 16),
        _infoBanner(
          'On ₹1,000 service:  CGST = ₹${(_half * 10).toStringAsFixed(0)}  +  '
          'SGST = ₹${(_half * 10).toStringAsFixed(0)}  =  '
          'Total ₹${((double.tryParse(_rate.text) ?? 18) * 10).toStringAsFixed(0)} tax',
        ),
      ],
      _SaveBtn(onSave: _save),
    ],
  );

  Widget _taxRow(String l, String r, double v, {bool bold = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: GoogleFonts.syne(fontSize: 13,
            color: bold ? C.white : C.textMuted,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        Text(r, style: GoogleFonts.syne(fontSize: 14,
            fontWeight: FontWeight.w800, color: C.primary)),
      ]);
}

// ═════════════════════════════════════════════════════════════
// 4. PAYMENT METHODS
// ═════════════════════════════════════════════════════════════
class PaymentMethodsPage extends ConsumerStatefulWidget {
  const PaymentMethodsPage({super.key});
  @override
  ConsumerState<PaymentMethodsPage> createState() => _PayMethodsState();
}

class _PayMethodsState extends ConsumerState<PaymentMethodsPage> {
  late Map<String, bool> _methods;
  final _allOptions = [
    'Cash', 'Card (Debit/Credit)', 'UPI (GPay/PhonePe)',
    'Paytm Wallet', 'Net Banking', 'Bank Transfer (NEFT)',
    'EMI', 'Store Credit',
  ];
  final _icons = <String, String>{
    'Cash': '💵', 'Card (Debit/Credit)': '💳', 'UPI (GPay/PhonePe)': '📱',
    'Paytm Wallet': '👛', 'Net Banking': '🏦', 'Bank Transfer (NEFT)': '🔄',
    'EMI': '📆', 'Store Credit': '🎁',
  };

  @override
  void initState() {
    super.initState();
    final enabled = ref.read(settingsProvider).enabledPayments;
    _methods = { for (var opt in _allOptions) opt : enabled.contains(opt) };
  }

  Future<void> _save() async {
    final enabled = _methods.entries.where((e) => e.value).map((e) => e.key).toList();
    ref.read(settingsProvider.notifier).update(
        ref.read(settingsProvider).copyWith(enabledPayments: enabled));
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final effectiveShopId = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');
    if (effectiveShopId.isEmpty) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToFirebase(effectiveShopId));
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Payment Methods', subtitle: 'Enable methods at POS checkout',
    children: [
      _infoBanner('Enabled methods will appear on the POS screen and invoices.'),
      SettingsGroup(title: 'PAYMENT OPTIONS', tiles: _methods.entries.map((e) =>
          SettingsTile(
            icon: _icons[e.key] ?? '💰',
            title: e.key,
            subtitle: e.value ? 'Enabled at POS' : 'Disabled',
            trailing: Switch(value: e.value,
                onChanged: (v) => setState(() => _methods[e.key] = v)),
          )).toList()),
      _SaveBtn(onSave: _save),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 5. STAFF
// ═════════════════════════════════════════════════════════════
class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({super.key});
  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends ConsumerState<StaffPage> {
  @override
  Widget build(BuildContext context) {
    final ref   = this.ref;
    // Watch techsProvider — now contains ALL roles (owner excluded)
    final techs  = ref.watch(techsProvider);
    final active = techs.where((t) => t.isActive).length;

    return _Page(
      title: 'Staff', subtitle: '$active active · ${techs.length} total',
      fab: FloatingActionButton.extended(
        heroTag: 'fab_staff',
        backgroundColor: C.primary, foregroundColor: C.bg,
        icon: const Icon(Icons.person_add_outlined),
        label: Text('Add Staff', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StaffFormPage())),
      ),
      children: [
        if (techs.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(children: [
              const Text('👨‍🔧', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('No staff added', style: GoogleFonts.syne(
                  fontSize: 16, color: C.textMuted)),
            ]),
          )),
        ...techs.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StaffFormPage(staff: t))),
            child: SCard(
              borderColor: t.isActive ? null : C.red.withValues(alpha: 0.3),
              child: Row(children: [
                Stack(children: [
                  CircleAvatar(radius: 26,
                    backgroundColor: (t.isActive ? C.primary : C.textDim).withValues(alpha: 0.15),
                    child: Text(t.name.isNotEmpty ? t.name[0] : '?',
                        style: GoogleFonts.syne(
                        fontWeight: FontWeight.w800, fontSize: 18,
                        color: t.isActive ? C.primary : C.textMuted)),
                  ),
                  Positioned(bottom: 0, right: 0, child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: t.isActive ? C.green : C.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.bgCard, width: 2),
                    ),
                  )),
                ]),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Flexible(child: Text(t.name, style: GoogleFonts.syne(
                        fontWeight: FontWeight.w700, fontSize: 15, color: C.white),
                        overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    // ✅ Use role from Technician object — no Firebase fetch needed
                    _rolePill(t.role),
                  ]),
                  Text(t.specialization, style: GoogleFonts.syne(
                      fontSize: 12, color: C.primary)),
                  const SizedBox(height: 2),
                  Row(children: [
                    _statChip('🔧', '${t.totalJobs} jobs'),
                    const SizedBox(width: 8),
                    _statChip('⭐', t.rating.toStringAsFixed(1)),
                    if (t.phone.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _statChip('📞', t.phone),
                    ],
                  ]),
                ])),
                Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: C.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.edit_outlined, color: C.primary, size: 16)),
              ]),
            ),
          ),
        )),
      ],
    );
  }

  Widget _statChip(String icon, String val) => Row(children: [
    Text(icon, style: const TextStyle(fontSize: 11)),
    const SizedBox(width: 3),
    Text(val, style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
  ]);

  // ✅ Fixed: takes role string directly — no async Firebase fetch per card
  Widget _rolePill(String role) {
    Color color = C.primary; // technician
    String emoji = '🔧';
    if (role == 'admin')     { color = C.yellow; emoji = '👑'; }
    if (role == 'manager')   { color = C.accent;  emoji = '🎯'; }
    if (role == 'reception') { color = C.green;   emoji = '💁'; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text('$emoji ${role.toUpperCase()}',
          style: GoogleFonts.syne(fontSize: 8, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class StaffFormPage extends ConsumerStatefulWidget {
  final Technician? staff;
  const StaffFormPage({super.key, this.staff});
  @override
  ConsumerState<StaffFormPage> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<StaffFormPage> {
  late final TextEditingController _name, _phone, _spec, _rating, _pin;
  late bool _isActive;
  late String _role;
  bool get _isEdit => widget.staff != null;

  // Role metadata — emoji, label, color
  static const _roleMeta = <String, (String, String, Color)>{
    'technician': ('🔧', 'Technician', Color(0xFFFF9800)),
    'manager':    ('🎯', 'Manager',    Color(0xFF00BCD4)),
    'reception':  ('💁', 'Reception',  Color(0xFF4CAF50)),
    'admin':      ('👑', 'Admin',      Color(0xFF9B59B6)),
  };
  static const _roles = ['technician', 'manager', 'reception', 'admin'];

  @override
  void initState() {
    super.initState();
    final t = widget.staff;
    _name     = TextEditingController(text: t?.name ?? '');
    _phone    = TextEditingController(text: t?.phone ?? '');
    _spec     = TextEditingController(text: t?.specialization ?? 'General');
    _rating   = TextEditingController(text: t?.rating.toStringAsFixed(1) ?? '5.0');
    _pin      = TextEditingController(text: t?.pin ?? '');
    _isActive = t?.isActive ?? true;
    // ✅ Role comes from Technician.role (now a real field).
    // For existing staff, Technician.role is populated by the realtime listener
    // from users/$uid/role in main.dart. No separate async fetch needed.
    _role = t?.role ?? 'technician';
  }

  // ✅ Removed didChangeDependencies + _loadExistingRole — no longer needed
  // because Technician.role is now passed directly from techsProvider.

  @override
  void dispose() {
    for (final c in [_name, _phone, _spec, _rating, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    // ── Validation ────────────────────────────────────────────
    final name = _name.text.trim();
    final pin  = _pin.text.trim();
    if (name.isEmpty) {
      _snack('Name is required', C.red); return;
    }
    if (pin.isNotEmpty && pin.length != 4) {
      _snack('PIN must be exactly 4 digits', C.red); return;
    }

    // Use activeSessionProvider first — it's set on PIN entry and stays current.
    // currentUserProvider only fires on Firebase Auth state change, so it can
    // be stale (empty shopId) when owner resumes via lock screen PIN.
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final shopId  = (active?.shopId.isNotEmpty == true)
        ? active!.shopId
        : (stream?.shopId ?? '');
    if (shopId.isEmpty) {
      _snack('Not logged in — please tap your name on the lock screen first.', C.red);
      return;
    }

    final existing = widget.staff;
    final id  = existing?.techId ?? 'staff_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    final tech = (existing ?? Technician(
      techId: id, shopId: shopId, name: '',
    )).copyWith(
      name: name,
      phone: _phone.text.trim(),
      specialization: _spec.text.trim().isEmpty ? 'General' : _spec.text.trim(),
      isActive: _isActive,
      rating: double.tryParse(_rating.text) ?? 5.0,
      pin: pin,
      role: _role,
    );

    final db = FirebaseDatabase.instance;

    // Single write — users/$id only (staff/ and technicians/ nodes removed)
    final userRecord = <String, dynamic>{
      'uid':            id,
      'displayName':    tech.name,
      'phone':          tech.phone,
      'email':          '',
      'role':           _role,
      'shopId':         shopId,
      'isActive':       tech.isActive,
      'isOwner':        false,
      'pin':            pin,
      'pin_hash':       '',
      'biometricEnabled': false,
      'specialization': tech.specialization,
      'totalJobs':      tech.totalJobs,
      'completedJobs':  tech.completedJobs,
      'rating':         tech.rating,
      'joinedAt':       existing != null
          ? (existing.joinedAt.isEmpty ? now : existing.joinedAt)
          : now,
      'createdAt':      existing != null
          ? (existing.joinedAt.isEmpty ? now : existing.joinedAt)
          : now,
      'updatedAt':      now,
    };

    try {
      await db.ref('users/$id').update(userRecord);

      // Update staffProvider — techsProvider auto-updates as a derived view
      await ref.read(staffProvider.notifier).loadFromFirebase(shopId);

      if (mounted) {
        _snack(_isEdit ? '✅ Staff updated' : '✅ Staff added', C.green);
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.of(context).pop();
      }
    } on FirebaseException catch (e) {
      final msg = e.code == 'permission-denied'
          ? 'PERMISSION_DENIED — check shops/$shopId/isActive = true in Firebase'
          : 'Firebase error: ${e.code} — ${e.message ?? ""}';
      if (mounted) _snack(msg, C.red);
    } catch (e) {
      if (mounted) _snack('Save failed: $e', C.red);
    }
  }

  Future<void> _deleteStaff() async {
    final staff = widget.staff!;
    final id    = staff.techId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove ${staff.name}?',
            style: GoogleFonts.syne(fontWeight: FontWeight.w800, color: C.white)),
        content: Text('This removes them from staff and job assignment. '
            'Their existing jobs are not deleted.',
            style: GoogleFonts.syne(fontSize: 13, color: C.textMuted, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.syne(color: C.textMuted))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: C.red,
                  foregroundColor: C.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text('Remove', style: GoogleFonts.syne(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // Hard-delete: removes from Firebase AND local state instantly.
      // The real-time listener in main.dart also skips isActive=false,
      // so the staff list updates immediately without any reload.
      await ref.read(staffProvider.notifier).removeFromFirebase(id);
      if (mounted) {
        _snack('✅ ${staff.name} removed', C.green);
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) Navigator.of(context).pop();
      }
    } on FirebaseException catch (e) {
      if (mounted) _snack('Delete failed: ${e.code}', C.red);
    } catch (e) {
      if (mounted) _snack('Delete failed: $e', C.red);
    }
  }

  void _snack(String msg, Color bg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 13)),
        backgroundColor: bg, behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4)));

  @override
  Widget build(BuildContext context) => _Page(
    title: _isEdit ? 'Edit Staff' : 'New Staff',
    subtitle: _isEdit ? widget.staff!.name : 'Add a team member',
    actions: [TextButton(onPressed: _save,
        child: Text('Save', style: GoogleFonts.syne(
            fontWeight: FontWeight.w800, color: C.primary, fontSize: 15)))],
    children: [
      // ── Avatar preview ──────────────────────────────────────
      Center(child: CircleAvatar(radius: 36,
        backgroundColor: (_roleMeta[_role]?.$3 ?? C.primary).withValues(alpha: 0.15),
        child: Text(
          _name.text.isEmpty ? '?' : _name.text[0].toUpperCase(),
          style: GoogleFonts.syne(fontWeight: FontWeight.w900,
              fontSize: 28,
              color: _roleMeta[_role]?.$3 ?? C.primary),
        ),
      )),
      const SizedBox(height: 20),

      const SLabel('STAFF DETAILS'),
      AppField(label: 'Full Name', controller: _name, required: true,
          hint: 'e.g. Suresh Kumar', onChanged: (_) => setState(() {})),
      AppField(label: 'Phone Number', controller: _phone,
          keyboardType: TextInputType.phone, hint: '+91 XXXXX XXXXX'),
      AppField(label: 'Staff Login PIN (4 digits)', controller: _pin,
          keyboardType: TextInputType.number, hint: '1234', obscureText: true),

      // ── Role selector ───────────────────────────────────────
      // ✅ Chip-based selector — no DropdownButtonFormField initialValue bug
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('ROLE', style: GoogleFonts.syne(
              fontSize: 10, fontWeight: FontWeight.w800,
              color: C.textMuted, letterSpacing: 1.0)),
          const SizedBox(width: 8),
          // Show currently selected role as a coloured badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (_roleMeta[_role]?.$3 ?? C.primary).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: (_roleMeta[_role]?.$3 ?? C.primary).withValues(alpha: 0.4)),
            ),
            child: Text(
              '${_roleMeta[_role]?.$1 ?? ''} ${_role.toUpperCase()}',
              style: GoogleFonts.syne(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: _roleMeta[_role]?.$3 ?? C.primary),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8,
          children: _roles.map((r) {
            final meta = _roleMeta[r]!;
            final sel  = _role == r;
            return GestureDetector(
              onTap: () => setState(() => _role = r),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? meta.$3.withValues(alpha: 0.15) : C.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel ? meta.$3 : C.border,
                      width: sel ? 1.5 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(meta.$1, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, children: [
                    Text(meta.$2, style: GoogleFonts.syne(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: sel ? meta.$3 : C.text)),
                    Text(_roleDesc(r), style: GoogleFonts.syne(
                        fontSize: 9, color: sel ? meta.$3.withValues(alpha: 0.8) : C.textMuted)),
                  ]),
                ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ]),

      AppField(label: 'Specialization', controller: _spec,
          hint: 'iOS Repair, Screen Replacement, Water Damage...'),
      AppField(label: 'Rating (0–5)', controller: _rating,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: '5.0'),

      SettingsGroup(title: 'STATUS', tiles: [
        SettingsTile(icon: '✅', title: 'Active',
            subtitle: _isActive
                ? 'Can be assigned to jobs'
                : 'Inactive — not shown in job assignment',
            trailing: Switch(value: _isActive,
                onChanged: (v) => setState(() => _isActive = v))),
      ]),

      _SaveBtn(onSave: _save, label: _isEdit ? '💾  Update Staff' : '➕  Add Staff'),
      if (_isEdit) ...[
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, height: 50,
          child: OutlinedButton(
            onPressed: _deleteStaff,
            style: OutlinedButton.styleFrom(foregroundColor: C.red,
                side: const BorderSide(color: C.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('🗑️  Remove Staff', style: GoogleFonts.syne(
                fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
      ],
    ],
  );

  String _roleDesc(String role) => switch (role) {
    'technician' => 'Repairs · job updates',
    'manager'    => 'All ops · no billing',
    'reception'  => 'Jobs · customers · POS',
    'admin'      => 'Full access',
    _            => '',
  };
}

// ═════════════════════════════════════════════════════════════
// 6. REPAIR WORKFLOW
// ═════════════════════════════════════════════════════════════
class WorkflowPage extends ConsumerStatefulWidget {
  const WorkflowPage({super.key});
  @override
  ConsumerState<WorkflowPage> createState() => _WorkflowState();
}

class _WorkflowState extends ConsumerState<WorkflowPage> {
  late List<Map<String, String>> _stages;

  @override
  void initState() {
    super.initState();
    _stages = List.from(ref.read(settingsProvider).workflowStages);
  }

  Future<void> _save() async {
    ref.read(settingsProvider.notifier).update(
        ref.read(settingsProvider).copyWith(workflowStages: _stages));
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final effectiveShopId = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');
    if (effectiveShopId.isEmpty) return;
    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToFirebase(effectiveShopId));
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Repair Workflow', subtitle: '${_stages.length} customizable stages',
    children: [
      _infoBanner('These stages appear in the status dropdown when managing repair jobs.'),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (oldIdx, newIdx) {
          setState(() {
            if (newIdx > oldIdx) newIdx -= 1;
            final item = _stages.removeAt(oldIdx);
            _stages.insert(newIdx, item);
          });
        },
        children: _stages.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          final sc = C.statusColor(s['title'] ?? '');
          return SCard(
            key: ValueKey(i),
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 32, height: 32,
                decoration: BoxDecoration(color: sc.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Center(child: Text(s['icon'] ?? '⚙️', style: const TextStyle(fontSize: 16)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(s['title'] ?? '', style: GoogleFonts.syne(fontWeight: FontWeight.w700,
                    fontSize: 14, color: C.white)),
                Text(s['desc'] ?? '', style: GoogleFonts.syne(
                    fontSize: 11, color: C.textMuted)),
              ])),
              const Icon(Icons.drag_indicator, color: C.textDim, size: 20),
            ]),
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      _SaveBtn(onSave: _save),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 7. WARRANTY RULES
// ═════════════════════════════════════════════════════════════
class WarrantyPage extends ConsumerStatefulWidget {
  const WarrantyPage({super.key});
  @override
  ConsumerState<WarrantyPage> createState() => _WarrantyPageState();
}

class _WarrantyPageState extends ConsumerState<WarrantyPage> {
  late final TextEditingController _days;

  final _rules = <String, TextEditingController>{
    'Screen Replacement':   TextEditingController(text: '90'),
    'Battery Replacement':  TextEditingController(text: '180'),
    'Water Damage Repair':  TextEditingController(text: '30'),
    'Charging Port Repair': TextEditingController(text: '60'),
    'Software Repair':      TextEditingController(text: '7'),
    'Camera Repair':        TextEditingController(text: '60'),
    'Speaker / Mic Repair': TextEditingController(text: '45'),
    'Back Glass Repair':    TextEditingController(text: '30'),
  };

  /// Converts a repair type name to a Firebase-safe key.
  /// Replaces spaces, slashes, and any other illegal chars with underscores,
  /// then collapses consecutive underscores and lowercases everything.
  /// e.g. "Speaker / Mic Repair" → "speaker_mic_repair"
  static String _safeKey(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _days = TextEditingController(text: s.defaultWarrantyDays.toString());
    for (final e in _rules.entries) {
      // Try safe key first, fall back to legacy raw key for backwards compat
      final safeKey  = 'warranty_${_safeKey(e.key)}';
      final legacyKey = 'warranty_${e.key}';
      final saved = s.settings[safeKey] ?? s.settings[legacyKey];
      if (saved != null) e.value.text = saved.toString();
    }
  }

  @override
  void dispose() {
    _days.dispose();
    for (final c in _rules.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final current = ref.read(settingsProvider);
    final newSettings = Map<String, dynamic>.from(current.settings);
    for (final e in _rules.entries) {
      // Use safe Firebase key — no spaces, slashes, or special chars
      newSettings['warranty_${_safeKey(e.key)}'] = int.tryParse(e.value.text) ?? 30;
    }
    ref.read(settingsProvider.notifier).update(current.copyWith(
        defaultWarrantyDays: int.tryParse(_days.text) ?? 30, settings: newSettings));
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final effectiveShopId = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');
    if (effectiveShopId.isEmpty) return;

    // Build a summary line: "Screen 90d · Battery 180d · ..."
    final summary = _rules.entries.map((e) {
      final days = int.tryParse(e.value.text) ?? 30;
      // Shorten label: take first word only for compactness
      final short = e.key.split(' ').first;
      return '$short ${days}d';
    }).join(' · ');

    await _shopSave(context, ref,
        () => ref.read(settingsProvider.notifier).saveToFirebase(effectiveShopId),
        successMsg: '✅ Warranty saved — $summary');
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Warranty Rules', subtitle: 'Post-repair warranty periods',
    children: [
      AppField(label: 'Global Default Warranty (Days)', controller: _days,
          keyboardType: TextInputType.number, hint: '30'),
      _infoBanner('This default applies when no specific rule matches the repair type.'),
      const SLabel('BY REPAIR TYPE'),
      ..._rules.entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(e.key, style: GoogleFonts.syne(
              fontSize: 13, color: C.text))),
          SizedBox(width: 90,
            child: TextFormField(
              controller: e.value,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(fontSize: 13, color: C.white,
                  fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  suffixText: 'days',
                  suffixStyle: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
            ),
          ),
        ]),
      )),
      const SizedBox(height: 16),
      _SaveBtn(onSave: _save),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 7. FIREBASE DIAGNOSTICS  (v2 — full node coverage)
// ═════════════════════════════════════════════════════════════
//
// Nodes / operations tested (every R/W the app performs):
//   0  Firebase SDK init
//   1  RTDB socket connection (.info/connected)
//   2  Auth — signed-in user
//   3  users/$uid          READ  own record (role, shopId, isActive)
//   4  users/$uid          WRITE lastLoginAt  (runs on every login)
//   5  shops/$shopId       READ
//   6  shops/$shopId       WRITE (all Settings sub-pages save here)
//   7  users (shopId idx)  READ  staff list (User Roles & Staff pages)
//   8  users/$uid          READ  own record fields (joinedAt, rating, totalJobs)
//   9  users               READ  full shop staff list (job assign, POS)
//  10  users/$uid          WRITE isActive toggle (User Roles page)
//  11  users/$uid          WRITE role change     (User Roles page)
//  12  users/$uid          WRITE PIN reset       (User Roles page)
//  13  users/$uid          WRITE add/edit staff  (Staff page)
//  14  users/$uid          WRITE isActive toggle (Staff remove / soft-delete)
//  15  customers           READ  (Jobs / Customers screens + Demo clear)
//  16  jobs                READ  (Jobs screen + Demo clear)
//  17  products            READ  (Inventory + POS + Demo clear)
//  18  transactions        READ  (Finance + Demo clear)
//  19  stock_history       READ  (Demo clear)
//  20  diagnostics/$uid    WRITE self-log (should always pass)
// ─────────────────────────────────────────────────────────────

/// Result for a single diagnostic check.
class _DiagResult {
  final String label;
  final String detail;
  final Color  color;
  const _DiagResult(this.label, this.detail, this.color);
}

class FirebaseDiagnosticsPage extends ConsumerStatefulWidget {
  const FirebaseDiagnosticsPage({super.key});
  @override
  ConsumerState<FirebaseDiagnosticsPage> createState() =>
      _FirebaseDiagnosticsPageState();
}

class _FirebaseDiagnosticsPageState
    extends ConsumerState<FirebaseDiagnosticsPage> {

  bool _running = false;
  bool _hasRun  = false;
  final List<_DiagResult> _results = [];

  static const _timeout = Duration(seconds: 8);

  // ── Error formatter ────────────────────────────────────────
  String _fmt(Object e) {
    final s = e.toString();
    final m = RegExp(r'\[([^\]]+)\]').firstMatch(s);
    if (m != null) {
      final code = m.group(1)!;
      if (code.contains('permission-denied')) return 'PERMISSION_DENIED — security rule blocked this';
      if (code.contains('network'))           return 'NETWORK_ERROR — device offline or RTDB unreachable';
      if (code.contains('unavailable'))       return 'SERVICE_UNAVAILABLE — Firebase temporarily down';
      return code;
    }
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'TIMEOUT (>8 s) — likely offline or rule hangs read';
    }
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }

  _DiagResult _ok(String label, String detail)   => _DiagResult(label, '✅  $detail', C.green);
  _DiagResult _warn(String label, String detail)  => _DiagResult(label, '⚠️  $detail', C.yellow);
  _DiagResult _fail(String label, String detail)  => _DiagResult(label, '❌  $detail', C.red);
  _DiagResult _skip(String label, String detail)  => _DiagResult(label, '—  $detail', C.textMuted);

  void _add(_DiagResult r) { _results.add(r); if (mounted) setState(() {}); }
  void _done()              { if (mounted) setState(() => _running = false); }

  // ══════════════════════════════════════════════════════════
  Future<void> _run() async {
    setState(() { _running = true; _hasRun = true; _results.clear(); });

    final db   = FirebaseDatabase.instance;
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;

    // ── 0. Firebase SDK ───────────────────────────────────────
    if (Firebase.apps.isEmpty) {
      _add(_fail('0 · Firebase SDK', 'No Firebase app initialised — check main.dart → Firebase.initializeApp().'));
      _done(); return;
    }
    _add(_ok('0 · Firebase SDK', 'App initialised (${Firebase.apps.length} app(s))'));

    // ── 1. RTDB socket connection ─────────────────────────────
    await () async {
      try {
        bool? connected;
        await db.ref('.info/connected')
            .onValue
            .timeout(_timeout)
            .firstWhere((event) {
          connected = event.snapshot.value as bool?;
          return connected != null;
        });
        if (connected == true) {
          _add(_ok('1 · RTDB Connection', 'Live socket connected to Firebase Realtime Database'));
        } else {
          _add(_warn('1 · RTDB Connection',
              'connected=false — SDK up but no live socket.\n'
              '  Causes: device offline · wrong databaseURL · project region mismatch'));
        }
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('TimeoutException') || msg.contains('timed out') || e is TimeoutException) {
          _add(_fail('1 · RTDB Connection',
              'Timed out (8 s) — .info/connected did not respond.\n'
              '  Device is likely offline or databaseURL is wrong.'));
        } else {
          _add(_fail('1 · RTDB Connection', _fmt(e)));
        }
      }
    }();

    // ── 2. Auth ───────────────────────────────────────────────
    if (user == null) {
      _add(_fail('2 · Auth', 'No signed-in user — all DB operations will be denied. Log in first.'));
      _done(); return;
    }
    if (user.isAnonymous) {
      _add(_warn('2 · Auth',
          'Anonymous session (uid: ${user.uid})\n'
          '  Most rules require email auth — sign in with email to access shop data.'));
    } else {
      _add(_ok('2 · Auth',
          'Email: ${user.email}  ·  UID: ${user.uid}\n'
          '  Email verified: ${user.emailVerified}'));
    }

    final uid = user.uid;

    // ── 3. users/$uid READ (own record) ──────────────────────
    String? userShopId;
    String? userRole;
    bool    userIsActive = false;
    await () async {
      try {
        final snap = await db.ref('users/$uid').get().timeout(_timeout);
        if (!snap.exists) {
          _add(_fail('3 · users/\$uid READ',
              'Node missing — this UID has no user record.\n'
              '  Fix: create users/$uid in Firebase Console with\n'
              '       shopId, role, isActive=true, email fields.'));
          return;
        }
        final d = Map<String, dynamic>.from(snap.value as Map);
        userShopId   = d['shopId']   as String?;
        userRole     = d['role']     as String?;
        userIsActive = (d['isActive'] as bool?) ?? false;
        final issues = <String>[];
        if (userShopId == null || userShopId!.isEmpty) issues.add('shopId missing');
        if (userRole   == null || userRole!.isEmpty)   issues.add('role missing');
        if (!userIsActive)                             issues.add('isActive=false → login blocked');
        if (issues.isEmpty) {
          _add(_ok('3 · users/\$uid READ',
              'shopId: $userShopId  ·  role: $userRole  ·  isActive: true'));
        } else {
          _add(_warn('3 · users/\$uid READ',
              'shopId: $userShopId  ·  role: $userRole  ·  isActive: $userIsActive\n'
              '  Issues: ${issues.join(' | ')}'));
        }
      } catch (e) {
        _add(_fail('3 · users/\$uid READ', _fmt(e)));
      }
    }();

    final shopId = userShopId ?? ref.read(currentUserProvider).asData?.value?.shopId ?? '';
    final role   = userRole   ?? ref.read(currentUserProvider).asData?.value?.role   ?? '';

    // ── 4. users/$uid WRITE — lastLoginAt ────────────────────
    await () async {
      try {
        await db.ref('users/$uid/lastLoginAt')
            .set(DateTime.now().toIso8601String())
            .timeout(_timeout);
        _add(_ok('4 · users/\$uid WRITE (lastLoginAt)',
            'Write OK — session tracking will work'));
      } catch (e) {
        _add(_fail('4 · users/\$uid WRITE (lastLoginAt)',
            '${_fmt(e)}\n'
            '  Rule should allow auth.uid==\$uid to write own record.\n'
            '  Impact: session timestamp not updated (non-critical but rule mismatch).'));
      }
    }();

    // ── 5. shops/$shopId READ ─────────────────────────────────
    bool shopIsActive = false;
    if (shopId.isEmpty) {
      _add(_skip('5 · shops/\$shopId READ', 'Skipped — no shopId on user record'));
    } else {
      try {
        final snap = await db.ref('shops/$shopId').get().timeout(_timeout);
        if (!snap.exists) {
          _add(_fail('5 · shops/\$shopId READ',
              'shops/$shopId does not exist.\n'
              '  Fix: run onboarding again or create the node manually in Firebase Console.'));
        } else {
          final d = Map<String, dynamic>.from(snap.value as Map);
          shopIsActive = (d['isActive'] as bool?) ?? false;
          final name   = d['shopName'] as String? ?? '(unnamed)';
          final plan   = d['plan']     as String? ?? '(no plan)';
          if (shopIsActive) {
            _add(_ok('5 · shops/\$shopId READ',
                'Name: $name  ·  Plan: $plan  ·  isActive: true'));
          } else {
            _add(_fail('5 · shops/\$shopId READ',
                'isActive=$shopIsActive — shop is inactive.\n'
                '  ALL settings writes (Shop Profile, Tax, Invoice, Payment Methods,\n'
                '  Warranty, Workflow, WhatsApp, SMS, etc.) will be PERMISSION_DENIED.\n'
                '  Fix: Firebase Console → shops → $shopId → isActive = true (Boolean)'));
          }
        }
      } catch (e) {
        _add(_fail('5 · shops/\$shopId READ', _fmt(e)));
      }
    }

    // ── 6. shops/$shopId WRITE ────────────────────────────────
    if (shopId.isEmpty) {
      _add(_skip('6 · shops/\$shopId WRITE', 'Skipped — no shopId'));
    } else if (!shopIsActive) {
      _add(_fail('6 · shops/\$shopId WRITE',
          'BLOCKED by isActive check (see test 5).\n'
          '  ALL settings sub-pages (Profile, Tax, Invoice, Payments, Warranty…)\n'
          '  will fail with PERMISSION_DENIED until isActive=true.'));
    } else {
      try {
        await db.ref('shops/$shopId/_diagTest')
            .set(DateTime.now().millisecondsSinceEpoch)
            .timeout(_timeout);
        await db.ref('shops/$shopId/_diagTest').remove().timeout(_timeout);
        _add(_ok('6 · shops/\$shopId WRITE',
            'Write + delete OK — all Settings pages will save successfully\n'
            '  (Shop Profile · Invoice · Tax · Payment Methods · Warranty · Workflow…)'));
      } catch (e) {
        _add(_fail('6 · shops/\$shopId WRITE',
            '${_fmt(e)}\n'
            '  Rule requires: isActive=true AND role in [admin, manager]\n'
            '  Your role: $role\n'
            '  Impact: every Settings save button will fail.'));
      }
    }

    // ── 7. users (shopId index) READ — staff list ─────────────
    if (shopId.isEmpty) {
      _add(_skip('7 · users READ (staff list)', 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('users')
            .orderByChild('shopId').equalTo(shopId)
            .get().timeout(_timeout);
        final count = (snap.exists && snap.value is Map)
            ? (snap.value as Map).length : 0;
        if (count > 0) {
          _add(_ok('7 · users READ (staff list)',
              '$count user(s) found for shopId=$shopId\n'
              '  User Roles page and staff list will load correctly.'));
        } else {
          _add(_warn('7 · users READ (staff list)',
              'Query succeeded but 0 users have shopId=$shopId.\n'
              '  User Roles / Staff pages will appear empty.\n'
              '  Fix: ensure every user record has shopId="$shopId" in DB.'));
        }
      } catch (e) {
        _add(_fail('7 · users READ (staff list)',
            '${_fmt(e)}\n'
            '  Rule must allow orderByChild("shopId") queries for authenticated users.\n'
            '  Missing index? Add ".indexOn": ["shopId"] to users/ in rules.'));
      }
    }

    // ── 8. users/$uid READ — own stats fields ────────────
    await () async {
      try {
        final snap = await db.ref('users/$uid').get().timeout(_timeout);
        if (snap.exists && snap.value is Map) {
          final d = Map<String, dynamic>.from(snap.value as Map);
          final active      = (d['isActive'] as bool?) ?? false;
          final totalJobs   = d['totalJobs']   ?? 0;
          final rating      = d['rating']      ?? 5.0;
          final hasJoinedAt = d.containsKey('joinedAt');
          _add(_ok('8 · users/\$uid READ (own stats)',
              'Record OK  ·  isActive: $active  ·  totalJobs: $totalJobs  ·  rating: $rating\n'
              '  joinedAt field present: $hasJoinedAt\n'
              '  All staff stats live in users/ — no separate staff/ node needed.'));
        } else {
          _add(_warn('8 · users/\$uid READ (own stats)',
              'users/$uid exists but has no fields.\n'
              '  Try logging out and signing back in to re-initialise.'));
        }
      } catch (e) {
        _add(_fail('8 · users/\$uid READ (own stats)', _fmt(e)));
      }
    }();

    // ── 9. users READ — full shop staff list ─────────────
    if (shopId.isEmpty) {
      _add(_skip('9 · users READ (shop staff list)', 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('users')
            .orderByChild('shopId').equalTo(shopId)
            .get().timeout(_timeout);
        final count = (snap.exists && snap.value is Map)
            ? (snap.value as Map).length : 0;
        if (count > 0) {
          _add(_ok('9 · users READ (shop staff list)',
              '$count user record(s) for this shop.\n'
              '  Staff page and job-assign dropdown will load correctly.\n'
              '  (staff/ and technicians/ nodes removed — all data in users/)'));
        } else {
          _add(_warn('9 · users READ (shop staff list)',
              'Query OK but 0 users for shopId=$shopId.\n'
              '  Staff page will be empty — add at least one staff member.'));
        }
      } catch (e) {
        _add(_fail('9 · users READ (shop staff list)',
            '${_fmt(e)}\n'
            '  Ensure ".indexOn": ["shopId"] on the users/ node in rules.'));
      }
    }

    // ── 10 & 11: Find a non-owner staff member to test against ────────────
    // Tests 10 & 11 MUST write to a DIFFERENT (non-owner) user uid, not own.
    // The rule's isOwner!=true guard on TARGET blocks writing to any record
    // where isOwner==true — including the logged-in admin's own record.
    // Writing to own uid here would always fail and give a false positive FAIL.
    String? otherUid;
    if (shopId.isNotEmpty && (role == 'admin' || role == 'manager')) {
      try {
        final staffSnap = await db.ref('users')
            .orderByChild('shopId').equalTo(shopId)
            .get().timeout(_timeout);
        if (staffSnap.exists && staffSnap.value is Map) {
          final staffMap = Map<String, dynamic>.from(staffSnap.value as Map);
          for (final entry in staffMap.entries) {
            if (entry.key == uid) continue;           // skip self
            final d = Map<String, dynamic>.from(entry.value as Map? ?? {});
            if ((d['isOwner'] as bool?) == true) continue;
            otherUid = entry.key;
            break;
          }
        }
      } catch (_) {}
    }

    // ── 10. users/$otherUid WRITE isActive (User Roles toggle) ─────
    if (shopId.isEmpty || role == 'technician' || role == 'reception') {
      _add(_skip('10 · users/\$uid WRITE (isActive toggle)',
          'Skipped — role "$role" cannot manage staff'));
    } else if (otherUid == null) {
      _add(_warn('10 · users/\$uid WRITE (isActive toggle)',
          'No other non-owner staff in this shop — cannot test cross-user write.\n'
          '  Add a second staff member (technician/manager/reception), then re-run.\n'
          '  Note: the rule intentionally blocks writing to owner records,\n'
          '  so testing on own uid would always fail even if the rule is correct.'));
    } else {
      try {
        final snap = await db.ref('users/$otherUid/isActive').get().timeout(_timeout);
        final cur  = snap.value as bool? ?? true;
        await db.ref('users/$otherUid/isActive').set(cur).timeout(_timeout);
        _add(_ok('10 · users/\$uid WRITE (isActive toggle)',
            'Write OK (tested on staff uid ${otherUid.substring(0, 8)}…)\n'
            '  User Roles activate / deactivate staff will work.'));
      } catch (e) {
        _add(_fail('10 · users/\$uid WRITE (isActive toggle)',
            '${_fmt(e)}\n'
            '  Tested against: ${otherUid.substring(0, 8)}…\n'
            '  Impact: toggling staff active status in User Roles page will fail.\n'
            '  Rule must allow admin/manager to write isActive on non-owner staff\n'
            '  in the same shop.  Check users/\$uid/.write clause 1.'));
      }
    }

    // ── 11. users/$otherUid WRITE role (User Roles role-change) ─────
    if (shopId.isEmpty || role == 'technician' || role == 'reception') {
      _add(_skip('11 · users/\$uid WRITE (role change)',
          'Skipped — role "$role" cannot change staff roles'));
    } else if (otherUid == null) {
      _add(_warn('11 · users/\$uid WRITE (role change)',
          'No other non-owner staff in this shop — cannot test cross-user write.\n'
          '  Add a second staff member, then re-run diagnostics.'));
    } else {
      try {
        final snap = await db.ref('users/$otherUid/role').get().timeout(_timeout);
        final cur  = snap.value as String? ?? 'technician';
        await db.ref('users/$otherUid/role').set(cur).timeout(_timeout);
        _add(_ok('11 · users/\$uid WRITE (role change)',
            'Write OK (tested on staff uid ${otherUid.substring(0, 8)}…)\n'
            '  User Roles role-change dropdown will work.'));
      } catch (e) {
        _add(_fail('11 · users/\$uid WRITE (role change)',
            '${_fmt(e)}\n'
            '  Tested against: ${otherUid.substring(0, 8)}…\n'
            '  Impact: changing staff role in User Roles page will fail.\n'
            '  Rule must allow admin/manager to write role on non-owner staff\n'
            '  in the same shop.  Check users/\$uid/role/.write child rule.'));
      }
    }

    // ── 12. users/$uid WRITE pin reset ────────────────────────
    if (shopId.isEmpty || role == 'technician' || role == 'reception') {
      _add(_skip('12 · users/\$uid WRITE (PIN reset)',
          role == 'technician' || role == 'reception'
              ? 'Skipped — role "$role" cannot reset PINs'
              : 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('users/$uid/pin').get().timeout(_timeout);
        final cur  = snap.value as String? ?? '';
        await db.ref('users/$uid/pin').set(cur).timeout(_timeout);
        _add(_ok('12 · users/\$uid WRITE (PIN reset)',
            'Write OK — User Roles PIN reset will work'));
      } catch (e) {
        _add(_fail('12 · users/\$uid WRITE (PIN reset)',
            '${_fmt(e)}\n'
            '  Impact: "Reset PIN" button in User Roles page will fail.\n'
            '  Rule should allow admin/manager to write users/\$uid/pin.'));
      }
    }

    // ── 13. users/$uid WRITE — add/edit staff ────────────
    if (shopId.isEmpty) {
      _add(_skip('13 · users/\$uid WRITE (add/edit staff)', 'Skipped — no shopId'));
    } else {
      try {
        final ts = DateTime.now().millisecondsSinceEpoch;
        await db.ref('users/$uid').update({'_diagTest': ts}).timeout(_timeout);
        await db.ref('users/$uid/_diagTest').remove().timeout(_timeout);
        _add(_ok('13 · users/\$uid WRITE (add/edit staff)',
            'Write OK — Add Staff and Edit Staff will work.\n'
            '  All staff data now writes to users/ only (staff/ node removed).'));
      } catch (e) {
        _add(_fail('13 · users/\$uid WRITE (add/edit staff)',
            '${_fmt(e)}\n'
            '  ⚠️  staff/ node has been removed — writes now go to users/.\n'
            '  Common causes:\n'
            '  a) Rule requires shops/$shopId/isActive=true but isActive is missing.\n'
            '  b) Rule requires role=="admin" or "manager" but your role="$role".\n'
            '  c) Rule clause D requires newData.child("shopId").val() to match\n'
            '     the admin/manager\'s own shopId.\n\n'
            '  Verify firebase_rules.json is applied in Firebase Console → Rules.'));
      }
    }

    // ── 14. users/$uid WRITE isActive (staff soft-delete) ──
    if (shopId.isEmpty) {
      _add(_skip('14 · users/\$uid WRITE (isActive)', 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('users/$uid/isActive').get().timeout(_timeout);
        final cur  = snap.value as bool? ?? true;
        await db.ref('users/$uid/isActive').set(cur).timeout(_timeout);
        _add(_ok('14 · users/\$uid WRITE (isActive)',
            'Write OK — "Remove Staff" soft-delete will work.\n'
            '  isActive is now on users/ only (staff/ node removed).'));
      } catch (e) {
        _add(_fail('14 · users/\$uid WRITE (isActive)',
            '${_fmt(e)}\n'
            '  Impact: removing a staff member (soft-delete) will fail.'));
      }
    }

    // ── 15. customers READ ────────────────────────────────────
    if (shopId.isEmpty) {
      _add(_skip('15 · customers READ', 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('customers')
            .orderByChild('shopId').equalTo(shopId).get().timeout(_timeout);
        final count = (snap.exists && snap.value is Map) ? (snap.value as Map).length : 0;
        _add(_ok('15 · customers READ', '$count customer(s) accessible (Customers + Jobs screens)'));
      } catch (e) {
        _add(_fail('15 · customers READ',
            '${_fmt(e)}\n'
            '  Ensure ".indexOn": ["shopId"] on customers/ in rules.'));
      }
    }

    // ── 16. jobs READ ─────────────────────────────────────────
    if (shopId.isEmpty) {
      _add(_skip('16 · jobs READ', 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('jobs')
            .orderByChild('shopId').equalTo(shopId).get().timeout(_timeout);
        final count = (snap.exists && snap.value is Map) ? (snap.value as Map).length : 0;
        _add(_ok('16 · jobs READ', '$count job(s) accessible (Jobs screen)'));
      } catch (e) {
        _add(_fail('16 · jobs READ',
            '${_fmt(e)}\n  Ensure ".indexOn": ["shopId"] on jobs/ in rules.'));
      }
    }

    // ── 17. products READ ─────────────────────────────────────
    if (shopId.isEmpty) {
      _add(_skip('17 · products READ', 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('products')
            .orderByChild('shopId').equalTo(shopId).get().timeout(_timeout);
        final count = (snap.exists && snap.value is Map) ? (snap.value as Map).length : 0;
        _add(_ok('17 · products READ', '$count product(s) accessible (Inventory + POS)'));
      } catch (e) {
        _add(_fail('17 · products READ',
            '${_fmt(e)}\n  Ensure ".indexOn": ["shopId"] on products/ in rules.'));
      }
    }

    // ── 18. transactions READ ─────────────────────────────────
    if (shopId.isEmpty) {
      _add(_skip('18 · transactions READ', 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('transactions')
            .orderByChild('shopId').equalTo(shopId).get().timeout(_timeout);
        final count = (snap.exists && snap.value is Map) ? (snap.value as Map).length : 0;
        _add(_ok('18 · transactions READ', '$count transaction(s) accessible (Finance screen)'));
      } catch (e) {
        _add(_fail('18 · transactions READ',
            '${_fmt(e)}\n  Ensure ".indexOn": ["shopId"] on transactions/ in rules.'));
      }
    }

    // ── 19. stock_history READ ────────────────────────────────
    if (shopId.isEmpty) {
      _add(_skip('19 · stock_history READ', 'Skipped — no shopId'));
    } else {
      try {
        final snap = await db.ref('stock_history')
            .orderByChild('shopId').equalTo(shopId).get().timeout(_timeout);
        final count = (snap.exists && snap.value is Map) ? (snap.value as Map).length : 0;
        _add(_ok('19 · stock_history READ', '$count record(s) (used by Demo Data clear)'));
      } catch (e) {
        _add(_warn('19 · stock_history READ',
            '${_fmt(e)}\n'
            '  Non-critical — only affects Demo Data Tools "Clear All" button.\n'
            '  Ensure ".indexOn": ["shopId"] on stock_history/ if needed.'));
      }
    }

    // ── 20. diagnostics/$uid WRITE — self-log ────────────────
    try {
      await db.ref('diagnostics/$uid').update({
        'lastRunAt':    DateTime.now().toUtc().toIso8601String(),
        'shopId':       shopId,
        'role':         role,
        'uid':          uid,
        'totalChecks':  _results.length + 1,
      }).timeout(_timeout);
      _add(_ok('20 · diagnostics/\$uid WRITE', 'Audit log write OK'));
    } catch (e) {
      _add(_fail('20 · diagnostics/\$uid WRITE',
          '${_fmt(e)}\n'
          '  Rule should allow auth.uid==\$uid.\n'
          '  Check your security rules for the diagnostics/ node.'));
    }

    _done();
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final failCount = _results.where((r) => r.detail.startsWith('❌')).length;
    final warnCount = _results.where((r) => r.detail.startsWith('⚠️')).length;
    final okCount   = _results.where((r) => r.detail.startsWith('✅')).length;

    return _Page(
      title: 'Firebase Diagnostics',
      subtitle: 'v2 — all 21 nodes & operations tested',
      children: [
        if (_hasRun && !_running)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: failCount > 0
                  ? C.red.withValues(alpha: 0.1)
                  : warnCount > 0
                      ? C.yellow.withValues(alpha: 0.1)
                      : C.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: failCount > 0
                      ? C.red.withValues(alpha: 0.4)
                      : warnCount > 0
                          ? C.yellow.withValues(alpha: 0.4)
                          : C.green.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Text(failCount > 0 ? '❌' : warnCount > 0 ? '⚠️' : '✅',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(
                failCount > 0
                    ? '$failCount FAILED · $warnCount warnings · $okCount passed'
                    : warnCount > 0
                        ? 'All critical checks passed · $warnCount warning(s)'
                        : 'All ${_results.length} checks passed ✨',
                style: GoogleFonts.syne(
                    fontWeight: FontWeight.w700, fontSize: 13,
                    color: failCount > 0 ? C.red : warnCount > 0 ? C.yellow : C.green),
              )),
            ]),
          ),

        if (!_hasRun)
          _infoBanner(
            'Tap "Run Diagnostics" to test every Firebase node and operation.\n\n'
            'Coverage: SDK · RTDB · Auth · users R/W · shops R/W · '
            'staff R/W · staff list · customers · jobs · products · '
            'transactions · stock_history · diagnostics — 21 checks total.\n\n'
            'Each failure shows the exact security rule fix needed.',
          ),

        ..._results.map(_buildRow),

        if (_running)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: C.primary)),
              const SizedBox(width: 12),
              Text('Running checks… (${_results.length} done)',
                  style: GoogleFonts.syne(fontSize: 13, color: C.textMuted)),
            ]),
          ),

        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity, height: 50,
          child: ElevatedButton(
            onPressed: _running ? null : _run,
            style: ElevatedButton.styleFrom(
              backgroundColor: C.primary, foregroundColor: C.bg,
              disabledBackgroundColor: C.primary.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _running
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: C.bg))
                : Text(_hasRun ? '🔄  Re-run Diagnostics' : '🧪  Run Diagnostics',
                    style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(_DiagResult r) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: r.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: r.color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.label,
            style: GoogleFonts.syne(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: C.textMuted, letterSpacing: 0.9)),
        const SizedBox(height: 5),
        Text(r.detail,
            style: GoogleFonts.syne(fontSize: 12, color: r.color, height: 1.5)),
      ]),
    ),
  );
}
// ═════════════════════════════════════════════════════════════
// 8. USER ROLES & ACCESS
// ═════════════════════════════════════════════════════════════
// ═════════════════════════════════════════════════════════════
// 8. USER ROLES & ACCESS
// ═════════════════════════════════════════════════════════════

/// Full-screen page with its own Scaffold (not _Page) because it contains
/// a TabBarView which cannot live inside a ListView.
class UserRolesPage extends ConsumerStatefulWidget {
  const UserRolesPage({super.key});
  @override
  ConsumerState<UserRolesPage> createState() => _UserRolesState();
}

class _UserRolesState extends ConsumerState<UserRolesPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabs;
  bool   _loadingStaff = false;
  String _loadError    = '';

  // Role changes pending save  uid → new role
  final Map<String, String> _pendingRoles = {};
  // PIN field per member
  final Map<String, TextEditingController> _pinCtrls = {};

  static const _roles = ['admin', 'manager', 'reception', 'technician'];
  // (emoji, label, color)
  static const Map<String, (String, String, Color)> _roleMeta = {
    'admin':      ('👑', 'Admin',      Color(0xFF9B59B6)),
    'manager':    ('🎯', 'Manager',    Color(0xFF00BCD4)),
    'reception':  ('💁', 'Reception',  Color(0xFF4CAF50)),
    'technician': ('🔧', 'Tech',       Color(0xFFFF9800)),
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(staffProvider).isEmpty) _loadStaff();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _pinCtrls.values) { c.dispose(); }
    super.dispose();
  }

  // ─── Firebase ops ────────────────────────────────────────────

  Future<void> _loadStaff() async {
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final shopId  = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');
    if (shopId.isEmpty) {
      setState(() { _loadError = 'Not logged in — please enter via lock screen.'; });
      return;
    }
    setState(() { _loadingStaff = true; _loadError = ''; });
    try {
      await ref.read(staffProvider.notifier).loadFromFirebase(shopId);
      for (final s in ref.read(staffProvider)) {
        _pinCtrls.putIfAbsent(s.uid, () => TextEditingController());
      }
      if (mounted) { setState(() => _loadingStaff = false); }
    } catch (e) {
      if (mounted) {
      setState(() {
        _loadError = e.toString();
        _loadingStaff = false;
      });
    }
    }
  }

  Future<void> _saveRoles() async {
    if (_pendingRoles.isEmpty) return;
    final notifier = ref.read(staffProvider.notifier);
    try {
      for (final e in _pendingRoles.entries) {
        await notifier.changeRole(e.key, e.value);
      }
      setState(() => _pendingRoles.clear());
      if (mounted) _snack('✅ Roles updated', C.green);
    } catch (e) {
      if (mounted) _snack('❌ ${e.toString().length > 70 ? e.toString().substring(0,70) : e}', C.red);
    }
  }

  Future<void> _resetPin(String uid) async {
    final pin = _pinCtrls[uid]?.text ?? '';
    if (pin.length != 4) { _snack('PIN must be exactly 4 digits', C.red); return; }
    try {
      await ref.read(staffProvider.notifier).resetPin(uid, pin);
      _pinCtrls[uid]?.clear();
      if (mounted) _snack('✅ PIN reset', C.green);
    } catch (e) {
      if (mounted) _snack('❌ PIN reset failed: $e', C.red);
    }
  }

  void _snack(String msg, Color bg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 13)),
             backgroundColor: bg, behavior: SnackBarBehavior.floating,
             duration: const Duration(seconds: 3)));

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffProvider);
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bgElevated,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: C.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('User Roles & Access',
              style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 16, color: C.white)),
          Text('Assign roles · reset PINs',
              style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
        ]),
        actions: [
          if (_pendingRoles.isNotEmpty)
            TextButton.icon(
              onPressed: _saveRoles,
              icon: const Icon(Icons.save_rounded, size: 16, color: C.primary),
              label: Text('Save ${_pendingRoles.length}',
                  style: GoogleFonts.syne(fontWeight: FontWeight.w800, color: C.primary, fontSize: 13)),
            ),
          IconButton(
            icon: _loadingStaff
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: C.primary))
                : const Icon(Icons.refresh_rounded, color: C.primary, size: 22),
            onPressed: _loadingStaff ? null : _loadStaff,
            tooltip: 'Reload from Firebase',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 1, color: C.border),
            TabBar(
              controller: _tabs,
              labelStyle: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.syne(fontWeight: FontWeight.w600, fontSize: 13),
              labelColor: C.primary,
              unselectedLabelColor: C.textMuted,
              indicatorColor: C.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: '👥  Staff & Roles'),
                Tab(text: '🔐  Permissions'),
              ],
            ),
          ]),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildStaffTab(staff),
          _buildPermissionsTab(),
        ],
      ),
    );
  }

  // ─── TAB 1: Staff list ──────────────────────────────────────

  Widget _buildStaffTab(List<StaffMember> staff) {
    if (_loadingStaff) {
      return const Center(child: CircularProgressIndicator(color: C.primary));
    }

    if (_loadError.isNotEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('❌', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Failed to load staff', style: GoogleFonts.syne(
              fontSize: 15, color: C.red, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_loadError, style: GoogleFonts.syne(fontSize: 11, color: C.textMuted),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadStaff,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('Retry', style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: C.primary, foregroundColor: C.bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
        ]),
      ));
    }

    if (staff.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('👥', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text('No staff found', style: GoogleFonts.syne(
            fontSize: 17, fontWeight: FontWeight.w800, color: C.white)),
        const SizedBox(height: 6),
        Text('Tap ↻ to load staff from Firebase.',
            style: GoogleFonts.syne(fontSize: 13, color: C.textMuted)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _loadStaff,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('Load Staff',
              style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14)),
          style: ElevatedButton.styleFrom(
              backgroundColor: C.primary, foregroundColor: C.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
        ),
      ]));
    }

    final active   = staff.where((s) => s.isActive).toList();
    final inactive = staff.where((s) => !s.isActive).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: C.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.primary.withValues(alpha: 0.25)),
          ),
          child: Text(
            'Tap a role pill to change it, then tap Save. '
            'Owner role is permanent and cannot be changed. '
            'PIN reset takes effect immediately.',
            style: GoogleFonts.syne(fontSize: 12, color: C.textMuted, height: 1.4),
          ),
        ),
        // Active staff
        ...active.map((s) => _staffCard(s)),
        // Inactive staff section
        if (inactive.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
            child: Text('INACTIVE ACCOUNTS',
                style: GoogleFonts.syne(fontSize: 10, fontWeight: FontWeight.w800,
                    color: C.textMuted, letterSpacing: 1.2)),
          ),
          ...inactive.map((s) => Opacity(opacity: 0.5, child: _staffCard(s))),
        ],
        const SizedBox(height: 8),
        if (_pendingRoles.isNotEmpty)
          SizedBox(width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: _saveRoles,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text('Save ${_pendingRoles.length} role change(s)',
                  style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: C.primary, foregroundColor: C.bg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
      ],
    );
  }

  Widget _staffCard(StaffMember s) {
    final currentRole = _pendingRoles[s.uid] ?? s.role;
    final meta = _roleMeta[currentRole] ?? ('👤', currentRole, C.textMuted);
    final roleColor = meta.$3;
    _pinCtrls.putIfAbsent(s.uid, () => TextEditingController());
    final hasPending = _pendingRoles.containsKey(s.uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: C.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: hasPending ? C.primary.withValues(alpha: 0.6) : C.border,
            width: hasPending ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(meta.$1,
                  style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Flexible(child: Text(s.displayName,
                    style: GoogleFonts.syne(fontWeight: FontWeight.w800,
                        fontSize: 14, color: C.white),
                    overflow: TextOverflow.ellipsis)),
                if (s.isOwner) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: C.yellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5)),
                    child: Text('OWNER', style: GoogleFonts.syne(
                        fontSize: 9, fontWeight: FontWeight.w800, color: C.yellow)),
                  ),
                ],
                if (hasPending) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: C.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text('UNSAVED', style: GoogleFonts.syne(
                        fontSize: 9, fontWeight: FontWeight.w800, color: C.primary)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(s.email.isNotEmpty ? s.email : s.phone,
                  style: GoogleFonts.syne(fontSize: 11, color: C.textMuted),
                  overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),

        Container(height: 1, color: C.border),

        // ── Role pills ────────────────────────────────────────
        if (!s.isOwner) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Text('ROLE', style: GoogleFonts.syne(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: C.textMuted, letterSpacing: 1.0)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Wrap(spacing: 8, runSpacing: 6, children: _roles.map((r) {
              final rm  = _roleMeta[r]!;
              final sel = currentRole == r;
              return GestureDetector(
                onTap: () => setState(() {
                  if (r == s.role) {
                    _pendingRoles.remove(s.uid);
                  } else {
                    _pendingRoles[s.uid] = r;
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? rm.$3.withValues(alpha: 0.16) : C.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: sel ? rm.$3 : C.border, width: sel ? 1.5 : 1)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(rm.$1, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 5),
                    Text(rm.$2, style: GoogleFonts.syne(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: sel ? rm.$3 : C.textMuted)),
                  ]),
                ),
              );
            }).toList()),
          ),

          Container(height: 1, color: C.border),
        ],

        // ── PIN reset ─────────────────────────────────────────
        if (!s.isOwner)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RESET PIN', style: GoogleFonts.syne(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: C.textMuted, letterSpacing: 1.0)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _pinCtrls[s.uid],
                    obscureText: true,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: GoogleFonts.syne(
                        fontSize: 20, letterSpacing: 10, color: C.white),
                    decoration: InputDecoration(
                      hintText: '  ●  ●  ●  ●',
                      hintStyle: GoogleFonts.syne(
                          fontSize: 14, color: C.textDim, letterSpacing: 4),
                      counterText: '',
                      filled: true, fillColor: C.bgElevated,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: C.border)),
                      enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: C.border)),
                      focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: C.primary, width: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(height: 48,
                  child: ElevatedButton(
                    onPressed: () => _resetPin(s.uid),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.primary, foregroundColor: C.bg,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: Text('Reset',
                        style: GoogleFonts.syne(fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                ),
              ]),
              if (s.pin.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text('Current PIN: ${'●' * s.pin.length}  (saved)',
                      style: GoogleFonts.syne(fontSize: 10, color: C.textMuted)),
                ),
            ]),
          ),
      ]),
    );
  }

  // ─── TAB 2: Permissions matrix ──────────────────────────────

  Widget _buildPermissionsTab() {
    const rows = [
      // (feature, admin, manager, reception, tech)
      ('SHOP SETTINGS', null, null, null, null),
      ('Edit shop profile',    true,  false, false, false),
      ('Tax & invoice config', true,  false, false, false),
      ('Workflow stages',      true,  true,  false, false),
      ('User roles & PINs',   true,  false, false, false),
      ('JOBS', null, null, null, null),
      ('Create job',           true,  true,  true,  false),
      ('Edit job details',     true,  true,  false, false),
      ('Change status',        true,  true,  true,  true),
      ('View all jobs',        true,  true,  true,  true),
      ('Delete job',           true,  false, false, false),
      ('CUSTOMERS', null, null, null, null),
      ('Add / edit customer',  true,  true,  true,  false),
      ('View customers',       true,  true,  true,  true),
      ('INVENTORY', null, null, null, null),
      ('Add / edit products',  true,  true,  false, false),
      ('Adjust stock',         true,  true,  false, false),
      ('View inventory',       true,  true,  true,  true),
      ('FINANCIALS', null, null, null, null),
      ('Create invoices',      true,  true,  true,  false),
      ('Record payments',      true,  true,  true,  false),
      ('View reports',         true,  true,  false, false),
      ('Export data',          true,  false, false, false),
    ];

    const colColors = [
      Color(0xFF9B59B6),
      Color(0xFF00BCD4),
      Color(0xFF4CAF50),
      Color(0xFFFF9800),
    ];
    const colIcons  = ['👑', '🎯', '💁', '🔧'];
    const colLabels = ['Admin', 'Mgr', 'Rec', 'Tech'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
      children: [
        // Column headers
        Row(children: [
          const Expanded(flex: 4, child: SizedBox()),
          for (int i = 0; i < 4; i++)
            Expanded(child: Column(children: [
              Text(colIcons[i], style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 2),
              Text(colLabels[i], style: GoogleFonts.syne(
                  fontSize: 9, fontWeight: FontWeight.w800, color: colColors[i])),
            ])),
        ]),
        const SizedBox(height: 10),

        for (final row in rows)
          row.$2 == null
          // Section header
          ? Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
              child: Text(row.$1, style: GoogleFonts.syne(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: C.textMuted, letterSpacing: 1.1)),
            )
          // Data row
          : Container(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: C.border.withValues(alpha: 0.4)),
                ),
              ),
              child: Row(children: [
                Expanded(flex: 4, child: Text(row.$1,
                    style: GoogleFonts.syne(fontSize: 12, color: C.text))),
                ...List.generate(4, (i) {
                  final allowed = [row.$2, row.$3, row.$4, row.$5][i] == true;
                  return Expanded(child: Center(child: allowed
                      ? Icon(Icons.check_circle_rounded, size: 17,
                          color: colColors[i])
                      : Text('—', style: GoogleFonts.syne(
                          fontSize: 16, color: C.textDim,
                          fontWeight: FontWeight.w900))));
                }),
              ]),
            ),

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: C.bgElevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('Permissions are enforced by Firebase Security Rules, '
              'not just in the app UI. Changing a role takes effect immediately.',
              style: GoogleFonts.syne(fontSize: 11, color: C.textMuted, height: 1.5)),
        ),
      ],
    );
  }
}


// ═════════════════════════════════════════════════════════════
// 9. WHATSAPP BUSINESS
// ═════════════════════════════════════════════════════════════
class WhatsappPage extends ConsumerStatefulWidget {
  const WhatsappPage({super.key});
  @override
  ConsumerState<WhatsappPage> createState() => _WhatsappPageState();
}

class _WhatsappPageState extends ConsumerState<WhatsappPage> {
  // ── controllers ───────────────────────────────────────────────────────────
  final _apiKey  = TextEditingController();
  final _phoneNumber = TextEditingController();

  // ── state ─────────────────────────────────────────────────────────────────
  WhatsAppConfig _cfg    = const WhatsAppConfig();
  bool _loading          = true;
  bool _testing          = false;
  bool _saving           = false;
  bool _testOk           = false; // shows green tick after successful test

  // local editable template bodies (synced from _cfg on load)
  late String _tplPickup;
  late String _tplUpdate;
  late String _tplReminder;

  @override
  void initState() {
    super.initState();
    _tplPickup   = const WhatsAppConfig().tplPickup;
    _tplUpdate   = const WhatsAppConfig().tplUpdate;
    _tplReminder = const WhatsAppConfig().tplReminder;
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _phoneNumber.dispose();
    super.dispose();
  }

  String get _shopId =>
      ref.read(activeSessionProvider)?.shopId
      ?? ref.read(settingsProvider).shopId;

  Future<void> _load() async {
    final cfg = await NotificationService.loadWhatsApp(_shopId);
    if (!mounted) return;
    setState(() {
      _cfg        = cfg;
      _tplPickup  = cfg.tplPickup;
      _tplUpdate  = cfg.tplUpdate;
      _tplReminder= cfg.tplReminder;
      _apiKey.text       = cfg.apiKey;
      _phoneNumber.text  = cfg.phoneNumber;
      _loading    = false;
    });
  }

  Future<void> _test() async {
    setState(() { _testing = true; _testOk = false; });
    final cfg  = _currentConfig();
    final shop = ref.read(settingsProvider);
    final result = await NotificationService.testWhatsApp(cfg, shop.phone);
    if (!mounted) return;
    setState(() { _testing = false; _testOk = result.ok; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.ok ? '✅ ${result.message}' : '❌ ${result.message}',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
      backgroundColor: result.ok ? C.green : C.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await NotificationService.saveWhatsApp(_shopId, _currentConfig());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ WhatsApp settings saved',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.green, behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Save failed: $e',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  WhatsAppConfig _currentConfig() => WhatsAppConfig(
    apiKey:       _apiKey.text.trim(),
    phoneNumber:  _phoneNumber.text.trim(),
    autoPickup:   _cfg.autoPickup,
    autoUpdate:   _cfg.autoUpdate,
    autoReminder: _cfg.autoReminder,
    tplPickup:    _tplPickup,
    tplUpdate:    _tplUpdate,
    tplReminder:  _tplReminder,
  );

  void _setCfg(WhatsAppConfig updated) => setState(() => _cfg = updated);

  @override
  Widget build(BuildContext context) => _Page(
    title: 'WhatsApp Business', subtitle: 'Send messages via Interakt (free tier)',
    children: [
      _infoBanner(
        '📲 Setup: Sign up free at app.interakt.ai → connect your WhatsApp Business number '
        '→ Settings → Developer → copy your API Key and paste below. '
        'Free tier: 1,000 conversations/month.',
        color: C.green,
      ),
      if (_loading)
        const Center(child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: C.primary),
        ))
      else ...[
        // ── Credentials ─────────────────────────────────────────────────
        const SLabel('API CREDENTIALS'),
        AppField(
          label:      'Interakt API Key',
          controller: _apiKey,
          hint:       'Paste your API key from app.interakt.ai → Settings → Developer',
          obscureText: true,
          onChanged:  (_) => setState(() => _testOk = false),
        ),
        AppField(
          label:      'WhatsApp Business Phone Number',
          controller: _phoneNumber,
          hint:       '10-digit number e.g. 9876543210',
          keyboardType: TextInputType.phone,
          onChanged:  (_) => setState(() => _testOk = false),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, height: 48,
          child: ElevatedButton.icon(
            onPressed: (_testing || _apiKey.text.isEmpty || _phoneNumber.text.isEmpty)
                ? null : _test,
            icon: _testing
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: C.bg))
                : Icon(_testOk ? Icons.check_circle : Icons.wifi_tethering,
                    size: 18, color: C.bg),
            label: Text(
              _testing ? 'Testing…' : _testOk ? 'Connected ✓' : 'Test Connection',
              style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _testOk ? C.green : C.primary,
              foregroundColor: C.bg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),

        // ── Triggers ────────────────────────────────────────────────────
        const SLabel('AUTO-SEND TRIGGERS'),
        SettingsGroup(title: '', tiles: [
          SettingsTile(
            icon:     '🎉',
            title:    'Pickup Ready Notification',
            subtitle: 'Send when job → Ready for Pickup',
            trailing: Switch(
              value:     _cfg.autoPickup,
              onChanged: (v) => _setCfg(_cfg.copyWith(autoPickup: v))),
          ),
          SettingsTile(
            icon:     '🔄',
            title:    'Status Update Messages',
            subtitle: 'Notify on every status change',
            trailing: Switch(
              value:     _cfg.autoUpdate,
              onChanged: (v) => _setCfg(_cfg.copyWith(autoUpdate: v))),
          ),
          SettingsTile(
            icon:     '⏰',
            title:    '3-Day Pickup Reminder',
            subtitle: 'Auto-remind if not collected in 3 days',
            trailing: Switch(
              value:     _cfg.autoReminder,
              onChanged: (v) => _setCfg(_cfg.copyWith(autoReminder: v))),
          ),
        ]),

        // ── Templates ───────────────────────────────────────────────────
        const SLabel('MESSAGE TEMPLATES'),
        _tplCard('Pickup Ready',    _tplPickup,
            (v) => setState(() => _tplPickup   = v)),
        _tplCard('Job Update',      _tplUpdate,
            (v) => setState(() => _tplUpdate   = v)),
        _tplCard('Pickup Reminder', _tplReminder,
            (v) => setState(() => _tplReminder = v)),

        _SaveBtn(
          onSave: _saving ? () {} : _save,
          label: _saving ? 'Saving…' : '💾  Save WhatsApp Settings',
        ),
      ],
    ],
  );

  Widget _tplCard(String name, String body, ValueChanged<String> onSaved) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SCard(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(name, style: GoogleFonts.syne(
                fontWeight: FontWeight.w700, fontSize: 13, color: C.white)),
            TextButton(
              onPressed: () => _editTemplate(context, name, body, onSaved),
              child: Text('Edit', style: GoogleFonts.syne(
                  color: C.primary, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: C.bgElevated, borderRadius: BorderRadius.circular(8)),
            child: Text(body, style: GoogleFonts.syne(
                fontSize: 11, color: C.textMuted, height: 1.5)),
          ),
        ])),
      );

  void _editTemplate(BuildContext ctx, String name, String body,
      ValueChanged<String> onSaved) {
    final ctrl = TextEditingController(text: body);
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: C.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit: $name', style: GoogleFonts.syne(
            fontWeight: FontWeight.w800, color: C.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _infoBanner(
            'Variables: {name} {device} {amount} {job_num} '
            '{status} {days} {shop_address} {shop_phone}'),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrl, maxLines: 6,
            style: GoogleFonts.syne(fontSize: 13, color: C.text),
            decoration: const InputDecoration(),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.syne(color: C.textMuted))),
          ElevatedButton(
            onPressed: () {
              onSaved(ctrl.text);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: C.primary, foregroundColor: C.bg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Save Template',
                style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// 10. SMS GATEWAY
// ═════════════════════════════════════════════════════════════
class SmsPage extends ConsumerStatefulWidget {
  const SmsPage({super.key});
  @override
  ConsumerState<SmsPage> createState() => _SmsPageState();
}

class _SmsPageState extends ConsumerState<SmsPage> {
  final _apiKey  = TextEditingController();
  final _sender  = TextEditingController(text: 'TECHFX');

  SmsConfig _cfg   = const SmsConfig();
  bool _loading    = true;
  bool _testing    = false;
  bool _saving     = false;
  bool _testOk     = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _sender.dispose();
    super.dispose();
  }

  String get _shopId =>
      ref.read(activeSessionProvider)?.shopId
      ?? ref.read(settingsProvider).shopId;

  Future<void> _load() async {
    final cfg = await NotificationService.loadSms(_shopId);
    if (!mounted) return;
    setState(() {
      _cfg           = cfg;
      _apiKey.text   = cfg.apiKey;
      _sender.text   = cfg.senderId;
      _loading       = false;
    });
  }

  SmsConfig _currentConfig() => SmsConfig(
    provider: _cfg.provider,
    apiKey:   _apiKey.text.trim(),
    senderId: _sender.text.trim(),
    onPickup: _cfg.onPickup,
    onUpdate: _cfg.onUpdate,
  );

  Future<void> _test() async {
    setState(() { _testing = true; _testOk = false; });
    final shop   = ref.read(settingsProvider);
    final result = await NotificationService.testSms(
        _currentConfig(), shop.phone);
    if (!mounted) return;
    setState(() { _testing = false; _testOk = result.ok; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.ok ? '✅ ${result.message}' : '❌ ${result.message}',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
      backgroundColor: result.ok ? C.green : C.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await NotificationService.saveSms(_shopId, _currentConfig());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ SMS settings saved',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.green, behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Save failed: $e',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'SMS Gateway', subtitle: 'Text message notifications to customers',
    children: [
      if (_loading)
        const Center(child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: C.primary),
        ))
      else ...[
        // ── Provider picker ──────────────────────────────────────────────
        const SLabel('PROVIDER'),
        ...['MSG91', 'Twilio', 'TextLocal', 'Fast2SMS'].map((p) {
          final sel = _cfg.provider == p;
          return GestureDetector(
            onTap: () => setState(() {
              _cfg    = _cfg.copyWith(provider: p);
              _testOk = false;
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: sel ? C.primary.withValues(alpha: 0.08) : C.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: sel ? C.primary : C.border, width: sel ? 2 : 1),
              ),
              child: Row(children: [
                Text(_providerIcon(p),
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p, style: GoogleFonts.syne(
                      fontWeight: FontWeight.w700, fontSize: 13,
                      color: sel ? C.primary : C.white)),
                  Text(_providerHint(p), style: GoogleFonts.syne(
                      fontSize: 10, color: C.textMuted)),
                ])),
                if (sel) const Icon(Icons.check_circle,
                    color: C.primary, size: 20),
              ]),
            ),
          );
        }),

        // ── Credentials ──────────────────────────────────────────────────
        const SLabel('CREDENTIALS'),
        AppField(
          label:     'API Key',
          controller: _apiKey,
          hint:      _providerKeyHint(_cfg.provider),
          obscureText: true,
          onChanged: (_) => setState(() => _testOk = false),
        ),
        AppField(
          label:     'Sender ID',
          controller: _sender,
          hint:      _cfg.provider == 'Twilio'
              ? 'Your Twilio number e.g. 919876543210'
              : '6-char alphanumeric e.g. TECHFX',
        ),
        const SizedBox(height: 8),

        // ── Test button ──────────────────────────────────────────────────
        SizedBox(width: double.infinity, height: 48,
          child: ElevatedButton.icon(
            onPressed: (_testing || _apiKey.text.isEmpty) ? null : _test,
            icon: _testing
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: C.bg))
                : Icon(_testOk ? Icons.check_circle : Icons.sms,
                    size: 18, color: C.bg),
            label: Text(
              _testing ? 'Sending test SMS…'
                  : _testOk ? 'SMS Sent ✓' : 'Send Test SMS',
              style: GoogleFonts.syne(
                  fontWeight: FontWeight.w800, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _testOk ? C.green : C.primary,
              foregroundColor: C.bg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),

        // ── Send triggers ────────────────────────────────────────────────
        const SLabel('SEND SETTINGS'),
        SettingsGroup(title: '', tiles: [
          SettingsTile(
            icon:     '🎉',
            title:    'Pickup Ready SMS',
            subtitle: 'Auto-send when Ready for Pickup',
            trailing: Switch(
              value:     _cfg.onPickup,
              onChanged: (v) => setState(
                  () => _cfg = _cfg.copyWith(onPickup: v))),
          ),
          SettingsTile(
            icon:     '🔄',
            title:    'Status Update SMS',
            subtitle: 'Notify on status changes',
            trailing: Switch(
              value:     _cfg.onUpdate,
              onChanged: (v) => setState(
                  () => _cfg = _cfg.copyWith(onUpdate: v))),
          ),
        ]),

        if (_cfg.provider == 'MSG91')
          _infoBanner(
            'MSG91 requires DLT-registered templates for Indian '
            'numbers. Transactional route 4 is used. '
            'Register templates at msg91.com → DLT.'),
        if (_cfg.provider == 'Twilio')
          _infoBanner(
            'Twilio API Key format: "AccountSID:AuthToken". '
            'Sender ID must be your Twilio phone number with country code.'),

        _SaveBtn(
          onSave: _saving ? () {} : _save,
          label: _saving ? 'Saving…' : '💾  Save SMS Settings',
        ),
      ],
    ],
  );

  String _providerIcon(String p) =>
      {'MSG91': '🇮🇳', 'Twilio': '🌐', 'TextLocal': '🇬🇧', 'Fast2SMS': '⚡'}[p]
          ?? '📱';

  String _providerHint(String p) => {
    'MSG91':     'Best for India — transactional route 4',
    'Twilio':    'Global — API Key format: AccountSID:AuthToken',
    'TextLocal': 'UK & India — standard HTTP API',
    'Fast2SMS':  'India — bulk SMS with DLT support',
  }[p] ?? '';

  String _providerKeyHint(String p) => p == 'Twilio'
      ? 'AccountSID:AuthToken (colon-separated)'
      : 'Paste your $p API key here';
}

// ═════════════════════════════════════════════════════════════
// 11. PUSH NOTIFICATIONS
// ═════════════════════════════════════════════════════════════
class PushNotifPage extends ConsumerStatefulWidget {
  const PushNotifPage({super.key});
  @override
  ConsumerState<PushNotifPage> createState() => _PushNotifState();
}

class _PushNotifState extends ConsumerState<PushNotifPage> {
  // Keys match Firebase path: shops/{shopId}/pushSettings/{key}
  final _notifs = <String, bool>{
    'jobOverdue':       true,
    'lowStock':         true,
    'newJob':           false,
    'statusChanged':    true,
    'dailySummary':     false,
    'pickupReminder':   true,
    'paymentReceived':  true,
    'warrantyExpiring': false,
  };

  // Human-readable labels for each key
  static const _labels = <String, String>{
    'jobOverdue':       'Job Overdue Alert',
    'lowStock':         'Low Stock Warning',
    'newJob':           'New Job Created',
    'statusChanged':    'Job Status Changed',
    'dailySummary':     'Daily Summary (8am)',
    'pickupReminder':   'Customer Pickup Reminder',
    'paymentReceived':  'Payment Received',
    'warrantyExpiring': 'Warranty Expiring Soon',
  };

  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shopId = ref.read(activeSessionProvider)?.shopId
        ?? ref.read(settingsProvider).shopId;
    if (shopId.isEmpty) { setState(() => _loading = false); return; }
    try {
      final snap = await FirebaseDatabase.instance
          .ref('shops/$shopId/pushSettings').get();
      if (snap.exists && snap.value is Map) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        setState(() {
          for (final k in _notifs.keys) {
            if (data.containsKey(k)) _notifs[k] = data[k] as bool? ?? _notifs[k]!;
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final shopId = ref.read(activeSessionProvider)?.shopId
        ?? ref.read(settingsProvider).shopId;
    if (shopId.isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseDatabase.instance
          .ref('shops/$shopId/pushSettings')
          .update(Map.from(_notifs));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Notification preferences saved',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Save failed: $e',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Push Notifications', subtitle: 'Alerts sent to this device',
    children: [
      _infoBanner('Preferences are saved per shop and apply to all devices.'),
      if (_loading)
        const Center(child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: C.primary),
        ))
      else ...[
        SettingsGroup(
          title: 'ALERT TYPES',
          tiles: _notifs.entries.map((e) => SettingsTile(
            icon: _notifIcon(e.key),
            title: _labels[e.key] ?? e.key,
            subtitle: e.value ? 'Enabled' : 'Disabled',
            trailing: Switch(
              value: e.value,
              onChanged: (v) => setState(() => _notifs[e.key] = v),
            ),
          )).toList(),
        ),
        _SaveBtn(
          onSave: _saving ? () {} : _save,
          label: _saving ? 'Saving…' : 'Save Preferences',
        ),
      ],
    ],
  );

  String _notifIcon(String k) {
    const m = {
      'jobOverdue':       '⏰',
      'lowStock':         '📦',
      'newJob':           '🔧',
      'statusChanged':    '🔄',
      'dailySummary':     '📊',
      'pickupReminder':   '🎉',
      'paymentReceived':  '💰',
      'warrantyExpiring': '🛡️',
    };
    return m[k] ?? '🔔';
  }
}

// ═════════════════════════════════════════════════════════════
// 12. EMAIL
// ═════════════════════════════════════════════════════════════
class EmailPage extends StatelessWidget {
  const EmailPage({super.key});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'Email Settings', subtitle: 'SMTP configuration for email sending',
    children: [
      _infoBanner('For Gmail: use App Passwords (not your main password). '
          'Enable 2FA first, then generate an App Password.'),
      const SLabel('SMTP CONFIGURATION'),
      const AppField(label: 'SMTP Host', hint: 'smtp.gmail.com'),
      const AppField(label: 'SMTP Port', hint: '587  (TLS)  or  465  (SSL)',
          keyboardType: TextInputType.number),
      const AppField(label: 'From Email Address', hint: 'noreply@yourshop.com',
          keyboardType: TextInputType.emailAddress),
      const AppField(label: 'App Password', hint: '16-character app password'),
      const AppField(label: 'From Display Name', hint: 'TechFix Pro Shop'),
      const SLabel('EMAIL TRIGGERS'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '🧾', title: 'Invoice on Completion',
            subtitle: 'Email invoice when job is completed',
            trailing: Switch(value: true, onChanged: (_) {})),
        SettingsTile(icon: '🎉', title: 'Pickup Ready Email',
            subtitle: 'Notify when device is ready',
            trailing: Switch(value: true, onChanged: (_) {})),
      ]),
      _SaveBtn(onSave: () {}),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 13. PAYMENT GATEWAY
// ═════════════════════════════════════════════════════════════
class PaymentGatewayPage extends StatefulWidget {
  const PaymentGatewayPage({super.key});
  @override
  State<PaymentGatewayPage> createState() => _PaymentGatewayState();
}

class _PaymentGatewayState extends State<PaymentGatewayPage> {
  String _selected = '';
  final _key = TextEditingController();
  final _secret = TextEditingController();
  bool _testMode = true;

  final _gateways = [
    ('razorpay', 'Razorpay', '🇮🇳', 'Most popular in India — UPI, cards, wallets'),
    ('stripe',   'Stripe',   '🌐', 'International cards & digital wallets'),
    ('paytm',    'Paytm',    '📱', 'Paytm QR, wallet & UPI payments'),
    ('instamojo','Instamojo','⚡', 'Simple Indian payment collection'),
  ];

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Payment Gateway', subtitle: 'Collect online payments from customers',
    children: [
      const SLabel('SELECT GATEWAY'),
      ..._gateways.map((g) {
        final sel = _selected == g.$1;
        return GestureDetector(
          onTap: () => setState(() => _selected = g.$1),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sel ? C.primary.withValues(alpha: 0.08) : C.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Text(g.$3, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(g.$2, style: GoogleFonts.syne(fontWeight: FontWeight.w700,
                    fontSize: 14, color: sel ? C.primary : C.white)),
                Text(g.$4, style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
              ])),
              if (sel) const Icon(Icons.check_circle, color: C.primary),
            ]),
          ),
        );
      }),
      if (_selected.isNotEmpty) ...[
        const SLabel('API CREDENTIALS'),
        AppField(label: 'API Key / Key ID', controller: _key, hint: 'rzp_live_xxxx or pk_live_xxxx'),
        AppField(label: 'API Secret', controller: _secret, hint: 'Secret key from dashboard'),
          SettingsGroup(title: '', tiles: [
          SettingsTile(icon: '🧪', title: 'Test Mode',
              subtitle: _testMode ? 'Using sandbox — no real money' : 'LIVE mode — real payments',
              iconBg: _testMode ? C.yellow.withValues(alpha: 0.1) : C.red.withValues(alpha: 0.1),
              trailing: Switch(value: _testMode,
                  onChanged: (v) => setState(() => _testMode = v))),
        ]),
        if (!_testMode) _infoBanner(
            '⚠️ LIVE mode is active. Real payments will be processed.', color: C.red),
      ],
      _SaveBtn(onSave: () {}),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 14. ACCOUNTING EXPORT
// ═════════════════════════════════════════════════════════════
class AccountingPage extends StatelessWidget {
  const AccountingPage({super.key});
  @override
  Widget build(BuildContext context) => _Page(
    title: 'Accounting Export', subtitle: 'Sync or export to accounting software',
    children: [
      ...[
        ('tally', 'Tally ERP 9 / Prime', '📊',
            'Export as Tally XML/CSV. Import via Tally gateway.'),
        ('zoho',  'Zoho Books',           '📚',
            'Auto-sync via Zoho Books API. Invoices & payments.'),
        ('qbo',   'QuickBooks Online',    '💼',
            'Connect via OAuth. Real-time sync.'),
        ('csv',   'Generic CSV Export',   '📋',
            'Download all transactions as CSV for any software.'),
      ].map((a) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(a.$3, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(a.$2, style: GoogleFonts.syne(fontWeight: FontWeight.w700,
                  fontSize: 14, color: C.white)),
              Text(a.$4, style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
            ])),
            SizedBox(width: 80,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: C.primary,
                    foregroundColor: C.bg, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8)),
                child: Text(a.$1 == 'csv' ? 'Export' : 'Connect',
                    style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          ]),
        ])),
      )),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 15. SUPPLIER INTEGRATION
// ═════════════════════════════════════════════════════════════
class SupplierPage extends StatefulWidget {
  const SupplierPage({super.key});
  @override
  State<SupplierPage> createState() => _SupplierState();
}

class _SupplierState extends State<SupplierPage> {
  final _url    = TextEditingController();
  final _apiKey = TextEditingController();
  bool _autoReorder = false, _emailPO = true;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Supplier Integration', subtitle: 'Auto-reorder low stock parts',
    children: [
      _infoBanner('When stock falls below reorder level, TechFix Pro can '
          'automatically create a Purchase Order and send it to your supplier.'),
      const SLabel('SUPPLIER API'),
      AppField(label: 'Supplier API URL', controller: _url,
          hint: 'https://api.supplier.com/orders'),
      AppField(label: 'API Key', controller: _apiKey,
          hint: 'Supplier-provided API key'),
      const SLabel('REORDER SETTINGS'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '🔄', title: 'Auto-Reorder on Low Stock',
            subtitle: _autoReorder ? 'Creates PO automatically' : 'Manual approval required',
            trailing: Switch(value: _autoReorder,
                onChanged: (v) => setState(() => _autoReorder = v))),
        SettingsTile(icon: '📧', title: 'Email Purchase Orders',
            subtitle: 'Send PO via email to supplier',
            trailing: Switch(value: _emailPO,
                onChanged: (v) => setState(() => _emailPO = v))),
      ]),
      _SaveBtn(onSave: () {}),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 16. AI DIAGNOSTICS
// ═════════════════════════════════════════════════════════════
class AiPage extends StatefulWidget {
  const AiPage({super.key});
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _apiKey = TextEditingController();
  bool _diagnosis = true, _pricing = false, _parts = false;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'AI Diagnostics', subtitle: 'Claude AI for smart repair suggestions',
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF0099CC)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          const Text('🤖', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          Text('Claude AI', style: GoogleFonts.syne(fontSize: 22,
              fontWeight: FontWeight.w900, color: Colors.white)),
          Text('by Anthropic', style: GoogleFonts.syne(
              fontSize: 13, color: Colors.white60)),
          const SizedBox(height: 8),
          Text('Smart repair diagnosis, pricing suggestions, and parts recommendations',
              style: GoogleFonts.syne(fontSize: 12, color: Colors.white70),
              textAlign: TextAlign.center),
        ]),
      ),
      const SizedBox(height: 16),
      const SLabel('API CONFIGURATION'),
      AppField(label: 'Anthropic API Key', controller: _apiKey,
          hint: 'sk-ant-api03-...'),
      _infoBanner('Get your API key from console.anthropic.com'),
      const SLabel('AI FEATURES'),
      SettingsGroup(title: '', tiles: [
        SettingsTile(icon: '🔍', title: 'Diagnosis Suggestions',
            subtitle: 'AI suggests likely causes from customer-reported symptoms',
            trailing: Switch(value: _diagnosis,
                onChanged: (v) => setState(() => _diagnosis = v))),
        SettingsTile(icon: '💰', title: 'Price Recommendations',
            subtitle: 'Market-rate pricing for common repairs',
            trailing: Switch(value: _pricing,
                onChanged: (v) => setState(() => _pricing = v))),
        SettingsTile(icon: '🔩', title: 'Parts Suggestions',
            subtitle: 'Auto-suggest parts needed based on diagnosis',
            trailing: Switch(value: _parts,
                onChanged: (v) => setState(() => _parts = v))),
      ]),
      _SaveBtn(onSave: () {}),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 17. APP LOCK & BIOMETRICS
// ═════════════════════════════════════════════════════════════
class AppLockPage extends StatefulWidget {
  const AppLockPage({super.key});
  @override
  State<AppLockPage> createState() => _AppLockState();
}

class _AppLockState extends State<AppLockPage> {
  bool _pinEnabled = false, _biometric = false, _autoLock = true;
  int _lockAfter = 2; // minutes
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _pinMismatch = false;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'App Lock & Biometrics', subtitle: 'Secure your shop data',
    children: [
      SettingsGroup(title: 'LOCK METHODS', tiles: [
        SettingsTile(icon: '🔢', title: 'PIN Lock',
            subtitle: _pinEnabled ? '4-digit PIN is set' : 'No PIN configured',
            trailing: Switch(value: _pinEnabled,
                onChanged: (v) => setState(() { _pinEnabled = v; if (!v) { _pin.clear(); _confirm.clear(); } }))),
        SettingsTile(icon: '🤳', title: 'Biometrics / Face ID',
            subtitle: _biometric ? 'Fingerprint or Face ID enabled' : 'Not configured',
            trailing: Switch(value: _biometric,
                onChanged: (v) => setState(() => _biometric = v))),
        SettingsTile(icon: '⏱️', title: 'Auto-Lock',
            subtitle: 'Lock after $_lockAfter min${_lockAfter == 1 ? "" : "s"} of inactivity',
            trailing: Switch(value: _autoLock,
                onChanged: (v) => setState(() => _autoLock = v))),
      ]),
      if (_autoLock) ...[
        const SLabel('AUTO-LOCK TIMEOUT'),
        Slider(
          value: _lockAfter.toDouble(), min: 1, max: 30,
          divisions: 5, activeColor: C.primary,
          label: '$_lockAfter min',
          onChanged: (v) => setState(() => _lockAfter = v.round()),
        ),
        Center(child: Text('Lock after $_lockAfter minute${_lockAfter == 1 ? "" : "s"}',
            style: GoogleFonts.syne(fontSize: 13, color: C.textMuted))),
        const SizedBox(height: 16),
      ],
      if (_pinEnabled) ...[
        const SLabel('SET PIN'),
        TextFormField(
          controller: _pin, obscureText: true, maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.syne(fontSize: 18, letterSpacing: 12, color: C.white),
          decoration: InputDecoration(
            labelText: 'Enter 4-digit PIN',
            labelStyle: GoogleFonts.syne(color: C.textMuted),
            counterText: '',
          ),
          onChanged: (_) => setState(() => _pinMismatch = false),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _confirm, obscureText: true, maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.syne(fontSize: 18, letterSpacing: 12, color: C.white),
          decoration: InputDecoration(
            labelText: 'Confirm PIN',
            labelStyle: GoogleFonts.syne(color: C.textMuted),
            counterText: '',
            errorText: _pinMismatch ? 'PINs do not match' : null,
          ),
          onChanged: (_) => setState(() => _pinMismatch = false),
        ),
        const SizedBox(height: 16),
      ],
      _SaveBtn(onSave: () {
        if (_pinEnabled) {
          if (_pin.text != _confirm.text) {
            setState(() => _pinMismatch = true);
            return;
          }
        }
      }),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 18. AUDIT LOGS
// ═════════════════════════════════════════════════════════════
class AuditLogsPage extends StatelessWidget {
  const AuditLogsPage({super.key});

  static const _logs = [
    ('2025-02-22 14:33', 'Admin',         'Job JOB-2025-0042 status → In Repair', '🔧'),
    ('2025-02-22 13:15', 'Suresh Kumar',  'Parts updated for JOB-2025-0041',       '🔩'),
    ('2025-02-22 11:00', 'Reception',     'New customer Vikram Singh added',        '👤'),
    ('2025-02-22 10:45', 'Admin',         'Product stock adjusted: S24 Screen +5', '📦'),
    ('2025-02-22 10:30', 'Admin',         'Invoice INV-2025-0041 generated',       '🧾'),
    ('2025-02-21 17:45', 'Ravi Sharma',   'Job JOB-2025-0039 cancelled',           '❌'),
    ('2025-02-21 16:00', 'Admin',         'Settings: Tax rate changed 18% → 18%',  '⚙️'),
    ('2025-02-21 14:22', 'Reception',     'Job JOB-2025-0040 checked in',          '📥'),
    ('2025-02-21 12:00', 'Suresh Kumar',  'Job JOB-2025-0038 status → Completed',  '🏁'),
  ];

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Audit Logs', subtitle: 'Complete activity trail',
    actions: [IconButton(icon: const Icon(Icons.download_outlined, color: C.primary),
        onPressed: () {})],
    children: [
      _infoBanner('All actions by all users are logged here. '
          'Logs cannot be deleted.', color: C.textMuted),
      ..._logs.map((l) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.border)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: C.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(l.$4, style: const TextStyle(fontSize: 17)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.$3, style: GoogleFonts.syne(fontSize: 13, color: C.text, height: 1.4)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.person_outline, size: 12, color: C.textMuted),
                const SizedBox(width: 4),
                Text(l.$2, style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
                const Spacer(),
                const Icon(Icons.access_time_outlined, size: 12, color: C.textMuted),
                const SizedBox(width: 4),
                Text(l.$1, style: GoogleFonts.syne(fontSize: 10, color: C.textMuted)),
              ]),
            ])),
          ]),
        ),
      )),
    ],
  );
}

// ═════════════════════════════════════════════════════════════
// 19. CLOUD BACKUP
// ═════════════════════════════════════════════════════════════
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});
  @override
  State<BackupPage> createState() => _BackupState();
}

class _BackupState extends State<BackupPage> {
  String _freq = 'Daily';
  String _location = 'Google Drive';
  bool _backing = false;

  @override
  Widget build(BuildContext context) => _Page(
    title: 'Cloud Backup', subtitle: 'Keep your data safe & restorable',
    children: [
      SCard(
        glowColor: C.green,
        child: Column(children: [
          const Text('✅', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('All data backed up', style: GoogleFonts.syne(
              fontSize: 15, fontWeight: FontWeight.w700, color: C.white)),
          Text('Last backup: Today 06:00 AM', style: GoogleFonts.syne(
              fontSize: 12, color: C.green)),
          const SizedBox(height: 4),
          Text('Size: 2.4 MB  ·  384 jobs  ·  47 customers',
              style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
        ]),
      ),
      const SizedBox(height: 16),
      const SLabel('BACKUP SCHEDULE'),
      Row(children: ['Daily', 'Weekly', 'Manual'].map((f) {
        final sel = _freq == f;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: f == 'Manual' ? 0 : 8),
          child: GestureDetector(
            onTap: () => setState(() => _freq = f),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? C.primary.withValues(alpha: 0.15) : C.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? C.primary : C.border, width: sel ? 2 : 1),
              ),
              child: Text(f, textAlign: TextAlign.center,
                  style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.w700,
                      color: sel ? C.primary : C.textMuted)),
            ),
          ),
        ));
      }).toList()),
      const SizedBox(height: 16),
      const SLabel('BACKUP LOCATION'),
      ...['Google Drive', 'iCloud', 'Local Storage'].map((loc) =>
          GestureDetector(
            onTap: () => setState(() => _location = loc),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _location == loc ? C.primary.withValues(alpha: 0.08) : C.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _location == loc ? C.primary : C.border,
                    width: _location == loc ? 2 : 1),
              ),
              child: Row(children: [
                Text(_locIcon(loc), style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(child: Text(loc, style: GoogleFonts.syne(fontWeight: FontWeight.w700,
                    fontSize: 13, color: _location == loc ? C.primary : C.white))),
                if (_location == loc) const Icon(Icons.check_circle, color: C.primary),
              ]),
            ),
          )),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 50,
        child: ElevatedButton.icon(
          onPressed: _backing ? null : () async {
            setState(() => _backing = true);
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) setState(() => _backing = false);
          },
          icon: _backing
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: C.bg))
              : const Icon(Icons.cloud_upload_outlined, size: 20),
          label: Text(_backing ? 'Backing up...' : '☁️  Backup Now',
              style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14)),
          style: ElevatedButton.styleFrom(backgroundColor: C.primary, foregroundColor: C.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 50,
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.restore_outlined, size: 20),
          label: Text('Restore from Backup',
              style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14)),
          style: OutlinedButton.styleFrom(foregroundColor: C.textMuted,
              side: const BorderSide(color: C.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
    ],
  );

  String _locIcon(String l) =>
      {'Google Drive': '🟢', 'iCloud': '☁️', 'Local Storage': '💾'}[l] ?? '💾';
}

// ═════════════════════════════════════════════════════════════
// 20. EXPORT DATA
// ═════════════════════════════════════════════════════════════
class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});
  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  final Map<String, bool> _exporting = {};
  int _exportedCount = 0; // rows in last export, shown in snackbar

  final _exports = [
    ('jobs',      '🔧', 'All Repair Jobs',          'Complete job history with status, costs & timeline'),
    ('customers', '👥', 'Customers List',            'Names, phones, tier, spend history'),
    ('inventory', '📦', 'Inventory & Stock',         'Products, SKUs, prices, stock levels'),
    ('invoices',  '🧾', 'Invoices & Receipts',       'All generated invoices with line items'),
    ('payments',  '💰', 'Payment Transactions',       'All payments received and pending'),
    ('finance',   '📊', 'Financial Summary Report',  'Revenue, costs, tax, profit summary'),
  ];

  @override
  void initState() {
    super.initState();
    _fromCtrl = TextEditingController(text: '2025-01-01');
    _toCtrl   = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  // ── date helpers ──────────────────────────────────────────
  DateTime get _from =>
      DateTime.tryParse(_fromCtrl.text) ?? DateTime(2020);
  DateTime get _to {
    final d = DateTime.tryParse(_toCtrl.text) ?? DateTime.now();
    return DateTime(d.year, d.month, d.day, 23, 59, 59);
  }

  bool _inRange(String isoDate) {
    if (isoDate.isEmpty) return true;
    try {
      final dt = DateTime.parse(isoDate.replaceAll(' ', 'T'));
      return !dt.isBefore(_from) && !dt.isAfter(_to);
    } catch (_) { return true; }
  }

  // ── CSV helpers ───────────────────────────────────────────
  static String _esc(dynamic v) {
    final s = (v ?? '').toString().replaceAll('"', '""');
    return s.contains(',') || s.contains('"') || s.contains('\n')
        ? '"$s"' : s;
  }

  static String _buildCsv(List<String> headers, List<List<dynamic>> rows) {
    final buf = StringBuffer();
    buf.writeln(headers.map(_esc).join(','));
    for (final r in rows) { buf.writeln(r.map(_esc).join(',')); }
    return buf.toString();
  }

  void _download(String csv, String filename) {
    final bytes = utf8.encode(csv);
    final blob  = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8;'),
    );
    final url = web.URL.createObjectURL(blob);
    final a   = web.document.createElement('a') as web.HTMLAnchorElement
      ..href     = url
      ..download = filename;
    web.document.body!.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
  }

  // ── Export builders ───────────────────────────────────────
  String _exportJobs() {
    final jobs = ref.read(jobsProvider)
        .where((j) => _inRange(j.createdAt)).toList();
    _exportedCount = jobs.length;
    final headers = [
      'Job #','Status','Payment Status','Customer','Phone',
      'Brand','Model','IMEI','Problem','Technician',
      'Parts Cost','Labor Cost','Discount','Tax','Total',
      'Amount Paid','Payment Method','Priority',
      'Created At','Estimated End','Updated At','Warranty Expiry',
    ];
    final rows = jobs.map((j) => [
      j.jobNumber, j.status, j.paymentStatus,
      j.customerName, j.customerPhone,
      j.brand, j.model, j.imei, j.problem, j.technicianName,
      j.partsCost.toStringAsFixed(2),
      j.laborCost.toStringAsFixed(2),
      j.discountAmount.toStringAsFixed(2),
      j.taxAmount.toStringAsFixed(2),
      j.totalAmount.toStringAsFixed(2),
      j.amountPaid.toStringAsFixed(2),
      j.paymentMethod, j.priority,
      j.createdAt, j.estimatedEndDate, j.updatedAt,
      j.warrantyExpiry ?? '',
    ]).toList();
    return _buildCsv(headers, rows);
  }

  String _exportCustomers() {
    final customers = ref.read(customersProvider)
        .where((c) => _inRange(c.createdAt)).toList();
    _exportedCount = customers.length;
    final headers = [
      'Name','Phone','Email','Address','Tier','VIP',
      'Blacklisted','Points','Repairs','Total Spend',
      'Notes','Created At',
    ];
    final rows = customers.map((c) => [
      c.name, c.phone, c.email, c.address,
      c.tier, c.isVip ? 'Yes' : 'No',
      c.isBlacklisted ? 'Yes' : 'No',
      c.points, c.repairsCount,
      c.totalSpend.toStringAsFixed(2),
      c.notes, c.createdAt,
    ]).toList();
    return _buildCsv(headers, rows);
  }

  String _exportInventory() {
    final products = ref.read(productsProvider);
    _exportedCount = products.length;
    final headers = [
      'SKU','Product Name','Category','Brand','Supplier',
      'Cost Price','Selling Price','Margin %',
      'Stock Qty','Reorder Level','Status','Created At',
    ];
    final rows = products.map((p) {
      final margin = p.costPrice > 0
          ? ((p.sellingPrice - p.costPrice) / p.costPrice * 100).toStringAsFixed(1)
          : '—';
      return [
        p.sku, p.productName, p.category, p.brand, p.supplierName,
        p.costPrice.toStringAsFixed(2), p.sellingPrice.toStringAsFixed(2),
        margin, p.stockQty, p.reorderLevel,
        p.isActive ? 'Active' : 'Inactive', p.createdAt,
      ];
    }).toList();
    return _buildCsv(headers, rows);
  }

  Future<String> _exportInvoices() async {
    final shopId = ref.read(activeSessionProvider)?.shopId
        ?? ref.read(settingsProvider).shopId;
    final snap = await FirebaseDatabase.instance
        .ref('invoices')
        .orderByChild('shopId')
        .equalTo(shopId)
        .get();
    final invoices = <Map<String, dynamic>>[];
    if (snap.exists && snap.value is Map) {
      for (final child in (snap.value as Map).entries) {
        final d = Map<String, dynamic>.from(child.value as Map);
        if (_inRange((d['issuedAt'] as String?) ?? '')) invoices.add(d);
      }
    }
    _exportedCount = invoices.length;
    final headers = [
      'Invoice #','Job ID','Customer ID','Subtotal','Discount',
      'Tax Rate %','Tax Amount','Grand Total',
      'Payment Method','Payment Status','Amount Paid','Balance Due',
      'Issued At','Paid At',
    ];
    final rows = invoices.map((inv) => [
      inv['invoiceNumber'] ?? '',
      inv['jobId'] ?? '',
      inv['customerId'] ?? '',
      ((inv['subtotal'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
      ((inv['discount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
      ((inv['taxRate']  as num?)?.toDouble() ?? 0).toStringAsFixed(1),
      ((inv['taxAmount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
      ((inv['grandTotal'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
      inv['paymentMethod'] ?? '',
      inv['paymentStatus'] ?? '',
      ((inv['amountPaid'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
      ((inv['balanceDue'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
      inv['issuedAt'] ?? '',
      inv['paidAt'] ?? '',
    ]).toList();
    return _buildCsv(headers, rows);
  }

  String _exportPayments() {
    final txs = ref.read(transactionsProvider)
        .where((t) {
          final raw = t['time'];
          if (raw == null) return false;
          final dt = raw is int
              ? DateTime.fromMillisecondsSinceEpoch(raw)
              : DateTime.tryParse(raw.toString()) ?? DateTime(2000);
          return !dt.isBefore(_from) && !dt.isAfter(_to);
        }).toList();
    _exportedCount = txs.length;
    final headers = [
      'Transaction ID','Type','Job ID','Product Name',
      'Qty','Price','Total','Payment Method',
      'Collected By','Date',
    ];
    final rows = txs.map((t) {
      final raw = t['time'];
      final dt  = raw is int
          ? DateTime.fromMillisecondsSinceEpoch(raw)
          : DateTime.tryParse(raw.toString() ) ?? DateTime(2000);
      return [
        t['txId'] ?? '',
        t['type'] ?? '',
        t['jobId'] ?? '',
        t['productName'] ?? '',
        t['qty'] ?? '',
        ((t['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
        ((t['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
        t['payment'] ?? '',
        t['collectedBy'] ?? '',
        dt.toIso8601String().substring(0, 16),
      ];
    }).toList();
    return _buildCsv(headers, rows);
  }

  String _exportFinance() {
    // Build from transactions in range
    final txs = ref.read(transactionsProvider).where((t) {
      final raw = t['time'];
      if (raw == null) return false;
      final dt = raw is int
          ? DateTime.fromMillisecondsSinceEpoch(raw)
          : DateTime.tryParse(raw.toString()) ?? DateTime(2000);
      return !dt.isBefore(_from) && !dt.isAfter(_to);
    }).toList();

    double totalRevenue = 0, repairRevenue = 0, posRevenue = 0;
    double totalCost = 0;
    final Map<String, double> byDay = {};

    for (final t in txs) {
      final amt  = ((t['total'] as num?)?.toDouble() ?? 0);
      final cost = ((t['cost']  as num?)?.toDouble() ?? 0);
      final type = (t['type'] as String?) ?? '';
      totalRevenue += amt;
      totalCost    += cost;
      if (type == 'repair') repairRevenue += amt;
      if (type == 'pos')    posRevenue    += amt;
      final raw = t['time'];
      final dt  = raw is int
          ? DateTime.fromMillisecondsSinceEpoch(raw)
          : DateTime.tryParse(raw.toString()) ?? DateTime(2000);
      final day = dt.toIso8601String().substring(0, 10);
      byDay[day] = (byDay[day] ?? 0) + amt;
    }

    final profit = totalRevenue - totalCost;
    final margin = totalRevenue > 0
        ? (profit / totalRevenue * 100).toStringAsFixed(1) : '0.0';

    // Summary rows
    final summaryHeaders = ['Metric', 'Value'];
    final summaryRows = [
      ['Period', '${_fromCtrl.text} → ${_toCtrl.text}'],
      ['Total Revenue', '₹${totalRevenue.toStringAsFixed(2)}'],
      ['Repair Revenue', '₹${repairRevenue.toStringAsFixed(2)}'],
      ['POS Revenue', '₹${posRevenue.toStringAsFixed(2)}'],
      ['Total Cost (parts)', '₹${totalCost.toStringAsFixed(2)}'],
      ['Gross Profit', '₹${profit.toStringAsFixed(2)}'],
      ['Gross Margin %', '$margin%'],
      ['Total Transactions', '${txs.length}'],
    ];

    // Daily breakdown
    final dailyHeaders = ['Date', 'Revenue'];
    final sortedDays = byDay.keys.toList()..sort();
    final dailyRows = sortedDays
        .map((d) => [d, '₹${byDay[d]!.toStringAsFixed(2)}'])
        .toList();

    _exportedCount = summaryRows.length;

    // Two sections separated by blank line
    final buf = StringBuffer();
    buf.writeln('SUMMARY');
    buf.write(_buildCsv(summaryHeaders, summaryRows));
    buf.writeln();
    buf.writeln('DAILY BREAKDOWN');
    buf.write(_buildCsv(dailyHeaders, dailyRows));
    return buf.toString();
  }

  // ── Dispatch ──────────────────────────────────────────────
  Future<void> _doExport(String key) async {
    setState(() => _exporting[key] = true);
    try {
      final now = DateTime.now().toIso8601String().substring(0, 10);
      String csv;
      switch (key) {
        case 'jobs':      csv = _exportJobs();            break;
        case 'customers': csv = _exportCustomers();       break;
        case 'inventory': csv = _exportInventory();       break;
        case 'invoices':  csv = await _exportInvoices();  break;
        case 'payments':  csv = _exportPayments();        break;
        case 'finance':   csv = _exportFinance();         break;
        default: return;
      }
      _download(csv, 'techfix_${key}_$now.csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '✅ ${key[0].toUpperCase()}${key.substring(1)} exported'
            '${_exportedCount > 0 ? ' · $_exportedCount rows' : ''}',
            style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Export failed: $e',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting[key] = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => _Page(
    title: 'Export Data', subtitle: 'Download your shop data as CSV',
    children: [
      const SLabel('DATE RANGE'),
      Row(children: [
        Expanded(child: AppField(
          label: 'From', hint: 'YYYY-MM-DD', controller: _fromCtrl)),
        const SizedBox(width: 10),
        Expanded(child: AppField(
          label: 'To',   hint: 'YYYY-MM-DD', controller: _toCtrl)),
      ]),
      const SizedBox(height: 4),
      _infoBanner('Files download automatically. '
          'Open with Excel, Google Sheets, or Tally.'),
      const SLabel('EXPORT OPTIONS'),
      ..._exports.map((e) {
        final loading = _exporting[e.$1] == true;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.border),
            ),
            child: Row(children: [
              Text(e.$2, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.$3, style: GoogleFonts.syne(
                    fontWeight: FontWeight.w700, fontSize: 13, color: C.white)),
                Text(e.$4, style: GoogleFonts.syne(
                    fontSize: 11, color: C.textMuted)),
              ])),
              const SizedBox(width: 8),
              SizedBox(width: 84, height: 36,
                child: ElevatedButton(
                  onPressed: loading ? null : () => _doExport(e.$1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: loading ? C.bgElevated : C.primary,
                    foregroundColor: loading ? C.textMuted : C.bg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.zero,
                  ),
                  child: loading
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: C.primary))
                      : Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.download, size: 14),
                            const SizedBox(width: 4),
                            Text('CSV', style: GoogleFonts.syne(
                                fontWeight: FontWeight.w800, fontSize: 12)),
                          ]),
                ),
              ),
            ]),
          ),
        );
      }),
    ],
  );
}
