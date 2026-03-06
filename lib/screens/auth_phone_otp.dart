// ─────────────────────────────────────────────────────────────────────────────
//  screens/auth_phone_otp.dart
//
//  Firebase Phone Auth — fully free on Spark plan (10 SMS/day limit)
//  No backend, no Cloud Functions, no extra packages.
//  Uses: firebase_auth (already in pubspec.yaml)
//
//  USAGE — from signup or login:
//    Navigator.push(context, MaterialPageRoute(
//      builder: (_) => PhoneOtpScreen(
//        phoneNumber: '+91 9876543210',
//        onSuccess: (user) { /* user is signed in / linked */ },
//      ),
//    ));
//
//  TWO MODES:
//  1. Standalone sign-in   — signInWithCredential()
//  2. Link to existing account — currentUser.linkWithCredential()
//     (set linkToExisting: true when calling from signup after email auth)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

enum _OtpStep { enterPhone, enterCode, done }

class PhoneOtpScreen extends StatefulWidget {
  /// Pre-filled phone number (e.g. from signup form). Can be empty.
  final String initialPhone;

  /// Called when verification is complete with the signed-in / linked user.
  final void Function(User user) onSuccess;

  /// If true, links the phone credential to the currently signed-in user
  /// instead of creating a new sign-in. Use this after email signup.
  final bool linkToExisting;

