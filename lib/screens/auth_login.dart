// ─────────────────────────────────────────────────────────────────────────────
//  screens/auth_login.dart  — Owner sign-in with email verification check
//
//  On login: if Firebase Auth user exists but email is NOT verified →
//  show a "please verify" banner with resend option instead of entering app.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import '../data/providers.dart';
import 'auth_signup.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool    _showPassword        = false;
  bool    _loading             = false;
  String? _error;
  bool    _needsVerification   = false;
  int     _resendCooldown      = 0;
  Timer?  _cooldownTimer;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _email.dispose(); _password.dispose();
    _cooldownTimer?.cancel(); _fadeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown([int s = 60]) {
    setState(() => _resendCooldown = s);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 1) { t.cancel(); if (mounted) setState(() => _resendCooldown = 0); }
      else { if (mounted) setState(() => _resendCooldown--); }
    });
  }

  Future<void> _login() async {
    final email    = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password');
      return;
    }
    setState(() { _loading = true; _error = null; _needsVerification = false; });
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final user = FirebaseAuth.instance.currentUser!;

      // ── Email verification gate ─────────────────────────────────────────
      if (!user.emailVerified) {
        await FirebaseAuth.instance.signOut();
        setState(() {
          _needsVerification = true;
          _loading = false;
        });
        return;
      }

      final db = FirebaseDatabase.instance;
      final uid = user.uid;

      final userSnap = await db.ref('users/$uid').get();
      if (!userSnap.exists || userSnap.value is! Map) {
        await FirebaseAuth.instance.signOut();
        setState(() => _error = 'Account not found. Contact support.');
        return;
      }
      final ud = Map<String, dynamic>.from(userSnap.value as Map);
      if (!(ud['isActive'] as bool? ?? true)) {
        await FirebaseAuth.instance.signOut();
        setState(() => _error = 'Account deactivated. Contact your admin.');
        return;
      }
      final shopId = (ud['shopId'] as String?) ?? '';
      if (shopId.isEmpty) {
        await FirebaseAuth.instance.signOut();
        setState(() => _error = 'No shop linked to this account.');
        return;
      }

      final shopSnap = await db.ref('shops/$shopId/isActive').get();
      if (shopSnap.exists && shopSnap.value == false) {
        await FirebaseAuth.instance.signOut();
        setState(() => _error = 'Shop suspended. Contact support.');
        return;
      }

      try { await ref.read(settingsProvider.notifier).loadFromFirebase(shopId); } catch (_) {}
      try { await ref.read(staffProvider.notifier).loadFromFirebase(shopId); } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shopId', shopId);
      // _AuthGate detects auth change → StaffLockScreen shown
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendlyMsg(e));
    } on FirebaseException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Login failed');
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendVerification() async {
    if (_resendCooldown > 0) return;
    setState(() => _loading = true);
    try {
      // Re-sign in silently to get fresh token for resend
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(), password: _password.text,
      );
      await cred.user!.sendEmailVerification();
      await FirebaseAuth.instance.signOut();
      _startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: C.bgElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text('Verification email sent!',
              style: GoogleFonts.syne(fontWeight: FontWeight.w600, color: C.white)),
        ));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendlyMsg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address above first');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: C.bgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text('Reset link sent to $email',
            style: GoogleFonts.syne(fontWeight: FontWeight.w600, color: C.white)),
      ));
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to send reset email');
    }
  }

  String _friendlyMsg(FirebaseAuthException e) => switch (e.code) {
    'user-not-found'    => 'No account found for that email.',
    'wrong-password'    => 'Incorrect password.',
    'invalid-email'     => 'Invalid email address.',
    'user-disabled'     => 'Account disabled. Contact support.',
    'too-many-requests' => 'Too many attempts. Try again later.',
    _                   => e.message ?? 'Login failed',
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
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Branding ───────────────────────────────────────────
                  Column(children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [C.primary, C.primaryDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(
                          color: C.primary.withValues(alpha: 0.35),
                          blurRadius: 24, offset: const Offset(0, 8))],
                      ),
                      child: Center(child: Text('T', style: GoogleFonts.syne(
                          fontWeight: FontWeight.w900, fontSize: 28, color: C.bg))),
                    ),
                    const SizedBox(height: 16),
                    Text('TechFix Pro', style: GoogleFonts.syne(
                        fontSize: 24, fontWeight: FontWeight.w800, color: C.white)),
                    const SizedBox(height: 4),
                    Text('Sign in to your shop account',
                        style: GoogleFonts.syne(fontSize: 13, color: C.textMuted)),
                  ]),
                  const SizedBox(height: 36),

                  // ── Verification banner (shown after unverified login) ──
                  if (_needsVerification) ...[
                    _VerificationBanner(
                      email: _email.text.trim(),
                      cooldown: _resendCooldown,
                      loading: _loading,
                      onResend: _resendVerification,
                      onDismiss: () => setState(() => _needsVerification = false),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Login card ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: C.bgCard,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: C.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppField(
                          label: 'Email address', hint: 'you@yourshop.com',
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          required: true,
                        ),
                        AppField(
                          label: 'Password', hint: '••••••••',
                          controller: _password,
                          keyboardType: TextInputType.visiblePassword,
                          required: true, obscureText: !_showPassword,
                          suffix: IconButton(
                            icon: Icon(
                              _showPassword ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 16, color: C.textMuted),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),

                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: C.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: C.red.withValues(alpha: 0.2)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.error_outline,
                                  color: C.red, size: 14),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!, style: GoogleFonts.syne(
                                  fontSize: 12, color: C.red,
                                  fontWeight: FontWeight.w600))),
                            ]),
                          ),
                          const SizedBox(height: 12),
                        ],

                        PBtn(
                          label: _loading ? 'Signing in…' : 'Sign In',
                          onTap: _loading ? null : _login,
                          full: true, icon: Icons.lock_open_rounded,
                        ),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _LinkBtn(
                              label: 'Create account',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const SignUpScreen())),
                            ),
                            _LinkBtn(
                              label: 'Forgot password?',
                              onTap: _resetPassword,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Center(child: Text(
                    'Staff access via PIN on the next screen',
                    style: GoogleFonts.syne(
                        fontSize: 11,
                        color: C.textMuted.withValues(alpha: 0.5)),
                  )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Email not verified banner ─────────────────────────────────────────────────
class _VerificationBanner extends StatelessWidget {
  final String     email;
  final int        cooldown;
  final bool       loading;
  final VoidCallback onResend;
  final VoidCallback onDismiss;

  const _VerificationBanner({
    required this.email,
    required this.cooldown,
    required this.loading,
    required this.onResend,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.yellow.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.yellow.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.mark_email_unread_outlined,
                color: C.yellow, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('Email not verified',
                style: GoogleFonts.syne(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: C.yellow))),
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(Icons.close_rounded,
                  size: 16, color: C.textMuted),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Please verify $email before signing in.',
            style: GoogleFonts.syne(
                fontSize: 12, color: C.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: cooldown > 0 || loading ? null : onResend,
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: Text(
                cooldown > 0
                    ? 'Resend in ${cooldown}s'
                    : 'Resend verification email',
                style: GoogleFonts.syne(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: C.yellow,
                side: BorderSide(color: C.yellow.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LinkBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(label, style: GoogleFonts.syne(
          fontSize: 12, color: C.textMuted, fontWeight: FontWeight.w600)),
    ),
  );
}
