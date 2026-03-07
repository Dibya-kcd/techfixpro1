import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/providers.dart';
import '../data/active_session.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/m.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import 'repair_detail.dart';
import 'add_repair.dart';

class RepairsScreen extends ConsumerStatefulWidget {
  const RepairsScreen({super.key});

  @override
  ConsumerState<RepairsScreen> createState() => _RepairsState();
}

class _RepairsState extends ConsumerState<RepairsScreen> {
  // Track which shopId we've synced so navigation back never re-syncs
  String? _syncedShopId;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    // Delay to next frame so ref is ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSync());
  }

  void _maybeSync() {
    final active = ref.read(activeSessionProvider);
    final stream = ref.read(currentUserProvider).asData?.value;
    final shopId  = (active?.shopId.isNotEmpty == true)
        ? active!.shopId : (stream?.shopId ?? '');
    if (shopId.isNotEmpty && _syncedShopId != shopId && !_syncing) {
      _syncing = true;
      _syncJobsFromFirebase(shopId).whenComplete(() {
        if (mounted) setState(() { _syncedShopId = shopId; _syncing = false; });
      });
    }
  }

  Future<void> _syncJobsFromFirebase(String shopId) async {
    try {
      final db = FirebaseDatabase.instance;
      final snap = await db.ref('jobs')
          .orderByChild('shopId')
          .equalTo(shopId)
          .get();
      final list = <Job>[];
      if (snap.exists && snap.children.isNotEmpty) {
        for (final child in snap.children) {
          final key = child.key;
          final value = child.value;
          if (key == null || value is! Map) continue;
          final data = Map<String, dynamic>.from(value);
          list.add(Job(
            jobId: key,
            jobNumber: (data['jobNumber'] as String?) ?? (data['num'] as String?) ?? '',
            shopId: (data['shopId'] as String?) ?? shopId,
            customerId: (data['customerId'] as String?) ?? '',
            customerName: (data['customerName'] as String?) ?? '',
            customerPhone: (data['customerPhone'] as String?) ?? '',
            brand: (data['brand'] as String?) ?? '',
            model: (data['model'] as String?) ?? '',
            imei: (data['imei'] as String?) ?? '',
            color: (data['color'] as String?) ?? '',
            problem: (data['problem'] as String?) ?? '',
            notes: (data['notes'] as String?) ?? '',
            status: (data['status'] as String?) ?? 'Checked In',
            previousStatus: data['previousStatus'] as String?,
            holdReason: data['holdReason'] as String?,
            priority: (data['priority'] as String?) ?? 'Normal',
            technicianId: (data['technicianId'] as String?) ?? (data['techId'] as String?) ?? '',
            technicianName: (data['technicianName'] as String?) ?? (data['techName'] as String?) ?? 'Unassigned',
            laborCost: (data['laborCost'] as num?)?.toDouble() ?? 0,
            partsCost: (data['partsCost'] as num?)?.toDouble() ?? 0,
            discountAmount: (data['discountAmount'] as num?)?.toDouble() ?? (data['discount'] as num?)?.toDouble() ?? 0,
            totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? (data['total'] as num?)?.toDouble() ?? 0,
            partsUsed: const [],
            intakePhotos: const [],
            completionPhotos: const [],
            timeline: const [],
            notificationSent: (data['notificationSent'] as bool?) ?? false,
            reopenCount: (data['reopenCount'] as int?) ?? 0,
            estimatedEndDate: (data['estimatedEndDate'] as String?) ?? '',
            createdAt: (data['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
            updatedAt: (data['updatedAt'] as String?) ?? DateTime.now().toIso8601String(),
          ));
        }
      }
      // Merge with any optimistic jobs already in the provider (e.g. from addJob).
      // This prevents the pattern: addJob() → pop() → rebuild → setAll() = duplicate.
      final existing = ref.read(jobsProvider);
      final merged = <String, Job>{};
      for (final j in existing) { merged[j.jobId] = j; } // keep optimistic writes
      for (final j in list)     { merged[j.jobId] = j; } // Firebase is source of truth
      ref.read(jobsProvider.notifier).setAll(merged.values.toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider);
    final search = ref.watch(searchJobProvider);
    final tab = ref.watch(jobTabProvider);
    // Watch settings — screen must rebuild when tax type/rate changes
    ref.watch(settingsProvider);
    // Watch auth state — triggers rebuild on login/logout; value read in _maybeSync
    ref.watch(currentUserProvider);

    // Filter by tab
    List<Job> filtered = jobs.where((j) {
      switch (tab) {
        case 'Active':   return j.isActive;
        case 'On Hold':  return j.isOnHold;
        case 'Ready':    return j.status == 'Ready for Pickup';
        case 'Done':     return j.isCompleted || j.isCancelled;
        default:         return true;
      }
    }).toList();

    // Search filter
    if (search.isNotEmpty) {
      final s = search.toLowerCase();
      filtered = filtered.where((j) =>
          j.jobNumber.toLowerCase().contains(s) ||
          j.customerName.toLowerCase().contains(s) ||
          j.brand.toLowerCase().contains(s) ||
          j.model.toLowerCase().contains(s) ||
          j.problem.toLowerCase().contains(s)).toList();
    }

    // Sort: overdue first, then by creation date desc
    filtered.sort((a, b) {
      if (a.isOverdue && !b.isOverdue) return -1;
      if (!a.isOverdue && b.isOverdue) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    final counts = {
      'All':     jobs.length,
      'Active':  jobs.where((j) => j.isActive).length,
      'On Hold': jobs.where((j) => j.isOnHold).length,
      'Ready':   jobs.where((j) => j.status == 'Ready for Pickup').length,
      'Done':    jobs.where((j) => j.isCompleted || j.isCancelled).length,
    };

    assert(() {
      debugPrint(
        '[RepairsScreen] tab=$tab search="$search" total=${jobs.length} filtered=${filtered.length}',
      );
      return true;
    }());

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────
          Container(
            color: C.bgElevated,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              onChanged: (v) => ref.read(searchJobProvider.notifier).state = v,
              style: GoogleFonts.syne(fontSize: 13, color: C.text),
              decoration: const InputDecoration(
                hintText: '🔍  Search job number, customer, device...',
                contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              ),
            ),
          ),

          // ── Tab bar ───────────────────────────────────────────
          Container(
            color: C.bgElevated,
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              children: counts.entries.map((e) {
                final sel = tab == e.key;
                Color tabColor = C.primary;
                if (e.key == 'On Hold') tabColor = C.yellow;
                if (e.key == 'Done') tabColor = C.textMuted;
                if (e.key == 'Ready') tabColor = C.green;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => ref.read(jobTabProvider.notifier).state = e.key,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? tabColor.withValues(alpha: 0.18) : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: sel ? tabColor : C.border,
                            width: sel ? 2 : 1),
                      ),
                      child: Row(children: [
                        Text(e.key, style: GoogleFonts.syne(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: sel ? tabColor : C.textMuted)),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: sel ? tabColor.withValues(alpha: 0.25) : C.bgCard,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text('${e.value}', style: GoogleFonts.syne(
                              fontSize: 10, fontWeight: FontWeight.w800,
                              color: sel ? tabColor : C.textMuted)),
                        ),
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Job list ──────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('📋', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text('No jobs found', style: GoogleFonts.syne(
                          fontSize: 16, fontWeight: FontWeight.w700, color: C.textMuted)),
                    ],
                  ))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _JobCard(
                      job: filtered[i],
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => RepairDetailScreen(jobId: filtered[i].jobId))),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_repairs',
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddRepairScreen())),
        backgroundColor: C.primary,
        foregroundColor: C.bg,
        icon: const Icon(Icons.add),
        label: Text('New Job', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

// ─── Job Card ─────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sc        = C.statusColor(job.status);
    final isSpecial = job.isOnHold || job.isCancelled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: C.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.border),
            boxShadow: job.isOverdue
                ? [BoxShadow(color: C.red.withValues(alpha: 0.15), blurRadius: 16)]
                : isSpecial
                    ? [BoxShadow(color: sc.withValues(alpha: 0.1), blurRadius: 12)]
                    : [const BoxShadow(color: Color(0x22000000), blurRadius: 6)],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left colour strip
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: sc,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16)),
                ),
              ),
              // Card body — Expanded so it never overflows
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Row 1: job number  |  badges  |  status pill ──
                      // All badges are optional; status pill is Flexible so it
                      // shrinks via ellipsis on narrow screens (e.g. iPhone SE).
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Job number — fixed, never shrinks
                          Text(job.jobNumber,
                              style: GoogleFonts.syne(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: C.white)),
                          // Optional badges — each guarded, no extra SizedBox
                          // when badge is absent
                          if (job.priority != 'Normal') ...[
                            const SizedBox(width: 6),
                            Pill(job.priority,
                                color: job.priority == 'Express'
                                    ? C.red : C.yellow,
                                small: true),
                          ],
                          if (job.isOverdue) ...[
                            const SizedBox(width: 4),
                            const Pill('OVERDUE', color: C.red, small: true),
                          ],
                          if (job.reopenCount > 0) ...[
                            const SizedBox(width: 4),
                            const Pill('Reopened', color: C.green, small: true),
                          ],
                          const Spacer(),
                          // Status pill: Flexible + ellipsis prevents right overflow
                          const SizedBox(width: 6),
                          Flexible(
                            child: Pill(
                              '${C.statusIcon(job.status)} ${job.status}',
                              color: sc,
                              small: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ── Row 2: Device name — ellipsis on overflow ──
                      Text(
                        '${job.brand} ${job.model}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.syne(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: C.white),
                      ),
                      const SizedBox(height: 2),

                      // ── Row 3: Customer name — Flexible prevents overflow ──
                      Row(children: [
                        const Icon(Icons.person_outline,
                            size: 13, color: C.textMuted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            job.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.syne(
                                fontSize: 12, color: C.textMuted),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),

                      // Problem — already has ellipsis, keep as-is
                      Text(job.problem,
                          style: GoogleFonts.syne(
                              fontSize: 12, color: C.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),

                      // ── Hold / Cancel reason banner ──
                      if (isSpecial &&
                          job.holdReason != null &&
                          job.holdReason!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: sc.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            '${C.statusIcon(job.status)}  ${job.holdReason}',
                            style:
                                GoogleFonts.syne(fontSize: 11, color: sc),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],

                      // ── Warranty badge ──
                      if (job.isUnderWarranty) ...[
                        const SizedBox(height: 8),
                        // mainAxisSize.min so it never stretches to full width
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: C.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: C.green.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_user,
                                      size: 12, color: C.green),
                                  const SizedBox(width: 4),
                                  Text('UNDER WARRANTY',
                                      style: GoogleFonts.syne(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: C.green)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 10),

                      // ── Row 4: Technician  |  amount  |  chevron ──
                      // Technician name is Flexible so a long name never
                      // pushes the amount off-screen on narrow devices.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (job.technicianName.isNotEmpty &&
                              job.technicianName != 'Unassigned') ...[
                            const Icon(Icons.engineering_outlined,
                                size: 13, color: C.textMuted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                job.technicianName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.syne(
                                    fontSize: 11, color: C.textMuted),
                              ),
                            ),
                            const Spacer(),
                          ] else
                            const Spacer(),
                          if (job.notificationSent)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.notifications_active,
                                  size: 14, color: C.green),
                            ),
                          // Amount — intrinsic size, never shrinks
                          Text(
                            fmtMoney(job.totalAmount),
                            style: GoogleFonts.syne(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: C.primary),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right,
                              size: 18, color: C.textDim),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