  const PhoneOtpScreen({
    super.key,
    this.initialPhone = '',
    required this.onSuccess,
    this.linkToExisting = false,
  });

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen>
    with SingleTickerProviderStateMixin {

  late final TextEditingController _phoneCtrl;
  final List<TextEditingController> _otpCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  _OtpStep _step             = _OtpStep.enterPhone;
  bool     _loading          = false;
  String?  _error;
  String?  _verificationId;
  int?     _resendToken;
  int      _resendCooldown   = 0;
  Timer?   _cooldownTimer;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.initialPhone);
    _fadeCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim  = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    for (final c in _otpCtrl) { c.dispose(); }
    for (final f in _otpFocus) { f.dispose(); }
    _cooldownTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Cooldown timer ────────────────────────────────────────────────────────
  void _startCooldown([int s = 60]) {
    setState(() => _resendCooldown = s);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendCooldown = 0);
      } else {
        if (mounted) setState(() => _resendCooldown--);
      }
    });
  }

  // ── Build phone number with country code ─────────────────────────────────
  String get _fullPhone {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    return '+91$digits';
  }

  // ── STEP 1: Send OTP ─────────────────────────────────────────────────────
  Future<void> _sendOtp({int? resendToken}) async {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 10) {
      setState(() => _error = 'Enter a valid 10-digit phone number');
      return;
    }
    setState(() { _loading = true; _error = null; });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _fullPhone,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),

      // ── Android only: auto-reads the SMS and verifies without user input ──
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _applyCredential(credential);
      },

      // ── OTP sent successfully — move to code entry ────────────────────
      codeSent: (String verificationId, int? token) {
        if (!mounted) return;
        _verificationId = verificationId;
        _resendToken    = token;
        setState(() { _step = _OtpStep.enterCode; _loading = false; });
        _startCooldown();
        // Focus first OTP box
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _otpFocus[0].requestFocus();
        });
      },

      // ── Error (wrong number, too many requests, etc.) ─────────────────
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() {
          _error   = _phoneError(e);
          _loading = false;
        });
      },

      // ── Timeout — verificationId still valid, show resend ─────────────
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  // ── STEP 2: Verify the code user typed ───────────────────────────────────
  Future<void> _verifyOtp() async {
    final code = _otpCtrl.map((c) => c.text).join();
    if (code.length != 6) {
      setState(() => _error = 'Enter the full 6-digit code');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode:        code,
      );
      await _applyCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error   = _codeError(e);
        _loading = false;
      });
      // Clear code boxes on wrong OTP
      for (final c in _otpCtrl) { c.clear(); }
      _otpFocus[0].requestFocus();
    }
  }

  // ── Apply credential: sign in OR link to existing account ────────────────
  Future<void> _applyCredential(PhoneAuthCredential credential) async {
    try {
      UserCredential result;
      if (widget.linkToExisting &&
          FirebaseAuth.instance.currentUser != null) {
        // Link phone to existing email/password account
        result = await FirebaseAuth.instance.currentUser!
            .linkWithCredential(credential);
      } else {
        // Stand-alone phone sign-in
        result = await FirebaseAuth.instance.signInWithCredential(credential);
      }
      if (!mounted) return;
      setState(() { _step = _OtpStep.done; _loading = false; });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) widget.onSuccess(result.user!);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _error = _codeError(e); _loading = false; });
    }
  }

  // ── Resend ────────────────────────────────────────────────────────────────
  Future<void> _resend() async {
    if (_resendCooldown > 0) return;
    for (final c in _otpCtrl) { c.clear(); }
    setState(() { _error = null; });
    await _sendOtp(resendToken: _resendToken);
  }

  // ── OTP box input handling ────────────────────────────────────────────────
  void _onOtpChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _otpFocus[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _otpFocus[index - 1].requestFocus();
    }
    // Auto-submit when all 6 filled
    final code = _otpCtrl.map((c) => c.text).join();
    if (code.length == 6) {
      FocusScope.of(context).unfocus();
      _verifyOtp();
    }
  }

  // ── Error messages ────────────────────────────────────────────────────────
  String _phoneError(FirebaseAuthException e) => switch (e.code) {
    'invalid-phone-number' => 'Invalid phone number. Include country code.',
    'too-many-requests'    => 'Too many attempts. Try again in a few minutes.',
    'quota-exceeded'       => 'SMS quota exceeded for today. Try email login.',
    _                      => e.message ?? 'Failed to send OTP.',
  };

  String _codeError(FirebaseAuthException e) => switch (e.code) {
    'invalid-verification-code' => 'Wrong code. Check your SMS and try again.',
    'session-expired'           => 'Code expired. Request a new one.',
    'credential-already-in-use' => 'This phone is linked to another account.',
    _                           => e.message ?? 'Verification failed.',
  };

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: C.textMuted),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: switch (_step) {
                  _OtpStep.enterPhone => _buildPhoneEntry(),
                  _OtpStep.enterCode  => _buildCodeEntry(),
                  _OtpStep.done       => _buildDone(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Phone number entry ────────────────────────────────────────────────────
  Widget _buildPhoneEntry() {
    return Column(
      key: const ValueKey('phone'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _OtpHeader(
          icon: Icons.phone_android_rounded,
          title: 'Verify your phone',
          subtitle: 'We\'ll send a 6-digit code via SMS',
        ),
        const SizedBox(height: 32),
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
              // Phone field
              Text('Mobile number', style: GoogleFonts.syne(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: C.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(children: [
                // Country code badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: C.bgElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: C.border),
                  ),
                  child: Text('+91', style: GoogleFonts.syne(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: C.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.syne(
                        fontSize: 16, fontWeight: FontWeight.w600,
                        color: C.white),
                    decoration: InputDecoration(
                      hintText: '9876543210',
                      hintStyle: GoogleFonts.syne(
                          color: C.textMuted.withValues(alpha: 0.4)),
                      filled: true,
                      fillColor: C.bgElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: C.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: C.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: C.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onSubmitted: (_) => _sendOtp(),
                  ),
                ),
              ]),

              if (_error != null) ...[
                const SizedBox(height: 12),
                _OtpError(_error!),
              ],

              const SizedBox(height: 20),
              PBtn(
                label: _loading ? 'Sending…' : 'Send OTP',
                onTap: _loading ? null : _sendOtp,
                full: true,
                icon: Icons.send_rounded,
              ),
              const SizedBox(height: 12),
              Center(child: Text(
                'Free via Firebase · No charges apply',
                style: GoogleFonts.syne(
                    fontSize: 11,
                    color: C.textMuted.withValues(alpha: 0.5)),
              )),
            ],
          ),
        ),
      ],
    );
  }

  // ── OTP code entry ────────────────────────────────────────────────────────
  Widget _buildCodeEntry() {
    return Column(
      key: const ValueKey('code'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _OtpHeader(
          icon: Icons.sms_outlined,
          title: 'Enter the code',
          subtitle: 'Sent to $_fullPhone',
        ),
        const SizedBox(height: 32),
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
              // 6 OTP boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (i) => _OtpBox(
                  controller: _otpCtrl[i],
                  focusNode:  _otpFocus[i],
                  hasError:   _error != null,
                  onChanged:  (v) => _onOtpChanged(v, i),
                )),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                _OtpError(_error!),
              ],

              if (_loading) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator(
                    strokeWidth: 2)),
              ],

              const SizedBox(height: 24),
              PBtn(
                label: _loading ? 'Verifying…' : 'Verify Code',
                onTap: _loading ? null : _verifyOtp,
                full: true,
                icon: Icons.verified_outlined,
              ),
              const SizedBox(height: 14),
              // Resend row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _step  = _OtpStep.enterPhone;
                      _error = null;
                    }),
                    child: Text('Change number',
                        style: GoogleFonts.syne(
                            fontSize: 12, color: C.textMuted)),
                  ),
                  TextButton(
                    onPressed: _resendCooldown > 0 || _loading
                        ? null
                        : _resend,
                    child: Text(
                      _resendCooldown > 0
                          ? 'Resend in ${_resendCooldown}s'
                          : 'Resend code',
                      style: GoogleFonts.syne(
                          fontSize: 12,
                          color: _resendCooldown > 0
                              ? C.textMuted
                              : C.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Done ──────────────────────────────────────────────────────────────────
  Widget _buildDone() {
    return Container(
      key: const ValueKey('done'),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: C.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: C.green.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: C.green.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: C.green, size: 36),
        ),
        const SizedBox(height: 16),
        Text('Phone verified!',
            style: GoogleFonts.syne(
                fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
        const SizedBox(height: 8),
        Text('Continuing…',
            style: GoogleFonts.syne(fontSize: 13, color: C.textMuted)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _OtpHeader extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  const _OtpHeader({required this.icon, required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        color: C.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: C.primary.withValues(alpha: 0.3), width: 2),
      ),
      child: Icon(icon, color: C.primary, size: 28),
    ),
    const SizedBox(height: 14),
    Text(title, style: GoogleFonts.syne(
        fontSize: 20, fontWeight: FontWeight.w800, color: C.white)),
    const SizedBox(height: 4),
    Text(subtitle, style: GoogleFonts.syne(
        fontSize: 12, color: C.textMuted), textAlign: TextAlign.center),
  ]);
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode             focusNode;
  final bool                  hasError;
  final void Function(String) onChanged;
  const _OtpBox({required this.controller, required this.focusNode,
      required this.hasError, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44, height: 52,
      child: TextField(
        controller:   controller,
        focusNode:    focusNode,
        textAlign:    TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength:    1,
        style: GoogleFonts.syne(
            fontSize: 20, fontWeight: FontWeight.w800,
            color: hasError ? C.red : C.white),
        decoration: InputDecoration(
          counterText: '',
          filled:    true,
          fillColor: hasError
              ? C.red.withValues(alpha: 0.08)
              : C.bgElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: hasError ? C.red : C.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: hasError
                    ? C.red.withValues(alpha: 0.5)
                    : C.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: hasError ? C.red : C.primary, width: 2),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
      ),
    );
  }
}

class _OtpError extends StatelessWidget {
  final String message;
  const _OtpError(this.message);

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
          fontSize: 12, color: C.red,
          fontWeight: FontWeight.w600, height: 1.4))),
    ]),
  );
}
