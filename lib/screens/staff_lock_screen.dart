import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../data/providers.dart';
import '../data/active_session.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  StaffLockScreen
// ═══════════════════════════════════════════════════════════════════════════════
class StaffLockScreen extends ConsumerStatefulWidget {
  final String ownerUid;
  final String ownerShopId;

  const StaffLockScreen({
    super.key,
    required this.ownerUid,
    required this.ownerShopId,
  });

  @override
  ConsumerState<StaffLockScreen> createState() => _StaffLockScreenState();
}

class _StaffLockScreenState extends ConsumerState<StaffLockScreen>
    with TickerProviderStateMixin {
  StaffMember? _selected;
  String _pin = '';
  bool _loading = false;
  String? _error;
  int _attempts = 0;
  DateTime? _lockUntil;
  Timer? _lockTimer;

  // Logo secret tap counter
  int _logoTaps = 0;
  DateTime? _firstTap;

  // Animations
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // FIX: Reload staff on mount so the lock screen always has data.
    // loadFromFirebase in auth_login.dart may have run before the Firebase
    // token was fully ready, leaving staffProvider empty. This ensures
    // staff always appear even after app restarts or token refreshes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.ownerShopId.isNotEmpty) {
        ref.read(staffProvider.notifier).reloadIfEmpty(widget.ownerShopId);
      }
    });
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _fadeCtrl.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  // ── Lockout countdown ──────────────────────────────────────────────────────
  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lockUntil == null || DateTime.now().isAfter(_lockUntil!)) {
        _lockTimer?.cancel();
        if (mounted) setState(() { _lockUntil = null; _error = null; });
      } else {
        if (mounted) setState(() {});
      }
    });
  }

  int get _lockSecondsLeft => _lockUntil == null
      ? 0
      : _lockUntil!.difference(DateTime.now()).inSeconds.clamp(0, 999);

  // ── Hidden logo 5-tap ──────────────────────────────────────────────────────
  void _onLogoTap() {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    if (_firstTap == null || now.difference(_firstTap!).inSeconds > 4) {
      _firstTap = now;
      _logoTaps = 1;
    } else {
      _logoTaps++;
    }
    if (_logoTaps >= 5) {
      _logoTaps = 0;
      _firstTap = null;
      HapticFeedback.mediumImpact();
      _showOwnerBottomSheet();
    }
  }

  // ── Staff PIN login ────────────────────────────────────────────────────────
  Future<void> _tryLogin() async {
    if (_loading) return;
    if (_lockUntil != null && DateTime.now().isBefore(_lockUntil!)) {
      setState(() => _error = 'Locked for ${_lockSecondsLeft}s');
      return;
    }
    final staff = _selected;
    if (staff == null || _pin.length != 4) return;

    setState(() { _loading = true; _error = null; });
    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/${staff.uid}/pin')
          .get();
      final realPin = snap.exists ? (snap.value as String? ?? '') : '';

      if (realPin != _pin) {
        _attempts++;
        setState(() { _pin = ''; });
        if (_attempts >= 3) {
          _lockUntil = DateTime.now().add(const Duration(seconds: 30));
          _attempts = 0;
          _startLockTimer();
          _error = 'Too many attempts. Wait ${_lockSecondsLeft}s';
        } else {
          _error = 'Wrong PIN · ${3 - _attempts} attempt${_attempts < 2 ? "s" : ""} left';
        }
        _shakeCtrl.forward(from: 0);
        HapticFeedback.heavyImpact();
        setState(() {});
        return;
      }

      // ✅ PIN correct
      HapticFeedback.lightImpact();
      _attempts = 0;
      ref.read(activeSessionProvider.notifier).loginAsStaff(
        uid: staff.uid,
        displayName: staff.displayName,
        role: staff.role,
        shopId: staff.shopId,
      );
    } catch (e) {
      setState(() => _error = 'Login failed. Try again.');
    } finally {
      if (mounted) setState(() { _loading = false; _pin = ''; });
    }
  }

  // ── Add / remove PIN digit ─────────────────────────────────────────────────
  void _addDigit(String d) {
    if (_pin.length >= 4 || _loading) return;
    if (_lockUntil != null && DateTime.now().isBefore(_lockUntil!)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 4) _tryLogin();
  }

  void _deleteDigit() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() { _pin = _pin.substring(0, _pin.length - 1); });
  }

  // ── Owner access bottom sheet ──────────────────────────────────────────────
  void _showOwnerBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OwnerAccessSheet(
        ownerUid: widget.ownerUid,
        ownerShopId: widget.ownerShopId,
        onEnter: (name, role) {
          ref.read(activeSessionProvider.notifier).resumeAsOwner(
            uid: widget.ownerUid,
            displayName: name,
            role: role,
            shopId: widget.ownerShopId,
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffProvider)
        .where((s) => s.isActive && !s.isOwner)
        .toList();
    final locked =
        _lockUntil != null && DateTime.now().isBefore(_lockUntil!);

    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              // ── Top bar: clock | firebase dot | hidden logo ────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: time display
                    _LiveClock(),
                    // Centre: Firebase connection status dot
                    const _FirebaseDot(),
                    // Right: Shop logo — secret 5-tap zone (NO visual hint to users)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _onLogoTap,
                      child: Consumer(
                        builder: (_, ref, __) {
                          final logoUrl = ref.watch(settingsProvider).logoUrl;
                          return ShopLogo(
                            logoUrl: logoUrl.isNotEmpty ? logoUrl : null,
                            size: 40,
                            borderRadius: 11,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Greeting ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Consumer(builder: (_, ref, __) {
                      final shopName = ref.watch(settingsProvider).shopName;
                      return Text(
                        shopName.isNotEmpty ? shopName : _greeting(),
                        style: GoogleFonts.syne(
                            fontSize: 13, color: C.primary,
                            fontWeight: FontWeight.w700),
                      );
                    }),
                    const SizedBox(height: 2),
                    Text(
                      _greeting(),
                      style: GoogleFonts.syne(
                          fontSize: 12, color: C.textMuted,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selected == null
                          ? "Who's working today?"
                          : 'Enter your PIN',
                      style: GoogleFonts.syne(
                          fontSize: 26, fontWeight: FontWeight.w800,
                          color: C.white, height: 1.1),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Staff selector OR PIN entry ────────────────────────────
              Expanded(
                child: _selected == null
                    ? _StaffGrid(
                        staff: staff,
                        onOwnerAccess: _showOwnerBottomSheet,
                        onSelect: (s) => setState(() {
                          _selected = s;
                          _pin = '';
                          _error = null;
                        }),
                      )
                    : _PinSection(
                        staff: _selected!,
                        pin: _pin,
                        error: _error,
                        loading: _loading,
                        locked: locked,
                        lockSecondsLeft: _lockSecondsLeft,
                        shakeAnim: _shakeAnim,
                        onBack: () => setState(() {
                          _selected = null;
                          _pin = '';
                          _error = null;
                        }),
                        onDigit: _addDigit,
                        onDelete: _deleteDigit,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning ☀️';
    if (h < 17) return 'Good afternoon 👋';
    return 'Good evening 🌙';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Live Clock widget
// ─────────────────────────────────────────────────────────────────────────────
class _LiveClock extends StatefulWidget {
  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1),
        (_) { if (mounted) setState(() => _now = DateTime.now()); });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final m = _now.minute.toString().padLeft(2, '0');
    final period = _now.hour < 12 ? 'AM' : 'PM';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$h:$m', style: GoogleFonts.syne(
            fontSize: 22, fontWeight: FontWeight.w800, color: C.white)),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(period, style: GoogleFonts.syne(
              fontSize: 11, fontWeight: FontWeight.w700, color: C.textMuted)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Firebase connection status dot
//  • Grey pulse  = checking / waiting
//  • Red solid   = not connected to Firebase (not authenticated)
//  • Green solid = connected and authenticated
// ─────────────────────────────────────────────────────────────────────────────
class _FirebaseDot extends StatefulWidget {
  const _FirebaseDot();
  @override
  State<_FirebaseDot> createState() => _FirebaseDotState();
}

class _FirebaseDotState extends State<_FirebaseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _pulseAnim;
  bool _connected = false;
  StreamSubscription<DatabaseEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _listenToConnection();
  }

  void _listenToConnection() {
    try {
      _sub = FirebaseDatabase.instance
          .ref('.info/connected')
          .onValue
          .listen((event) {
        final isConnected = (event.snapshot.value as bool?) ?? false;
        if (mounted) setState(() => _connected = isConnected);
        if (isConnected) {
          _pulse.stop();
          _pulse.value = 1.0;
        } else {
          _pulse.repeat(reverse: true);
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulse.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check Firebase Auth state as secondary signal
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final isAuthed = firebaseUser != null && !firebaseUser.isAnonymous;
    final isLive = _connected && isAuthed;

    final color = isLive
        ? const Color(0xFF22C55E)   // bright green — connected + authed
        : _connected
            ? const Color(0xFFF59E0B) // amber — DB reachable but not authed
            : const Color(0xFFEF4444); // red — not connected

    final label = isLive
        ? 'Connected'
        : _connected ? 'Not signed in' : 'Offline';

    return Tooltip(
      message: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Outer glow ring (animated when not live)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(
                    alpha: isLive ? 0.15 : _pulseAnim.value * 0.2),
              ),
              child: Center(
                child: Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(
                        alpha: isLive ? 1.0 : _pulseAnim.value),
                    boxShadow: isLive ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ] : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.syne(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: isLive ? 0.9 : 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Staff avatar grid
// ─────────────────────────────────────────────────────────────────────────────
class _StaffGrid extends StatelessWidget {
  final List<StaffMember> staff;
  final void Function(StaffMember) onSelect;
  final VoidCallback onOwnerAccess;

  const _StaffGrid({
    required this.staff,
    required this.onSelect,
    required this.onOwnerAccess,
  });

  @override
  Widget build(BuildContext context) {
    if (staff.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: C.bgCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: C.border),
                ),
                child: Icon(Icons.people_outline,
                    size: 34, color: C.textMuted.withValues(alpha: 0.4)),
              ),
              const SizedBox(height: 16),
              Text('No staff added yet',
                  style: GoogleFonts.syne(
                      fontSize: 15, fontWeight: FontWeight.w700, color: C.white)),
              const SizedBox(height: 6),
              Text(
                'Sign in as owner to set up your team',
                textAlign: TextAlign.center,
                style: GoogleFonts.syne(
                    fontSize: 12, color: C.textMuted),
              ),
              const SizedBox(height: 28),
              // Visible owner access button — only shown when no staff exist
              GestureDetector(
                onTap: onOwnerAccess,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: C.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: C.primary.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined,
                          color: C.primary, size: 18),
                      const SizedBox(width: 10),
                      Text('Owner Access',
                          style: GoogleFonts.syne(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: C.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.9,
        ),
        itemCount: staff.length,
        itemBuilder: (_, i) => _StaffCard(member: staff[i], onTap: () => onSelect(staff[i])),
      ),
    );
  }
}

class _StaffCard extends StatefulWidget {
  final StaffMember member;
  final VoidCallback onTap;
  const _StaffCard({required this.member, required this.onTap});

  @override
  State<_StaffCard> createState() => _StaffCardState();
}

class _StaffCardState extends State<_StaffCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.93).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const _roleColors = {
    'admin': Color(0xFF7C6AF7),
    'manager': Color(0xFF3B96F5),
    'technician': Color(0xFF2EC4B6),
    'reception': Color(0xFFF5A623),
  };

  @override
  Widget build(BuildContext context) {
    final color = _roleColors[widget.member.role] ?? C.primary;
    final initials = widget.member.displayName
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          decoration: BoxDecoration(
            color: C.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: C.border, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: color.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Center(
                  child: Text(initials, style: GoogleFonts.syne(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                ),
              ),
              const SizedBox(height: 10),
              // Name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  widget.member.displayName.split(' ').first,
                  style: GoogleFonts.syne(
                      fontSize: 13, fontWeight: FontWeight.w700, color: C.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              // Role chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.member.roleLabel,
                  style: GoogleFonts.syne(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.85)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PIN entry section (shown after staff selected)
// ─────────────────────────────────────────────────────────────────────────────
class _PinSection extends StatelessWidget {
  final StaffMember staff;
  final String pin;
  final String? error;
  final bool loading;
  final bool locked;
  final int lockSecondsLeft;
  final Animation<double> shakeAnim;
  final VoidCallback onBack;
  final void Function(String) onDigit;
  final VoidCallback onDelete;

  const _PinSection({
    required this.staff,
    required this.pin,
    required this.error,
    required this.loading,
    required this.locked,
    required this.lockSecondsLeft,
    required this.shakeAnim,
    required this.onBack,
    required this.onDigit,
    required this.onDelete,
  });

  static const _roleColors = {
    'admin': Color(0xFF7C6AF7),
    'manager': Color(0xFF3B96F5),
    'technician': Color(0xFF2EC4B6),
    'reception': Color(0xFFF5A623),
  };

  @override
  Widget build(BuildContext context) {
    final color = _roleColors[staff.role] ?? C.primary;
    final initials = staff.displayName
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();

    return Column(
      children: [
        // ── Selected user header ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: [
              // Back button
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: C.bgCard,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: C.border),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 15, color: C.textMuted),
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: color.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Center(child: Text(initials, style: GoogleFonts.syne(
                    fontSize: 15, fontWeight: FontWeight.w800, color: color))),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(staff.displayName, style: GoogleFonts.syne(
                      fontSize: 15, fontWeight: FontWeight.w800, color: C.white)),
                  Text(staff.roleLabel, style: GoogleFonts.syne(
                      fontSize: 11, color: C.textMuted)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 36),

        // ── PIN dots ───────────────────────────────────────────────────────
        AnimatedBuilder(
          animation: shakeAnim,
          builder: (_, child) {
            final offset = (shakeAnim.value > 0)
                ? (shakeAnim.value * 10 * (shakeAnim.value < 0.5 ? 1 : -1))
                : 0.0;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = pin.length > i;
              final isNext = pin.length == i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: filled ? 18 : 14,
                height: filled ? 18 : 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? (error != null ? C.red : color)
                      : Colors.transparent,
                  border: Border.all(
                    color: filled
                        ? (error != null ? C.red : color)
                        : isNext
                            ? color.withValues(alpha: 0.5)
                            : C.border,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 12),

        // ── Status message ─────────────────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: error != null
              ? Text(
                  locked ? 'Locked · ${lockSecondsLeft}s remaining' : error!,
                  key: ValueKey(error),
                  style: GoogleFonts.syne(
                      fontSize: 13, color: C.red, fontWeight: FontWeight.w600),
                )
              : loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const SizedBox(height: 18),
        ),

        const Spacer(),

        // ── NumPad ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
          child: _NumPad(
            color: color,
            onDigit: onDigit,
            onDelete: onDelete,
            locked: loading || locked,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Numeric pad
// ─────────────────────────────────────────────────────────────────────────────
class _NumPad extends StatelessWidget {
  final Color color;
  final void Function(String) onDigit;
  final VoidCallback onDelete;
  final bool locked;

  const _NumPad({
    required this.color,
    required this.onDigit,
    required this.onDelete,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    const layout = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: layout.map((row) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((label) {
            if (label.isEmpty) return const SizedBox(width: 80, height: 60);
            final isDel = label == '⌫';
            return _NumKey(
              label: label,
              isDel: isDel,
              color: color,
              locked: locked,
              onTap: locked ? null : () => isDel ? onDelete() : onDigit(label),
            );
          }).toList(),
        ),
      )).toList(),
    );
  }
}

class _NumKey extends StatefulWidget {
  final String label;
  final bool isDel;
  final Color color;
  final bool locked;
  final VoidCallback? onTap;

  const _NumKey({
    required this.label,
    required this.isDel,
    required this.color,
    required this.locked,
    required this.onTap,
  });

  @override
  State<_NumKey> createState() => _NumKeyState();
}

class _NumKeyState extends State<_NumKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: widget.onTap == null ? null : (_) => _ctrl.forward(),
        onTapUp: widget.onTap == null
            ? null
            : (_) { _ctrl.reverse(); widget.onTap!(); },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          width: 80, height: 60,
          decoration: BoxDecoration(
            color: widget.isDel
                ? C.bgElevated
                : widget.locked
                    ? C.bgCard.withValues(alpha: 0.5)
                    : C.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.locked ? C.border.withValues(alpha: 0.3) : C.border,
              width: 1,
            ),
          ),
          child: Center(
            child: widget.isDel
                ? Icon(
                    Icons.backspace_outlined,
                    size: 20,
                    color: widget.locked
                        ? C.textMuted.withValues(alpha: 0.3)
                        : C.textDim,
                  )
                : Text(
                    widget.label,
                    style: GoogleFonts.syne(
                      fontSize: 22, fontWeight: FontWeight.w700,
                      color: widget.locked
                          ? C.white.withValues(alpha: 0.2)
                          : C.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _OwnerAccessSheet  — hidden bottom sheet, triggered by 5-tap logo
//
//  Step 1: Verify identity (owner PIN or email + password)
//  Step 2: Enter app as owner
//  This sheet has NO visible trigger on the lock screen.
// ═══════════════════════════════════════════════════════════════════════════════
class _OwnerAccessSheet extends ConsumerStatefulWidget {
  final String ownerUid;
  final String ownerShopId;
  final void Function(String name, String role) onEnter;

  const _OwnerAccessSheet({
    required this.ownerUid,
    required this.ownerShopId,
    required this.onEnter,
  });

  @override
  ConsumerState<_OwnerAccessSheet> createState() => _OwnerAccessSheetState();
}

class _OwnerAccessSheetState extends ConsumerState<_OwnerAccessSheet> {
  // Auth mode: PIN only usable when ownerUid is known
  late bool _pinMode;

  // Controllers
  final _pinCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _showPass = false;
  bool _loading = false;
  bool _verified = false;
  String? _error;
  String _ownerName = '';
  String _ownerRole = '';
  String _resolvedUid = '';      // uid resolved after email login
  String _resolvedShopId = '';   // shopId resolved after login

  // PIN for the owner unlock pad
  String _ownerPin = '';

  @override
  void initState() {
    super.initState();
    _pinMode = widget.ownerUid.isNotEmpty;
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Verify owner identity ──────────────────────────────────────────────────
  Future<void> _verify() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_pinMode) {
        // Verify owner PIN
        if (_ownerPin.length != 4) {
          setState(() { _error = 'Enter your 4-digit PIN'; _loading = false; });
          return;
        }
        final snap = await FirebaseDatabase.instance
            .ref('users/${widget.ownerUid}/pin')
            .get();
        final real = snap.exists ? (snap.value as String? ?? '') : '';
        if (real != _ownerPin) {
          HapticFeedback.heavyImpact();
          setState(() { _error = 'Incorrect PIN'; _ownerPin = ''; _loading = false; });
          return;
        }
      } else {
        // Verify email + password
        if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
          setState(() { _error = 'Enter email and password'; _loading = false; });
          return;
        }
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );
        // If ownerUid was provided, verify it matches
        if (widget.ownerUid.isNotEmpty && cred.user?.uid != widget.ownerUid) {
          await FirebaseAuth.instance.signOut();
          setState(() { _error = "Account does not match this shop's owner"; _loading = false; });
          return;
        }
        // Store resolved uid for data load below
        _resolvedUid = cred.user!.uid;
      }

      // Load owner data using resolved uid (may differ from widget.ownerUid if empty)
      final uid = _resolvedUid.isNotEmpty ? _resolvedUid : widget.ownerUid;
      final snap = await FirebaseDatabase.instance
          .ref('users/$uid')
          .get();
      final d = snap.exists && snap.value is Map
          ? Map<String, dynamic>.from(snap.value as Map)
          : <String, dynamic>{};

      // Store shopId for use in Enter App action
      _resolvedShopId = (d['shopId'] as String?) ?? widget.ownerShopId;

      setState(() {
        _verified = true;
        _ownerName = (d['displayName'] as String?) ?? 'Owner';
        _ownerRole = (d['role'] as String?) ?? 'admin';
      });
    } catch (e) {
      setState(() => _error = 'Verification failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addOwnerPinDigit(String d) {
    if (_ownerPin.length >= 4 || _loading) return;
    HapticFeedback.selectionClick();
    setState(() { _ownerPin += d; _error = null; });
    if (_ownerPin.length == 4) _verify();
  }

  void _deleteOwnerPinDigit() {
    if (_ownerPin.isEmpty) return;
    setState(() { _ownerPin = _ownerPin.substring(0, _ownerPin.length - 1); });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.bgElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: C.border.withValues(alpha: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              const SizedBox(height: 12),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: C.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: C.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.shield_outlined,
                          color: C.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Owner Access', style: GoogleFonts.syne(
                            fontSize: 16, fontWeight: FontWeight.w800,
                            color: C.white)),
                        Text('Verify your identity to continue',
                            style: GoogleFonts.syne(
                                fontSize: 11, color: C.textMuted)),
                      ],
                    ),
                    const Spacer(),
                    if (!_verified)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel', style: GoogleFonts.syne(
                            color: C.textMuted, fontSize: 13)),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Body
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _verified
                    ? _buildSuccessView()
                    : _buildVerifyView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Verification UI ────────────────────────────────────────────────────────
  Widget _buildVerifyView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode toggle
        Row(
          children: [
            _ModeChip(
              label: 'PIN',
              selected: _pinMode,
              icon: Icons.pin_outlined,
              onTap: () => setState(() { _pinMode = true; _error = null; _ownerPin = ''; }),
            ),
            const SizedBox(width: 8),
            _ModeChip(
              label: 'Email',
              selected: !_pinMode,
              icon: Icons.email_outlined,
              onTap: () => setState(() { _pinMode = false; _error = null; }),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_pinMode) ...[
          // Owner PIN pad
          Text('Enter owner PIN', style: GoogleFonts.syne(
              fontSize: 12, color: C.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),

          // Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = _ownerPin.length > i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: filled ? 16 : 12,
                height: filled ? 16 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled
                      ? (_error != null ? C.red : C.primary)
                      : Colors.transparent,
                  border: Border.all(
                    color: filled
                        ? (_error != null ? C.red : C.primary)
                        : C.border,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Error or loading
          if (_error != null)
            Center(child: Text(_error!, style: GoogleFonts.syne(
                fontSize: 12, color: C.red, fontWeight: FontWeight.w600))),
          if (_loading)
            const Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))),

          const SizedBox(height: 12),

          // Compact numpad for owner
          _NumPad(
            color: C.primary,
            onDigit: _addOwnerPinDigit,
            onDelete: _deleteOwnerPinDigit,
            locked: _loading,
          ),
        ] else ...[
          // Email + password fields
          AppField(
            label: 'Email', hint: 'owner@shop.com',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
          ),
          AppField(
            label: 'Password', hint: 'Enter password',
            controller: _passCtrl,
            obscureText: !_showPass,
            suffix: IconButton(
              icon: Icon(
                  _showPass ? Icons.visibility_off : Icons.visibility,
                  size: 16, color: C.textMuted),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
          ),
          if (_error != null) ...[
            Text(_error!, style: GoogleFonts.syne(
                fontSize: 12, color: C.red, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          PBtn(
            label: _loading ? 'Verifying…' : 'Verify Identity',
            onTap: _loading ? null : _verify,
            full: true,
            icon: Icons.lock_open_rounded,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ── Verified / enter app UI ────────────────────────────────────────────────
  Widget _buildSuccessView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Verified badge ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: C.green.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.green.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: C.green, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Identity Verified', style: GoogleFonts.syne(
                  fontSize: 13, fontWeight: FontWeight.w800, color: C.green)),
              Text('Welcome back, $_ownerName',
                  style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Option 1: Enter App as Admin (no role/PIN picker) ───────────
        GestureDetector(
          onTap: () {
            final uid    = _resolvedUid.isNotEmpty ? _resolvedUid : widget.ownerUid;
            final shopId = _resolvedShopId.isNotEmpty ? _resolvedShopId : widget.ownerShopId;
            // Set admin session → _AuthGate sees activeSession != null → RootShell
            ref.read(activeSessionProvider.notifier).resumeAsOwner(
              uid:         uid,
              displayName: _ownerName,
              role:        _ownerRole,
              shopId:      shopId,
            );
            Navigator.of(context).pop(); // close sheet
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: C.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.primary.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: C.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.rocket_launch_rounded,
                    color: C.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter App as Admin', style: GoogleFonts.syne(
                      fontSize: 14, fontWeight: FontWeight.w800, color: C.white)),
                  Text('Full access · no PIN required',
                      style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
                ],
              )),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 15, color: C.textMuted),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        // ── Option 2: View Staff & PINs ─────────────────────────────────
        GestureDetector(
          onTap: () {
            final shopId = _resolvedShopId.isNotEmpty
                ? _resolvedShopId
                : widget.ownerShopId;
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _StaffPinViewer(shopId: shopId),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border),
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: C.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.badge_outlined,
                    color: C.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('View Staff & PINs', style: GoogleFonts.syne(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: C.white)),
                Text('See all staff members and their access PINs',
                    style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
              ])),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: C.textMuted),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        // ── Option 3: Back to role screen ───────────────────────────────
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.border),
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: C.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.people_outline_rounded,
                    color: C.textMuted, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Back to Role Screen', style: GoogleFonts.syne(
                    fontSize: 13, fontWeight: FontWeight.w700, color: C.white)),
                Text('Staff can log in with their PIN',
                    style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
              ])),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        // ── Option 4: Sign Out from Firebase ────────────────────────────
        GestureDetector(
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: C.bgCard,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text('Sign out of Firebase?', style: GoogleFonts.syne(
                    fontWeight: FontWeight.w800, color: C.white)),
                content: Text(
                  'This will disconnect the app from the database. '
                  'Staff will not be able to use the app until you sign back in.',
                  style: GoogleFonts.syne(fontSize: 13, color: C.textMuted, height: 1.5)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel', style: GoogleFonts.syne(color: C.textMuted)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.red, foregroundColor: C.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Sign Out', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            );
            if (confirm == true && mounted) {
              Navigator.of(context).pop();
              await AppUtils.signOut(ref);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.red.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.red.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.logout_rounded, color: C.red, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sign Out from Database', style: GoogleFonts.syne(
                    fontSize: 13, fontWeight: FontWeight.w700, color: C.red)),
                Text('Disconnects Firebase on this device',
                    style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
              ])),
            ]),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Staff PIN Viewer — shown from hidden admin sheet
//  Lists all active staff with role, and PIN revealed on tap (per card)
// ─────────────────────────────────────────────────────────────────────────────
class _StaffPinViewer extends ConsumerStatefulWidget {
  final String shopId;
  const _StaffPinViewer({required this.shopId});

  @override
  ConsumerState<_StaffPinViewer> createState() => _StaffPinViewerState();
}

class _StaffPinViewerState extends ConsumerState<_StaffPinViewer> {
  // Track which staff cards have PIN revealed
  final Set<String> _revealed = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Load staff if not already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.shopId.isNotEmpty) {
        setState(() => _loading = true);
        await ref.read(staffProvider.notifier).loadFromFirebase(widget.shopId);
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  // Role → colour mapping matching the rest of the app
  Color _roleColor(String role) {
    switch (role) {
      case 'admin':       return const Color(0xFF9B59B6);
      case 'manager':     return const Color(0xFF3498DB);
      case 'technician':  return const Color(0xFF1ABC9C);
      case 'reception':   return const Color(0xFFF39C12);
      default:            return C.textMuted;
    }
  }

  String _roleEmoji(String role) {
    switch (role) {
      case 'admin':       return '👑';
      case 'manager':     return '🧑‍💼';
      case 'technician':  return '🔧';
      case 'reception':   return '🗂️';
      default:            return '👤';
    }
  }

  @override
  Widget build(BuildContext context) {
    final allStaff = ref.watch(staffProvider);
    final staff    = allStaff.where((s) => !s.isOwner).toList()
      ..sort((a, b) {
        const order = ['admin','manager','reception','technician'];
        return order.indexOf(a.role).compareTo(order.indexOf(b.role));
      });

    return Container(
      decoration: BoxDecoration(
        color: C.bgElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: C.border.withValues(alpha: 0.4)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ──────────────────────────────────────────────────
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: C.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: C.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.badge_outlined,
                        color: C.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Staff & PINs', style: GoogleFonts.syne(
                            fontSize: 16, fontWeight: FontWeight.w800,
                            color: C.white)),
                        Text('Tap any card to reveal PIN',
                            style: GoogleFonts.syne(
                                fontSize: 11, color: C.textMuted)),
                      ],
                    ),
                  ),
                  // Active count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: C.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${staff.where((s) => s.isActive).length} active',
                      style: GoogleFonts.syne(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: C.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: C.border.withValues(alpha: 0.5), height: 1),
            const SizedBox(height: 8),

            // ── Staff list ───────────────────────────────────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : staff.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('👥',
                                  style: TextStyle(fontSize: 40)),
                              const SizedBox(height: 12),
                              Text('No staff added yet',
                                  style: GoogleFonts.syne(
                                      fontSize: 14, color: C.textMuted)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          itemCount: staff.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = staff[i];
                            final revealed = _revealed.contains(s.uid);
                            final color = _roleColor(s.role);

                            return GestureDetector(
                              onTap: () => setState(() {
                                if (revealed) {
                                  _revealed.remove(s.uid);
                                } else {
                                  _revealed.add(s.uid);
                                }
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: revealed
                                      ? color.withValues(alpha: 0.08)
                                      : C.bgCard,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: revealed
                                        ? color.withValues(alpha: 0.35)
                                        : C.border.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Avatar
                                    Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Text(
                                          s.displayName.isNotEmpty
                                              ? s.displayName[0].toUpperCase()
                                              : '?',
                                          style: GoogleFonts.syne(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Name + role
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Flexible(
                                              child: Text(
                                                s.displayName,
                                                style: GoogleFonts.syne(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: s.isActive
                                                      ? C.white
                                                      : C.textMuted,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            // Active/inactive dot
                                            Container(
                                              width: 7, height: 7,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: s.isActive
                                                    ? C.green
                                                    : C.red,
                                              ),
                                            ),
                                          ]),
                                          const SizedBox(height: 3),
                                          Row(children: [
                                            Text(
                                              '${_roleEmoji(s.role)}  ${s.roleLabel}',
                                              style: GoogleFonts.syne(
                                                fontSize: 11,
                                                color: color,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (s.specialization.isNotEmpty &&
                                                s.specialization != 'General') ...[
                                              Text('  ·  ',
                                                  style: GoogleFonts.syne(
                                                      fontSize: 11,
                                                      color: C.textDim)),
                                              Text(s.specialization,
                                                  style: GoogleFonts.syne(
                                                      fontSize: 11,
                                                      color: C.textDim)),
                                            ],
                                          ]),
                                        ],
                                      ),
                                    ),

                                    // PIN display (revealed or masked)
                                    const SizedBox(width: 10),
                                    AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      child: revealed
                                          ? Container(
                                              key: const ValueKey('pin'),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                color: color.withValues(
                                                    alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                    color: color.withValues(
                                                        alpha: 0.3)),
                                              ),
                                              child: Text(
                                                s.pin.isEmpty
                                                    ? 'No PIN'
                                                    : s.pin,
                                                style: GoogleFonts.syne(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                  color: color,
                                                  letterSpacing: 4,
                                                ),
                                              ),
                                            )
                                          : Container(
                                              key: const ValueKey('mask'),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                color: C.bgCard,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                    color: C.border),
                                              ),
                                              child: Text(
                                                '••••',
                                                style: GoogleFonts.syne(
                                                  fontSize: 14,
                                                  color: C.textMuted,
                                                  letterSpacing: 4,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mode toggle chip
// ─────────────────────────────────────────────────────────────────────────────
class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? C.primary.withValues(alpha: 0.12) : C.bgCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? C.primary : C.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 14,
              color: selected ? C.primary : C.textMuted),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.syne(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: selected ? C.primary : C.textMuted)),
        ]),
      ),
    );
  }
}
