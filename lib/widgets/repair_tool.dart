// ─────────────────────────────────────────────────────────────────────────────
//  widgets/repair_tool.dart  — One-tap onboarding repair for stuck owners
//
//  Shows automatically when:
//    • Firebase user is authenticated
//    • registrations/{uid} exists
//    • users/{uid} has no shopId  (incomplete onboarding)
//
//  The owner taps "Complete Setup" — it runs resumeSetup() which now:
//    1. Writes users/{uid} fully (bypassing partial record)
//    2. Writes shops/{shopId}
//  Then navigates straight into the app.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../data/seed.dart';
import '../data/providers.dart';
import '../data/active_session.dart';
import '../theme/t.dart';

/// Call this from StaffLockScreen / _AuthGate when a stuck owner is detected.
/// Returns true if repair was needed and completed.
Future<bool> repairIfNeeded(BuildContext context, WidgetRef ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;

  // Check users/ record completeness
  final userSnap = await FirebaseDatabase.instance
      .ref('users/${user.uid}').get();
  final userMap = userSnap.exists && userSnap.value is Map
      ? Map<String, dynamic>.from(userSnap.value as Map)
      : <String, dynamic>{};
  final shopId = (userMap['shopId'] as String?) ?? '';
  if (shopId.isNotEmpty) return false; // already complete

  // Check registrations/
  final regSnap = await FirebaseDatabase.instance
      .ref('registrations/${user.uid}').get();
  if (!regSnap.exists || regSnap.value is! Map) return false;
  final reg = Map<String, dynamic>.from(regSnap.value as Map);
  final regShopId   = (reg['shopId']   as String?) ?? '';
  final regShopName = (reg['shopName'] as String?) ?? '';
  // Use ownerName from registrations/ if saved, else fall back to Auth displayName
  final regOwnerName = (reg['ownerName'] as String?)?.isNotEmpty == true
      ? reg['ownerName'] as String
      : (user.displayName ?? user.email!.split('@').first);
  final regPhone = (reg['phone'] as String?) ?? '';
  if (regShopId.isEmpty) return false;

  // Show repair dialog
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RepairDialog(
      shopName:  regShopName,
      ownerName: regOwnerName,
      email:     user.email ?? '',
      phone:     regPhone,
    ),
  );
  if (confirmed != true) return false;

  // Run repair
  try {
    await ShopOnboarding.resumeSetup(
      shopId:     regShopId,
      ownerUid:   user.uid,
      ownerName:  regOwnerName,
      ownerEmail: user.email ?? '',
      ownerPhone: regPhone,
      shopName:   regShopName,
      plan:       (reg['plan'] as String?) ?? 'free',
    );

    // Re-read completed user record
    final snap2 = await FirebaseDatabase.instance
        .ref('users/${user.uid}').get();
    if (snap2.exists && snap2.value is Map) {
      final d = Map<String, dynamic>.from(snap2.value as Map);
      ref.read(activeSessionProvider.notifier).loginAsOwner(
        uid:         user.uid,
        displayName: (d['displayName'] as String?) ?? user.displayName ?? '',
        role:        (d['role']        as String?) ?? 'admin',
        shopId:      regShopId,
      );
      await ref.read(settingsProvider.notifier).loadFromFirebase(regShopId);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: C.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text('Repair failed: $e',
            style: GoogleFonts.syne(color: C.white)),
      ));
    }
    return false;
  }
}

class _RepairDialog extends StatefulWidget {
  final String shopName;
  final String ownerName;
  final String email;
  final String phone;
  const _RepairDialog({
    required this.shopName,
    required this.ownerName,
    required this.email,
    required this.phone,
  });

  @override
  State<_RepairDialog> createState() => _RepairDialogState();
}

class _RepairDialogState extends State<_RepairDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: C.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.build_circle_outlined,
                  color: Colors.orange, size: 28),
            ),
            const SizedBox(height: 16),
            Text('Complete Your Setup',
                style: GoogleFonts.syne(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: C.white)),
            const SizedBox(height: 8),
            Text(
              'Your account was created but shop setup didn\'t finish. '
              'Tap below to complete it now.',
              textAlign: TextAlign.center,
              style: GoogleFonts.syne(fontSize: 13, color: C.textMuted),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: C.bgElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(Icons.store_outlined,  'Shop',  widget.shopName),
                  const SizedBox(height: 6),
                  _InfoRow(Icons.person_outlined, 'Owner', widget.ownerName),
                  const SizedBox(height: 6),
                  _InfoRow(Icons.email_outlined,  'Email', widget.email),
                  if (widget.phone.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _InfoRow(Icons.phone_outlined, 'Phone', widget.phone),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : () {
                  setState(() => _loading = true);
                  Navigator.of(context).pop(true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.primary,
                  foregroundColor: C.bg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Complete Setup →',
                        style: GoogleFonts.syne(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Do it later',
                  style: GoogleFonts.syne(color: C.textMuted, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 15, color: C.primary),
    const SizedBox(width: 8),
    Text('$label: ', style: GoogleFonts.syne(
        fontSize: 12, color: C.textMuted, fontWeight: FontWeight.w600)),
    Expanded(child: Text(value, style: GoogleFonts.syne(
        fontSize: 12, color: C.white, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis)),
  ]);
}
