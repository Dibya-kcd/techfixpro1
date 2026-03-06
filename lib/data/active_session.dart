// ─────────────────────────────────────────────────────────────────────────────
//  data/active_session.dart
//
//  IN-APP SESSION LAYER — sits on top of Firebase Auth
//
//  Architecture:
//  ┌─────────────────────────────────────────────────────────────┐
//  │  Firebase Auth (owner signs in once — stays forever)        │
//  │  ↓ never sign out unless owner explicitly chooses           │
//  │  ┌───────────────────────────────────────────────────────┐  │
//  │  │  activeSessionProvider  (in-memory, no DB write)      │  │
//  │  │                                                       │  │
//  │  │  • null          → show StaffLockScreen               │  │
//  │  │  • SessionMode.owner  → owner is operating            │  │
//  │  │  • SessionMode.staff  → a staff member is operating   │  │
//  │  └───────────────────────────────────────────────────────┘  │
//  └─────────────────────────────────────────────────────────────┘
//
//  Flow:
//  1. Owner logs in via email/password (LoginScreen — unchanged).
//  2. RootShell starts. activeSessionProvider is null.
//  3. StaffLockScreen is shown OVER the app (owner still connected).
//  4. Staff tap their name → enter PIN → activeSessionProvider = staff session.
//  5. Owner can tap hidden logo area (5× rapid taps) to re-enter owner mode.
//  6. "Log out" button signs out THIS staff member only → back to lock screen.
//  7. Owner "Full sign out" → Firebase signOut → back to LoginScreen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
export 'package:flutter_riverpod/legacy.dart';

enum SessionMode { owner, staff }

class ActiveSession {
  final SessionMode mode;
  final String uid;          // owner uid OR staff uid
  final String displayName;
  final String role;         // 'admin' | 'manager' | 'technician' | 'reception'
  final String shopId;
  final bool isOwner;

  const ActiveSession({
    required this.mode,
    required this.uid,
    required this.displayName,
    required this.role,
    required this.shopId,
    this.isOwner = false,
  });

  bool get isStaff => mode == SessionMode.staff;

  @override
  String toString() =>
      'ActiveSession(mode=$mode, name=$displayName, role=$role)';
}

class ActiveSessionNotifier extends StateNotifier<ActiveSession?> {
  ActiveSessionNotifier() : super(null);

  /// Called right after owner Firebase login — puts the app in owner mode.
  void loginAsOwner({
    required String uid,
    required String displayName,
    required String role,
    required String shopId,
  }) {
    state = ActiveSession(
      mode: SessionMode.owner,
      uid: uid,
      displayName: displayName,
      role: role,
      shopId: shopId,
      isOwner: true,
    );
  }

  /// Called when a staff member logs in via PIN on the lock screen.
  void loginAsStaff({
    required String uid,
    required String displayName,
    required String role,
    required String shopId,
  }) {
    state = ActiveSession(
      mode: SessionMode.staff,
      uid: uid,
      displayName: displayName,
      role: role,
      shopId: shopId,
      isOwner: false,
    );
  }

  /// "Log out" this staff member → show lock screen again.
  /// Does NOT touch Firebase Auth → DB stays connected.
  void logoutStaff() => state = null;

  /// Owner chooses to operate as themselves (from hidden login).
  void resumeAsOwner({
    required String uid,
    required String displayName,
    required String role,
    required String shopId,
  }) {
    state = ActiveSession(
      mode: SessionMode.owner,
      uid: uid,
      displayName: displayName,
      role: role,
      shopId: shopId,
      isOwner: true,
    );
  }

  /// Full app reset — called by AppUtils.signOut before Firebase signOut.
  void clear() => state = null;
}

final activeSessionProvider =
    StateNotifierProvider<ActiveSessionNotifier, ActiveSession?>(
        (_) => ActiveSessionNotifier());
