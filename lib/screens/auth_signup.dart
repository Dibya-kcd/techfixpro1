// ─────────────────────────────────────────────────────────────────────────────
//  screens/auth_signup.dart  — Full email-verified registration
//
//  FLOW:
//  Step 1: Form (shop, name, email, phone, password, PIN)
//  Step 2: Firebase creates account → sends verification email
//          App polls every 4 s for emailVerified = true
//          User clicks link in email → auto-detected OR presses "I verified"
//  Step 3: Only NOW write shop data to Firebase DB → enter app
//
//  WHY defer DB write until after verification?
//  → Prevents abandoned unverified accounts from polluting the database.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../data/seed.dart';
import '../data/providers.dart';
import '../data/active_session.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

enum _Step { form, verifyEmail, done }

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});
  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen>
    with SingleTickerProviderStateMixin {

  final _shopName  = TextEditingController();
  final _ownerName = TextEditingController();
  final _email     = TextEditingController();
  final _phone     = TextEditingController();
  final _password  = TextEditingController();
  final _pin       = TextEditingController();

  bool    _showPassword = false;
  bool    _loading      = false;
  String? _error;
  _Step   _step         = _Step.form;

  User?   _pendingUser;
  String? _pendingShopName;
  String? _pendingOwnerName;
  String? _pendingPhone;
  String? _pendingPin;

  Timer? _pollTimer;
  int    _resendCooldown = 0;
  Timer? _cooldownTimer;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _shopName.dispose(); _ownerName.dispose(); _email.dispose();
    _phone.dispose(); _password.dispose(); _pin.dispose();
    _pollTimer?.cancel(); _cooldownTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_shopName.text.trim().isEmpty)  return 'Shop name is required';
    if (_ownerName.text.trim().isEmpty) return 'Your full name is required';
    final email = _email.text.trim();
    if (email.isEmpty) return 'Email is required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 10) return 'Phone must be 10 digits';
    if (_password.text.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) return 'App PIN must be exactly 4 digits';
    return null;
  }

  // STEP 1 → 2 ────────────────────────────────────────────────────────────────
  Future<void> _submitForm() async {
    final err = _validate();
    if (err != null) { setState(() => _error = err); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(), password: _password.text,
      );
      final user = cred.user!;
      await user.updateDisplayName(_ownerName.text.trim());
      await user.sendEmailVerification();

      _pendingUser      = user;
      _pendingShopName  = _shopName.text.trim();
      _pendingOwnerName = _ownerName.text.trim();
      _pendingPhone     = '+91 ${_phone.text.trim().replaceAll(RegExp(r'[^0-9]'), '')}';
      _pendingPin       = _pin.text;

      setState(() { _step = _Step.verifyEmail; _loading = false; });
      _startPolling();
      _startCooldown();
    } on FirebaseAuthException catch (e) {
      setState(() { _error = _friendlyError(e); _loading = false; });
    } catch (e) {
      setState(() { _error = 'Sign up failed. Try again.'; _loading = false; });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _checkVerified(silent: true);
    });
  }

  void _startCooldown([int s = 60]) {
    setState(() => _resendCooldown = s);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 1) { t.cancel(); if (mounted) setState(() => _resendCooldown = 0); }
      else { if (mounted) { setState(() => _resendCooldown--); } }
    });
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0) return;
    setState(() => _loading = true);
    try {
      await _pendingUser!.sendEmailVerification();
      _startCooldown();
    } catch (e) {
      if (mounted) { setState(() => _error = 'Could not resend. Try again.'); }
    } finally {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      await _pendingUser!.reload();
      final fresh = FirebaseAuth.instance.currentUser!;
      if (fresh.emailVerified) {
        _pollTimer?.cancel();
        await _finalizeAccount(fresh);
      } else if (!silent) {
        setState(() {
          _error = 'Email not verified yet. Check your inbox and click the link.';
          _loading = false;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() { _error = 'Check failed. Try again.'; _loading = false; });
      }
    }
  }

  // STEP 2 → 3: Write DB only after email verified ───────────────────────────
  Future<void> _finalizeAccount(User user) async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      // shopId is generated INSIDE initialize() — NOT here.
      // This ensures registrations/ and shops/ always use the same ID.
      // Passing shopId='' tells initialize() to auto-generate it.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_shopName',  _pendingShopName!);
      await prefs.setString('pending_ownerName', _pendingOwnerName!);
      await prefs.setString('pending_phone',     _pendingPhone!);
      await prefs.setString('pending_pin',       _pendingPin!);

      // initialize() returns the shopId it generated and used
      final shopId = await ShopOnboarding.initialize(
        shopId:     '',            // auto-generate inside — single source of truth
        ownerUid:   user.uid,
        ownerName:  _pendingOwnerName!,
        ownerEmail: user.email!,
        ownerPhone: _pendingPhone!,
        shopName:   _pendingShopName!,
        ownerPin:   _pendingPin!,
      );

      // Success — clear pending data
      await prefs.remove('pending_shopName');
      await prefs.remove('pending_ownerName');
      await prefs.remove('pending_phone');
      await prefs.remove('pending_pin');

      await ref.read(settingsProvider.notifier).loadFromFirebase(shopId);
      if (!mounted) return;
      setState(() { _step = _Step.done; _loading = false; });

      // Show "You're all set!" for 2s, then set active owner session.
      // _AuthGate sees activeSession != null → navigates to RootShell.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      // Read completed user record to populate session correctly
      final snap = await FirebaseDatabase.instance.ref('users/${user.uid}').get();
      final d = snap.exists && snap.value is Map
          ? Map<String, dynamic>.from(snap.value as Map) : <String, dynamic>{};
      ref.read(activeSessionProvider.notifier).loginAsOwner(
        uid:         user.uid,
        displayName: (d['displayName'] as String?) ?? _pendingOwnerName ?? '',
        role:        (d['role']        as String?) ?? 'admin',
        shopId:      shopId,
      );
      if (mounted) { Navigator.of(context).popUntil((r) => r.isFirst); }
    } catch (e) {
      // DB write failed — pending data is still in SharedPreferences.
      // Next login will auto-resume via registrations/{uid}.
      if (mounted) {
        setState(() {
          _error = 'Setup interrupted. Please log in to resume — your account was created.';
          _loading = false;
          _step = _Step.verifyEmail; // stay on screen, don't delete account
        });
      }
    }
  }

  Future<void> _cancel() async {
    _pollTimer?.cancel();
    try { await _pendingUser?.delete(); } catch (_) {}
    if (mounted) { Navigator.of(context).pop(); }
  }

  String _friendlyError(FirebaseAuthException e) => switch (e.code) {
    'email-already-in-use'  => 'An account already exists for this email.',
    'weak-password'         => 'Password is too weak (min 8 characters).',
    'invalid-email'         => 'Email address is not valid.',
    'operation-not-allowed' => 'Email sign-up is not enabled. Contact support.',
    _                       => e.message ?? 'Sign up failed.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: switch (_step) {
                  _Step.form        => _buildForm(),
                  _Step.verifyEmail => _buildVerifyEmail(),
                  _Step.done        => _buildDone(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      key: const ValueKey('form'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _AuthHeader(title: 'Create your shop', subtitle: 'Set up your TechFix Pro account'),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: C.bgCard, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: C.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _StepDots(current: 0, total: 3),
            const SizedBox(height: 20),
            AppField(label: 'Shop Name', hint: 'e.g. iCare Repairs',
                controller: _shopName, required: true),
            AppField(label: 'Your Full Name', hint: 'e.g. Kavita Singh',
                controller: _ownerName, required: true),
            AppField(label: 'Email', hint: 'owner@shop.com',
                controller: _email, keyboardType: TextInputType.emailAddress, required: true),
            AppField(
              label: 'Phone', hint: '9876543210',
              controller: _phone, prefixText: '+91 ',
              keyboardType: TextInputType.phone, required: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            AppField(
              label: 'Password', hint: 'Min 8 characters',
              controller: _password, keyboardType: TextInputType.visiblePassword,
              required: true, obscureText: !_showPassword,
              suffix: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility,
                    size: 16, color: C.textMuted),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            AppField(
              label: '4-digit Staff PIN', hint: 'Your personal unlock PIN',
              controller: _pin, keyboardType: TextInputType.number, required: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              _AuthError(_error!),
            ],
            const SizedBox(height: 16),
            PBtn(
              label: _loading ? 'Creating account…' : 'Continue',
              onTap: _loading ? null : _submitForm,
              full: true, icon: Icons.arrow_forward_rounded,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Already have an account? Sign in',
                  style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildVerifyEmail() {
    final email = _pendingUser?.email ?? _email.text.trim();
    return Column(
      key: const ValueKey('verify'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _AuthHeader(title: 'Verify your email', subtitle: 'Check your inbox to continue'),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: C.bgCard, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: C.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _StepDots(current: 1, total: 3),
            const SizedBox(height: 28),

            Center(child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: C.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: C.primary.withValues(alpha: 0.3), width: 2),
              ),
              child: const Icon(Icons.mark_email_unread_outlined,
                  color: C.primary, size: 34),
            )),
            const SizedBox(height: 20),

            Text('Check your inbox', textAlign: TextAlign.center,
                style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
            const SizedBox(height: 8),
            Text('We sent a verification link to', textAlign: TextAlign.center,
                style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
            const SizedBox(height: 4),
            Text(email, textAlign: TextAlign.center,
                style: GoogleFonts.syne(fontSize: 14, fontWeight: FontWeight.w700, color: C.primary)),
            const SizedBox(height: 8),
            Text('Click the link in the email, then tap the button below.',
                textAlign: TextAlign.center,
                style: GoogleFonts.syne(fontSize: 12, color: C.textMuted, height: 1.5)),

            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(
                  strokeWidth: 2, color: C.primary.withValues(alpha: 0.5))),
              const SizedBox(width: 8),
              Text('Checking automatically…',
                  style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
            ]),

            if (_error != null) ...[const SizedBox(height: 16), _AuthError(_error!)],

            const SizedBox(height: 24),
            PBtn(
              label: _loading ? 'Checking…' : "I've verified my email ✓",
              onTap: _loading ? null : () => _checkVerified(),
              full: true, icon: Icons.verified_outlined,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _resendCooldown > 0 || _loading ? null : _resend,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                _resendCooldown > 0 ? 'Resend in ${_resendCooldown}s' : 'Resend email',
                style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: C.textMuted,
                side: const BorderSide(color: C.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: C.border.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.info_outline_rounded, size: 13, color: C.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text("Can't find it? Check your spam / junk folder.",
                  style: GoogleFonts.syne(fontSize: 11, color: C.textMuted, height: 1.4))),
            ]),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _cancel,
              child: Text('Cancel registration',
                  style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Container(
      key: const ValueKey('done'),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: C.bgCard, borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.green.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        const _StepDots(current: 2, total: 3),
        const SizedBox(height: 32),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: C.green.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, color: C.green, size: 40),
        ),
        const SizedBox(height: 20),
        Text("You're all set!", style: GoogleFonts.syne(
            fontSize: 20, fontWeight: FontWeight.w800, color: C.white)),
        const SizedBox(height: 8),
        Text('Setting up your shop…', style: GoogleFonts.syne(
            fontSize: 13, color: C.textMuted)),
        const SizedBox(height: 24),
        const CircularProgressIndicator(),
      ]),
    );
  }
}

