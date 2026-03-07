// ─────────────────────────────────────────────────────────────────────────────
//  screens/add_repair.dart  — New Job / Repair intake form
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/m.dart';
import '../data/providers.dart';
import '../data/active_session.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

class AddRepairScreen extends ConsumerStatefulWidget {
  final Customer? preselectedCustomer;
  const AddRepairScreen({super.key, this.preselectedCustomer});

  @override
  ConsumerState<AddRepairScreen> createState() => _AddRepairScreenState();
}

class _AddRepairScreenState extends ConsumerState<AddRepairScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _custName = TextEditingController();
  final _custPhone= TextEditingController();
  final _brand    = TextEditingController();
  final _model    = TextEditingController();
  final _imei     = TextEditingController();
  final _problem  = TextEditingController();
  final _notes    = TextEditingController();

  String  _priority = 'Normal';
  String  _techId   = '';
  String  _techName = '';
  bool    _saving   = false;

  @override
  void initState() {
    super.initState();
    final c = widget.preselectedCustomer;
    if (c != null) {
      _custName.text  = c.name;
      _custPhone.text = c.phone;
    }
  }

  @override
  void dispose() {
    _custName.dispose(); _custPhone.dispose();
    _brand.dispose();   _model.dispose();
    _imei.dispose();    _problem.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final active = ref.read(activeSessionProvider);
      final stream = ref.read(currentUserProvider).asData?.value;
      final shopId  = (active?.shopId.isNotEmpty == true)
          ? active!.shopId : (stream?.shopId ?? '');
      if (shopId.isEmpty) throw Exception('No shop linked — please sign in via lock screen.');

      final db  = FirebaseDatabase.instance;
      final now = DateTime.now();
      final jobId = db.ref('jobs').push().key!;

      // Build sequential job number
      final snap = await db.ref('jobs')
          .orderByChild('shopId').equalTo(shopId).get();
      final count = snap.exists && snap.value is Map
          ? (snap.value as Map).length + 1 : 1;
      final settings = ref.read(settingsProvider);
      final prefix   = settings.invoicePrefix.isNotEmpty
          ? settings.invoicePrefix : 'JOB';
      final jobNumber =
          '$prefix-${now.year}-${count.toString().padLeft(4, '0')}';

      // Find existing customer by phone or create a new one
      String customerId = '';
      final customers = ref.read(customersProvider);
      final phone = _custPhone.text.trim();
      Customer? match;
      try {
        match = customers.firstWhere((c) => c.phone == phone);
      } catch (_) {}

      if (match != null) {
        customerId = match.customerId;
      } else if (phone.isNotEmpty) {
        customerId = db.ref('customers').push().key!;
        await db.ref('customers/$customerId').set({
          'customerId': customerId,
          'name':       _custName.text.trim(),
          'phone':      phone,
          'email':      '',
          'address':    '',
          'tier':       'Bronze',
          'isVip':      false,
          'isBlacklisted': false,
          'points':     0,
          'repairsCount': 0,
          'totalSpend': 0.0,
          'shopId':     shopId,
          'createdAt':  now.toIso8601String(),
          'updatedAt':  now.toIso8601String(),
        });
      }

      await db.ref('jobs/$jobId').set({
        'jobId':         jobId,
        'jobNumber':     jobNumber,
        'shopId':        shopId,
        'customerId':    customerId,
        'customerName':  _custName.text.trim(),
        'customerPhone': phone,
        'brand':         _brand.text.trim(),
        'model':         _model.text.trim(),
        'imei':          _imei.text.trim(),
        'color':         '',
        'problem':       _problem.text.trim(),
        'notes':         _notes.text.trim(),
        'status':        'Checked In',
        'previousStatus': null,
        'holdReason':    null,
        'priority':      _priority,
        'technicianId':  _techId,
        'technicianName':_techName.isEmpty ? 'Unassigned' : _techName,
        'laborCost':     0.0,
        'partsCost':     0.0,
        'discountAmount':0.0,
        'taxAmount':     0.0,
        'totalAmount':   0.0,
        'partsUsed':     [],
        'intakePhotos':  [],
        'completionPhotos': [],
        'notificationSent': false,
        'notificationChannel': '',
        'reopenCount':   0,
        'createdAt':     now.toIso8601String(),
        'updatedAt':     now.toIso8601String(),
        'timeline': [
          {
            'status': 'Checked In',
            'time':   now.toIso8601String(),
            'by':     (active?.displayName ?? stream?.displayName) ?? 'Staff',
            'type':   'flow',
            'note':   'Job created',
          }
        ],
      });

      // Immediately push new job + customer to local providers
      // so the UI updates instantly (onValue listener may have slight delay)
      final newJob = Job.fromMap({
        'jobId': jobId, 'jobNumber': jobNumber, 'shopId': shopId,
        'customerId': customerId, 'customerName': _custName.text.trim(),
        'customerPhone': phone, 'brand': _brand.text.trim(),
        'model': _model.text.trim(), 'imei': _imei.text.trim(),
        'color': '', 'problem': _problem.text.trim(),
        'notes': _notes.text.trim(), 'status': 'Checked In',
        'previousStatus': null, 'holdReason': null, 'priority': _priority,
        'technicianId': _techId, 'technicianName': _techName.isEmpty ? 'Unassigned' : _techName,
        'laborCost': 0.0, 'partsCost': 0.0, 'discountAmount': 0.0,
        'taxAmount': 0.0, 'totalAmount': 0.0, 'partsUsed': [],
        'intakePhotos': [], 'completionPhotos': [],
        'notificationSent': false, 'notificationChannel': '',
        'reopenCount': 0, 'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'timeline': [{'status': 'Checked In', 'time': now.toIso8601String(),
            'by': active?.displayName ?? stream?.displayName ?? 'Staff',
            'type': 'flow', 'note': 'Job created'}],
        'subtotal': 0.0,
      });
      ref.read(jobsProvider.notifier).addJob(newJob);

      // Also add new customer to local provider if we just created one
      if (match == null && phone.isNotEmpty) {
        ref.read(customersProvider.notifier).add(Customer(
          customerId: customerId, name: _custName.text.trim(),
          phone: phone, email: '', address: '', tier: 'Bronze',
          isVip: false, isBlacklisted: false, points: 0,
          repairsCount: 0, totalSpend: 0.0, shopId: shopId,
          createdAt: now.toIso8601String(), updatedAt: now.toIso8601String(),
        ));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $jobNumber created',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e',
              style: GoogleFonts.syne(fontWeight: FontWeight.w600, fontSize: 12)),
          backgroundColor: C.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final techs = ref.watch(techsProvider);

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bgElevated,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: C.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('New Repair Job',
            style: GoogleFonts.syne(
                fontWeight: FontWeight.w800, fontSize: 16, color: C.white)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save',
                style: GoogleFonts.syne(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _saving ? C.textMuted : C.primary)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          children: [

            // ── Customer ────────────────────────────────────────
            const SLabel('CUSTOMER'),
            _field('Customer Name', _custName, required: true,
                hint: 'e.g. Rajesh Kumar'),
            _field('Phone Number', _custPhone,
                hint: '+91 XXXXX XXXXX',
                type: TextInputType.phone),

            // ── Device ──────────────────────────────────────────
            const SLabel('DEVICE'),
            _field('Brand', _brand, required: true,
                hint: 'e.g. Samsung, Apple, OnePlus'),
            _field('Model', _model, required: true,
                hint: 'e.g. Galaxy S24, iPhone 15'),
            _field('IMEI / Serial', _imei,
                hint: '15-digit IMEI or serial number',
                type: TextInputType.number),

            // ── Problem ─────────────────────────────────────────
            const SLabel('PROBLEM & NOTES'),
            _field('Problem Description', _problem, required: true,
                hint: 'e.g. Screen cracked, battery drains fast',
                maxLines: 3),
            _field('Internal Notes', _notes,
                hint: 'Accessories received, customer remarks…',
                maxLines: 2),

            // ── Assignment ──────────────────────────────────────
            const SLabel('ASSIGNMENT'),
            SCard(child: Column(children: [
              // Priority
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Priority',
                    style: GoogleFonts.syne(
                        fontSize: 14, color: C.text,
                        fontWeight: FontWeight.w600)),
                DropdownButton<String>(
                  value: _priority,
                  dropdownColor: C.bgElevated,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setState(() => _priority = v ?? 'Normal'),
                  items: ['Low', 'Normal', 'High', 'Urgent'].map((p) =>
                      DropdownMenuItem(
                        value: p,
                        child: Text(p,
                            style: GoogleFonts.syne(
                                fontSize: 13, color: _priorityColor(p),
                                fontWeight: FontWeight.w700)),
                      )).toList(),
                ),
              ]),
              if (techs.isNotEmpty) ...[
                const Divider(color: C.border, height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Assign To',
                      style: GoogleFonts.syne(
                          fontSize: 14, color: C.text,
                          fontWeight: FontWeight.w600)),
                  DropdownButton<String>(
                    value: _techId.isEmpty ? '' : _techId,
                    dropdownColor: C.bgElevated,
                    underline: const SizedBox.shrink(),
                    onChanged: (v) {
                      final t = techs.firstWhere(
                          (t) => t.techId == v,
                          orElse: () => techs.first);
                      setState(() {
                        _techId   = v ?? '';
                        _techName = v != null && v.isNotEmpty ? t.name : '';
                      });
                    },
                    items: [
                      const DropdownMenuItem(
                          value: '',
                          child: Text('Unassigned',
                              style: TextStyle(color: Colors.grey))),
                      ...techs.map((t) => DropdownMenuItem(
                            value: t.techId,
                            child: Text(t.name,
                                style: GoogleFonts.syne(
                                    fontSize: 13, color: C.white)),
                          )),
                    ],
                  ),
                ]),
              ],
            ])),

            const SizedBox(height: 24),
            PBtn(
              label: _saving ? 'Creating job…' : '➕  Create Repair Job',
              onTap: _saving ? null : _save,
              full: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {
    String? hint, TextInputType? type,
    bool required = false, int maxLines = 1,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: TextSpan(
          text: label.toUpperCase(),
          style: GoogleFonts.syne(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: C.textMuted, letterSpacing: 0.5),
          children: required
              ? [TextSpan(
                  text: ' *',
                  style: GoogleFonts.syne(color: C.accent))]
              : [],
        )),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          keyboardType: type,
          maxLines: maxLines,
          style: GoogleFonts.syne(fontSize: 13, color: C.text),
          decoration: InputDecoration(hintText: hint),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty)
                  ? '$label is required' : null
              : null,
        ),
        const SizedBox(height: 12),
      ]);

  Color _priorityColor(String p) => switch (p) {
    'Low'    => Colors.grey,
    'High'   => Colors.orange,
    'Urgent' => Colors.red,
    _        => C.primary,
  };
}
