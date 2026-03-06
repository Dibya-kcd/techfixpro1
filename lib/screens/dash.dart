import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/m.dart';
import '../data/providers.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

class DashScreen extends ConsumerWidget {
  final VoidCallback onRepairs;
  final VoidCallback onInventory;
  final void Function(String jobId)? onOpenJob;
  const DashScreen({super.key, required this.onRepairs, required this.onInventory, this.onOpenJob});

  Future<void> _showUserSwitchDialog(BuildContext context, WidgetRef ref) async {
    final techs = ref.read(techsProvider);
    final activeTechs = techs.where((t) => t.isActive).toList();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: C.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Switch Staff Member', style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
            const SizedBox(height: 8),
            Text('Select a staff member to switch account', style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
            const SizedBox(height: 20),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: activeTechs.length,
                itemBuilder: (context, i) {
                  final t = activeTechs[i];
                  return GestureDetector(
                    onTap: () => _verifyPinAndSwitch(context, ref, t),
                    child: Container(
                      width: 80,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: C.primary.withValues(alpha: 0.15),
                            child: Text(t.name[0], style: GoogleFonts.syne(fontWeight: FontWeight.w800, color: C.primary)),
                          ),
                          const SizedBox(height: 8),
                          Text(t.name.split(' ')[0], 
                            textAlign: TextAlign.center,
                            style: GoogleFonts.syne(fontSize: 11, fontWeight: FontWeight.w600, color: C.white),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _verifyPinAndSwitch(BuildContext context, WidgetRef ref, Technician tech) {
    final pinCtrl = TextEditingController();
    Navigator.of(context).pop(); // Close selection sheet
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: C.bgCard,
        title: Text('Enter PIN for ${tech.name}', style: GoogleFonts.syne(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              obscureText: true,
              textAlign: TextAlign.center,
              maxLength: 4,
              style: GoogleFonts.syne(fontSize: 24, letterSpacing: 12, fontWeight: FontWeight.w800, color: C.primary),
              decoration: const InputDecoration(counterText: '', hintText: '••••'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          PBtn(
            label: 'Verify',
            onTap: () {
              if (pinCtrl.text == tech.pin || (tech.pin.isEmpty && pinCtrl.text == '1234')) {
                ref.read(currentStaffProvider.notifier).setStaff(tech);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Switched to ${tech.name}'), backgroundColor: C.green)
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid PIN'), backgroundColor: C.red)
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs        = ref.watch(jobsProvider);
    final products    = ref.watch(productsProvider);
    final settings    = ref.watch(settingsProvider);
    final currentStaff= ref.watch(currentStaffProvider);
    final txs         = ref.watch(transactionsProvider);
    
    final ownerName = currentStaff?.name ?? (settings.ownerName.isEmpty ? 'Admin' : settings.ownerName);
    final shopName  = settings.shopName.isEmpty ? 'TechFix Pro' : settings.shopName;
    final active    = jobs.where((j) => j.isActive).toList();
    final ready     = jobs.where((j) => j.status == 'Ready for Pickup').toList();
    final overdue   = jobs.where((j) => j.isOverdue).toList();
    final lowStock  = products.where((p) => p.isLowStock).toList();

    // ── Live KPI: Today's revenue from transactions provider ─────────────
    final now = DateTime.now();
    double todayRevenue = 0;
    double yestRevenue  = 0;
    for (final tx in txs) {
      final t = tx['time'];
      if (t == null) continue;
      final dt = t is int
          ? DateTime.fromMillisecondsSinceEpoch(t)
          : DateTime.tryParse(t.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final amt = ((tx['total'] as num?) ?? 0).toDouble();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        todayRevenue += amt;
      } else if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
        yestRevenue  += amt;
      }
    }
    // Also include completed jobs paid today (for shops not using POS transactions)
    if (todayRevenue == 0) {
      for (final j in jobs) {
        if (j.status == 'Completed' || j.status == 'Ready for Pickup') {
          try {
            final dt = DateTime.parse(j.updatedAt.replaceAll(' ', 'T'));
            if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
              todayRevenue += j.totalAmount;
            } else if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
              yestRevenue  += j.totalAmount;
            }
          } catch (_) {}
        }
      }
    }
    final revenueGrowth = yestRevenue == 0
        ? (todayRevenue > 0 ? '+100%' : '—')
        : '${todayRevenue >= yestRevenue ? '+' : ''}${((todayRevenue - yestRevenue) / yestRevenue * 100).toStringAsFixed(0)}%';
    final revenueDisplay = todayRevenue == 0
        ? '₹0'
        : todayRevenue >= 1000
            ? '₹${(todayRevenue / 1000).toStringAsFixed(1)}k'
            : '₹${todayRevenue.toStringAsFixed(0)}';

    return Scaffold(
      backgroundColor: C.bg,
      body: RefreshIndicator(
        color: C.primary,
        onRefresh: () async {},
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header greeting
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [C.primary, C.primaryDark]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(child: Text('🔧', style: TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Good morning, $ownerName 👋', style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
                      Text(shopName, style: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: C.white)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showUserSwitchDialog(context, ref),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: C.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: C.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.swap_horiz, size: 16, color: C.primary),
                          const SizedBox(width: 4),
                          Text('Switch', style: GoogleFonts.syne(fontSize: 11, fontWeight: FontWeight.w700, color: C.primary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // KPI grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final cols = width < 600
                      ? 2
                      : width < 900
                          ? 2
                          : width < 1200
                              ? 3
                              : 4;
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: width < 600 ? 1.1 : 1.3,
                    children: [
                      KpiCard(icon: '💰', value: revenueDisplay, label: "Today's Revenue", sub: revenueGrowth, color: C.green),
                      KpiCard(icon: '🔧', value: '${active.length}', label: 'Active Jobs', sub: '${ready.length} ready', color: C.primary, onTap: onRepairs),
                      KpiCard(icon: '⏰', value: '${overdue.length}', label: 'Overdue', sub: 'Attention!', color: C.red, onTap: onRepairs),
                      KpiCard(icon: '📦', value: '${lowStock.length}', label: 'Low Stock', sub: 'Items', color: C.yellow, onTap: onInventory),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // Low Stock Alert Banner
              if (lowStock.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SCard(
                    borderColor: C.yellow.withValues(alpha: 0.5),
                    glowColor: C.yellow,
                    onTap: onInventory,
                    child: Row(
                      children: [
                        const Text('⚠️', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Low Stock Alert', style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 14, color: C.white)),
                              Text('${lowStock.length} items are below reorder level', style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
                            ],
                          ),
                        ),
                        Text('View All →', style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.w700, color: C.yellow)),
                      ],
                    ),
                  ),
                ),

              // Revenue chart
              SCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📈 Revenue This Week', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.white)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 140,
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true, reservedSize: 24,
                                getTitlesWidget: (v, m) {
                                  const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
                                  final i = v.toInt();
                                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(days[i], style: GoogleFonts.syne(fontSize: 10, color: C.textMuted)),
                                  );
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: () {
                                // Live 7-day revenue from transactions
                                final spots = <FlSpot>[];
                                for (int i = 0; i < 7; i++) {
                                  final day = now.subtract(Duration(days: 6 - i));
                                  double rev = txs.fold(0.0, (s, tx) {
                                    final t = tx['time'];
                                    if (t == null) return s;
                                    final dt = t is int
                                        ? DateTime.fromMillisecondsSinceEpoch(t)
                                        : DateTime.tryParse(t.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
                                    if (dt.year == day.year && dt.month == day.month && dt.day == day.day) {
                                      return s + ((tx['total'] as num?) ?? 0).toDouble();
                                    }
                                    return s;
                                  });
                                  // Fall back to jobs if no tx data
                                  if (rev == 0) {
                                    for (final j in jobs) {
                                      if (j.status == 'Completed' || j.status == 'Ready for Pickup') {
                                        try {
                                          final dt = DateTime.parse(j.updatedAt.replaceAll(' ', 'T'));
                                          if (dt.year == day.year && dt.month == day.month && dt.day == day.day) rev += j.totalAmount;
                                        } catch (_) {}
                                      }
                                    }
                                  }
                                  spots.add(FlSpot(i.toDouble(), rev / 1000)); // in ₹k
                                }
                                return spots;
                              }(),
                              isCurved: true, color: C.primary, barWidth: 2.5,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    C.primary.withValues(alpha: 0.3),
                                    C.primary.withValues(alpha: 0),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                          minX: 0, maxX: 6, minY: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Ready for pickup
              if (ready.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('🎉 Ready for Pickup (${ready.length})', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.green)),
                    GestureDetector(onTap: onRepairs, child: Text('View →', style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700, color: C.primary))),
                  ],
                ),
                const SizedBox(height: 8),
                ...ready.map((job) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SCard(
                    glowColor: C.green,
                    onTap: () => onOpenJob?.call(job.jobId),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${job.brand} ${job.model}', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.white)),
                              Text('${job.customerName} · ${job.customerPhone}', style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(fmtMoney(job.totalAmount), style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 16, color: C.green)),
                            const SizedBox(height: 4),
                            Pill(job.notificationSent ? 'Notified ✓' : 'Not Notified',
                                color: job.notificationSent ? C.green : C.yellow, small: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: 8),
              ],

              // Active jobs
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🔧 Active Jobs', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.white)),
                  GestureDetector(onTap: onRepairs, child: Text('All →', style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700, color: C.primary))),
                ],
              ),
              const SizedBox(height: 8),
              ...active.take(3).map((job) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SCard(
                  onTap: () => onOpenJob?.call(job.jobId),
                  child: Row(
                    children: [
                      Container(width: 3, height: 48, decoration: BoxDecoration(color: C.statusColor(job.status), borderRadius: BorderRadius.circular(99))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${job.brand} ${job.model}', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.white)),
                            Text(job.customerName, style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
                          ],
                        ),
                      ),
                      Pill('${C.statusIcon(job.status)} ${job.status}', color: C.statusColor(job.status), small: true),
                    ],
                  ),
                ),
              )),

              // Low stock
              if (lowStock.isNotEmpty) ...[
                const SizedBox(height: 16),
                SCard(
                  glowColor: C.yellow,
                  onTap: onInventory,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚠️ Low Stock Alert', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.yellow)),
                      const SizedBox(height: 10),
                      ...lowStock.take(3).map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(p.productName, style: GoogleFonts.syne(fontSize: 13, color: C.text), overflow: TextOverflow.ellipsis)),
                            Text(p.isOutOfStock ? 'OUT' : '${p.stockQty} left',
                                style: GoogleFonts.syne(fontSize: 12, fontWeight: FontWeight.w700, color: p.isOutOfStock ? C.red : C.yellow)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