// ── Shared auth widgets ───────────────────────────────────────────────────────

class _AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _AuthHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [C.primary, C.primaryDark],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: C.primary.withValues(alpha: 0.3),
            blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Center(child: Text('T', style: GoogleFonts.syne(
          fontWeight: FontWeight.w900, fontSize: 24, color: C.bg))),
    ),
    const SizedBox(height: 12),
    Text(title, style: GoogleFonts.syne(
        fontSize: 22, fontWeight: FontWeight.w800, color: C.white)),
    const SizedBox(height: 4),
    Text(subtitle, style: GoogleFonts.syne(fontSize: 13, color: C.textMuted)),
  ]);
}

class _StepDots extends StatelessWidget {
  final int current;
  final int total;
  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(total, (i) {
      final active = i == current;
      final done   = i < current;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: active ? 24 : 8, height: 8,
        decoration: BoxDecoration(
          color: done ? C.green : active ? C.primary : C.border,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }),
  );
}

class _AuthError extends StatelessWidget {
  final String message;
  const _AuthError(this.message);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: C.red.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: C.red.withValues(alpha: 0.2)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.error_outline, color: C.red, size: 14),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: GoogleFonts.syne(
          fontSize: 12, color: C.red, fontWeight: FontWeight.w600, height: 1.4))),
    ]),
  );
}
