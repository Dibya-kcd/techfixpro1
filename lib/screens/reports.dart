import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/providers.dart';
import '../theme/t.dart';
import '../widgets/w.dart';
import '../models/m.dart' as m;

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsState();
}

class _ReportsState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobs     = ref.watch(jobsProvider);
    final products = ref.watch(productsProvider);

    return Scaffold(
      backgroundColor: C.bg,
      body: Column(children: [
        Container(
          color: C.bgElevated,
          child: TabBar(
            controller: _tabs,
            indicatorColor: C.primary,
            indicatorWeight: 3,
            labelColor: C.primary,
            unselectedLabelColor: C.textMuted,
            labelStyle: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 12),
            tabs: const [
              Tab(text: '💰 Sales'),
              Tab(text: '🔧 Repairs'),
              Tab(text: '📦 Stock'),
              Tab(text: '📊 Finance'),
            ],
          ),
        ),
        Expanded(child: TabBarView(controller: _tabs, children: [
          const _SalesTab(),
          _RepairsTab(jobs: jobs),
          _StockTab(products: products),
          const _FinanceTab(),
        ])),
      ]),
    );
  }
}

// ── Sales Tab ─────────────────────────────────────────────────
class _SalesTab extends ConsumerWidget {
  const _SalesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionsProvider);
    final allJobs = ref.watch(jobsProvider);
    final width = MediaQuery.of(context).size.width;
    final gridCols = width < 900 ? 2 : width < 1200 ? 3 : 4;
    final maxWidth = width > 1200 ? 1200.0 : width;

    // Calculate real stats from transactions
    final now = DateTime.now();
    final thisMonth = txs.where((tx) {
      final date = DateTime.fromMillisecondsSinceEpoch(tx['time'] as int);
      return date.month == now.month && date.year == now.year;
    });

    final posRevenue = thisMonth.fold(0.0, (s, tx) => s + (tx['total'] as num).toDouble());
    final totalCostSales = thisMonth.fold(0.0, (s, tx) =>
        s + ((tx['cost'] as num?) ?? 0).toDouble() * (tx['qty'] as num).toDouble());

    // Include completed/delivered repair job revenue this month
    final repairRevenue = allJobs.where((j) {
      if (j.status != 'Delivered' && j.status != 'Completed') return false;
      final raw = j.updatedAt.isNotEmpty ? j.updatedAt : j.createdAt;
      final date = DateTime.tryParse(raw);
      if (date == null) return false;
      return date.month == now.month && date.year == now.year;
    }).fold(0.0, (s, j) => s + ((j.totalAmount as num?) ?? 0).toDouble());

    final totalRevenue = posRevenue + repairRevenue;
    final txCount = thisMonth.length;
    final avgOrder = txCount == 0 ? 0.0 : posRevenue / txCount;

    // Profit margin: show 0.0% when no revenue (never '—')
    final profitMargin = totalRevenue == 0
        ? '0.0%'
        : '${((totalRevenue - totalCostSales) / totalRevenue * 100).toStringAsFixed(1)}%';

    // Daily revenue for the last 7 days
    final dailyRev = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return txs.where((tx) {
        final date = DateTime.fromMillisecondsSinceEpoch(tx['time'] as int);
        return date.day == day.day && date.month == day.month && date.year == day.year;
      }).fold(0.0, (s, tx) => s + (tx['total'] as num).toDouble());
    });

    // Top selling products
    final prodSales = <String, double>{};
    for (final tx in txs) {
      final name = tx['productName'] as String;
      prodSales[name] = (prodSales[name] ?? 0) + (tx['qty'] as num).toDouble();
    }
    final topProds = prodSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final displayProds = topProds.take(5).toList();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            children: [
              GridView.count(
                crossAxisCount: gridCols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: width < 600 ? 1.1 : 1.4,
                children: [
                  KpiCard(icon: '💰', value: '₹${(totalRevenue/1000).toStringAsFixed(1)}k', label: 'Revenue', sub: 'This month', color: C.green),
                  KpiCard(icon: '🛒', value: txCount.toString(), label: 'Transactions', sub: 'This month', color: C.primary),
                  KpiCard(icon: '📈', value: profitMargin, label: 'Profit Margin', sub: 'This month', color: C.accent),
                  KpiCard(icon: '⭐', value: '₹${avgOrder.toStringAsFixed(0)}', label: 'Avg Order', sub: 'Per sale', color: C.yellow),
                ],
              ),
              const SizedBox(height: 16),
              SCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📈 Revenue (Last 7 Days)', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.white)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 160,
                      child: BarChart(
                        BarChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                getTitlesWidget: (v, _) {
                                  final day = now.subtract(Duration(days: 6 - v.toInt()));
                                  const days = ['S','M','T','W','T','F','S'];
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(days[day.weekday % 7], style: GoogleFonts.syne(fontSize: 10, color: C.textMuted)),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: dailyRev.asMap().entries.map((e) => BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value / 100, // Scale for chart
                                color: e.key == 6 ? C.primary : C.primary.withValues(alpha: 0.4),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                width: 22,
                              ),
                            ],
                          )).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🏆 Top Selling Products', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.white)),
                    const SizedBox(height: 12),
                    if (displayProds.isEmpty)
                      Center(child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text('No sales data yet', style: GoogleFonts.syne(color: C.textMuted)),
                      ))
                    else
                      ...displayProds.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(color: C.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: const Center(child: Text('📦', style: TextStyle(fontSize: 14))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(e.key, style: GoogleFonts.syne(fontSize: 13, color: C.text), overflow: TextOverflow.ellipsis)),
                            Text('${e.value.toInt()} sold', style: GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700, color: C.primary)),
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Repairs Tab ───────────────────────────────────────────────
class _RepairsTab extends ConsumerWidget {
  final List jobs;
  const _RepairsTab({required this.jobs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final techs = ref.watch(techsProvider);
    final width = MediaQuery.of(context).size.width;
    final gridCols = width < 900 ? 2 : width < 1200 ? 3 : 4;
    final maxWidth = width > 1200 ? 1200.0 : width;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            children: [
              GridView.count(
                crossAxisCount: gridCols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: width < 600 ? 1.1 : 1.4,
                children: [
                  KpiCard(icon: '🔧', value: '${jobs.length}', label: 'Total Jobs', color: C.primary),
                  KpiCard(icon: '✅', value: '${jobs.where((j) => j.status == "Completed").length}',
                      label: 'Completed', color: C.green),
                  KpiCard(icon: '⏰', value: '${jobs.where((j) => j.isOverdue).length}',
                      label: 'Overdue', color: C.red),
                  KpiCard(icon: '⏸️', value: '${jobs.where((j) => j.isOnHold).length}',
                      label: 'On Hold', color: C.yellow),
                ],
              ),
              const SizedBox(height: 16),
              SCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Technician Performance',
                      style: GoogleFonts.syne(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: C.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...techs.map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: (t.isActive ? C.primary : C.textMuted)
                                  .withValues(alpha: 0.2),
                              radius: 20,
                              child: Text(
                                t.name[0],
                                style: GoogleFonts.syne(
                                  fontWeight: FontWeight.w800,
                                  color: t.isActive ? C.primary : C.textMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: GoogleFonts.syne(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: C.text,
                                    ),
                                  ),
                                  Text(
                                    '${t.totalJobs} jobs · ${t.specialization}',
                                    style: GoogleFonts.syne(
                                      fontSize: 11,
                                      color: C.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '⭐ ${t.rating}',
                              style: GoogleFonts.syne(
                                fontWeight: FontWeight.w700,
                                color: C.yellow,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stock Tab ─────────────────────────────────────────────────
class _StockTab extends StatelessWidget {
  final List products;
  const _StockTab({required this.products});

  @override
  Widget build(BuildContext context) {
    final totalVal = products.fold(0.0, (s, p) => s + (p as m.Product).costPrice * p.stockQty);
    final low = products.where((p) => (p as m.Product).isLowStock).toList();
    final out = products.where((p) => (p as m.Product).isOutOfStock).toList();

    final width = MediaQuery.of(context).size.width;
    final gridCols = width < 900 ? 2 : width < 1200 ? 3 : 4;
    final maxWidth = width > 1200 ? 1200.0 : width;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            children: [
              GridView.count(
                crossAxisCount: gridCols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: width < 600 ? 1.1 : 1.4,
                children: [
                  KpiCard(
                    icon: '📦',
                    value: '₹${(totalVal / 1000).toStringAsFixed(0)}k',
                    label: 'Stock Value',
                    color: C.primary,
                  ),
                  KpiCard(
                    icon: '⚠️',
                    value: '${low.length}',
                    label: 'Low Stock',
                    color: C.yellow,
                  ),
                  KpiCard(
                    icon: '🚫',
                    value: '${out.length}',
                    label: 'Out of Stock',
                    color: C.red,
                  ),
                  KpiCard(
                    icon: '📊',
                    value: '${products.length}',
                    label: 'Total SKUs',
                    color: C.green,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (low.isNotEmpty || out.isNotEmpty)
                SCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reorder Report',
                        style: GoogleFonts.syne(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: C.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...[...out, ...low].map(
                        (p) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Text(
                                p.isOutOfStock ? '🚫' : '⚠️',
                                style: const TextStyle(fontSize: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (p as m.Product).productName,
                                      style: GoogleFonts.syne(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: C.text,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${p.stockQty} remaining · Min: ${p.reorderLevel}',
                                      style: GoogleFonts.syne(
                                        fontSize: 11,
                                        color: C.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PBtn(
                                label: 'Order',
                                onTap: () {},
                                small: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Finance Tab ───────────────────────────────────────────────
class _FinanceTab extends ConsumerWidget {
  const _FinanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionsProvider);
    final width = MediaQuery.of(context).size.width;
    final gridCols = width < 600 ? 2 : width < 900 ? 2 : width < 1200 ? 3 : 4;
    final maxWidth = width > 1200 ? 1200.0 : width;

    // Calculate real finance stats
    final now = DateTime.now();
    final thisMonth = txs.where((tx) {
      final date = DateTime.fromMillisecondsSinceEpoch(tx['time'] as int);
      return date.month == now.month && date.year == now.year;
    });

    final grossRevenue = thisMonth.fold(0.0, (s, tx) => s + (tx['total'] as num).toDouble());
    final totalCost = thisMonth.fold(0.0, (s, tx) => s + ((tx['cost'] as num?) ?? 0).toDouble() * (tx['qty'] as num).toDouble());
    final grossProfit = grossRevenue - totalCost;
    // Read from shop settings — respects No Tax / custom rate
    final rSettings   = ref.watch(settingsProvider);
    final rTaxType    = rSettings.settings['taxType'] as String? ?? 'GST';
    final rTaxRate    = rTaxType == 'No Tax' ? 0.0 : rSettings.defaultTaxRate / 100;
    final taxCollected = rTaxType == 'No Tax' ? 0.0 : grossRevenue * rTaxRate;
    final netMargin = grossRevenue == 0 ? 0.0 : (grossProfit / grossRevenue) * 100;

    // Profit data for the last 7 days
    final dailyProfit = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final dayTxs = txs.where((tx) {
        final date = DateTime.fromMillisecondsSinceEpoch(tx['time'] as int);
        return date.day == day.day && date.month == day.month && date.year == day.year;
      });
      final rev = dayTxs.fold(0.0, (s, tx) => s + (tx['total'] as num).toDouble());
      final cost = dayTxs.fold(0.0, (s, tx) => s + ((tx['cost'] as num?) ?? 0).toDouble() * (tx['qty'] as num).toDouble());
      return rev - cost;
    });

    // Aging receivables — outstanding (non-paid, non-cancelled) jobs grouped by age
    final now2 = DateTime.now();
    final allJobs = ref.watch(jobsProvider);
    double aging0to30 = 0, aging31to60 = 0, aging60plus = 0;
    for (final job in allJobs) {
      if (job.isCancelled) continue;
      if (job.status == 'Delivered') continue;
      final balance = job.totalAmount;
      if (balance <= 0) continue;
      final created = DateTime.tryParse(job.createdAt) ?? now2;
      final age = now2.difference(created).inDays;
      if (age <= 30)       { aging0to30  += balance; }
      else if (age <= 60)  { aging31to60 += balance; }
      else                 { aging60plus += balance; }
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            children: [
              GridView.count(
                crossAxisCount: gridCols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: width < 600 ? 1.1 : 1.4,
                children: [
                  KpiCard(icon: '💰', value: '₹${(grossRevenue/1000).toStringAsFixed(1)}k', label: 'Gross Revenue', color: C.green),
                  KpiCard(icon: '🧾', value: '₹${(taxCollected/1000).toStringAsFixed(1)}k',   label: 'Tax Collected', color: C.primary),
                  KpiCard(icon: '📈', value: '₹${(grossProfit/1000).toStringAsFixed(1)}k',  label: 'Gross Profit',  color: C.accent),
                  KpiCard(icon: '📊', value: '${netMargin.toStringAsFixed(1)}%',       label: 'Net Margin',    color: C.yellow),
                ],
              ),
              const SizedBox(height: 16),
              SCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('💎 Profit Trend (Last 7 Days)', style: GoogleFonts.syne(fontWeight: FontWeight.w700, fontSize: 14, color: C.white)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 160,
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: const FlTitlesData(
                            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24)),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: dailyProfit.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value / 100)).toList(),
                              isCurved: true,
                              color: C.accent,
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                              belowBarData: BarAreaData(show: true, color: C.accent.withValues(alpha: 0.1)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aging Receivables',
                      style: GoogleFonts.syne(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: C.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...[
                      ('0–30 days',  '₹${aging0to30.toStringAsFixed(0)}',  C.yellow),
                      ('31–60 days', '₹${aging31to60.toStringAsFixed(0)}', C.green),
                      ('60+ days',   '₹${aging60plus.toStringAsFixed(0)}', C.red),
                    ].map(
                      (row) => Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: C.border),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              row.$1,
                              style: GoogleFonts.syne(
                                fontSize: 13,
                                color: C.textMuted,
                              ),
                            ),
                            Text(
                              row.$2,
                              style: GoogleFonts.syne(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: row.$3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
