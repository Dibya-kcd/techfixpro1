import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../models/m.dart';
import '../data/providers.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final Customer? customer;
  const CustomerFormScreen({super.key, this.customer});

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustFormState();
}

class _CustFormState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name, _phone, _email, _address;
  late String _tier;
  late bool _isVip;
  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _name    = TextEditingController(text: c?.name ?? '');
    _phone   = TextEditingController(text: c?.phone ?? '');
    _email   = TextEditingController(text: c?.email ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _tier    = c?.tier ?? 'Bronze';
    _isVip   = c?.isVip ?? false;
  }

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _email.dispose(); _address.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final now = DateTime.now().toIso8601String();
    final id = _isEdit ? widget.customer!.customerId : const Uuid().v4();
    final shopId = ref.read(currentUserProvider).asData?.value?.shopId ?? '';
    final existing = widget.customer;

    final updated = (existing ?? Customer(
      customerId: id,
      shopId: shopId,
      name: '',
      phone: '',
      createdAt: now,
      updatedAt: now,
    )).copyWith(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      address: _address.text.trim(),
      tier: _tier,
      isVip: _isVip,
      updatedAt: now,
    );

    try {
      final db = FirebaseDatabase.instance;
      await db.ref('customers/$id').set({
        'customerId': updated.customerId,
        'name': updated.name,
        'phone': updated.phone,
        'email': updated.email,
        'address': updated.address,
        'tier': updated.tier,
        'isVip': updated.isVip,
        'isBlacklisted': updated.isBlacklisted,
        'points': updated.points,
        'repairsCount': updated.repairsCount,
        'totalSpend': updated.totalSpend,
        'shopId': shopId,
        'createdAt': updated.createdAt,
        'updatedAt': updated.updatedAt,
      });
      if (mounted) {
        nav.pop();
        messenger.showSnackBar(SnackBar(
          content: Text(_isEdit ? 'Customer updated!' : 'New customer added!',
              style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
          backgroundColor: C.green, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (_isEdit) {
        ref.read(customersProvider.notifier).update(updated);
      } else {
        ref.read(customersProvider.notifier).add(updated);
      }
      if (mounted) {
        nav.pop();
      }
    }
  }

  void _confirmDelete() {
     final nav = Navigator.of(context);
     showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
         backgroundColor: C.bgCard,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
         title: Text('Delete Customer?', style: GoogleFonts.syne(fontWeight: FontWeight.w800, color: C.white)),
         content: Text(
           'This will permanently remove ${widget.customer!.name}. Their repair history remains.',
           style: GoogleFonts.syne(fontSize: 13, color: C.textMuted),
         ),
         actions: [
           TextButton(onPressed: () => Navigator.pop(ctx),
               child: Text('Cancel', style: GoogleFonts.syne(color: C.textMuted))),
           ElevatedButton(
             onPressed: () async {
               final id = widget.customer!.customerId;
               try {
                 final db = FirebaseDatabase.instance;
                 await db.ref('customers/$id').remove();
               } catch (_) {}
               ref.read(customersProvider.notifier).delete(id);
               if (!context.mounted) return;
               Navigator.of(ctx).pop();
               nav.pop();
             },
             style: ElevatedButton.styleFrom(backgroundColor: C.red, foregroundColor: C.white,
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
             child: Text('Delete', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
           ),
         ],
       ),
     );
   }

  @override
  Widget build(BuildContext context) {
    final initial = _name.text.isEmpty ? '?' : _name.text[0].toUpperCase();
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Customer' : 'New Customer',
            style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('Save', style: GoogleFonts.syne(fontWeight: FontWeight.w800,
                fontSize: 15, color: C.primary)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          children: [
            // Avatar
            Center(child: Container(
              width: 72, height: 72,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [C.primary, C.primaryDark]),
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(initial,
                  style: GoogleFonts.syne(fontSize: 28, fontWeight: FontWeight.w800, color: C.bg))),
            )),
            const SizedBox(height: 24),

            const SLabel('PERSONAL DETAILS'),
            _buildField('Full Name', _name, required: true, hint: 'e.g. Rajesh Kumar',
                onChanged: (_) => setState(() {})),
            _buildField('Phone Number', _phone, required: true,
                hint: '+91 XXXXX XXXXX', type: TextInputType.phone),
            _buildField('Email Address', _email, hint: 'email@example.com',
                type: TextInputType.emailAddress),
            _buildField('Address', _address,
                hint: 'Street, City, PIN code', maxLines: 2),

            const SLabel('LOYALTY & STATUS'),
            SCard(child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Loyalty Tier', style: GoogleFonts.syne(fontSize: 14,
                    color: C.text, fontWeight: FontWeight.w600)),
                DropdownButton<String>(
                  value: _tier,
                  dropdownColor: C.bgElevated,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) => setState(() => _tier = v ?? 'Bronze'),
                  items: ['Bronze', 'Silver', 'Gold', 'Platinum'].map((t) =>
                      DropdownMenuItem(value: t, child: Row(children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(
                            color: C.tierColor(t), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(t, style: GoogleFonts.syne(fontSize: 13, color: C.tierColor(t),
                            fontWeight: FontWeight.w700)),
                      ]))).toList(),
                ),
              ]),
              const Divider(color: C.border, height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('VIP Customer 👑', style: GoogleFonts.syne(fontSize: 14,
                      color: C.text, fontWeight: FontWeight.w600)),
                  Text('Priority service & special benefits',
                      style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
                ]),
                Switch(value: _isVip, onChanged: (v) => setState(() => _isVip = v)),
              ]),
            ])),
            const SizedBox(height: 24),

            PBtn(label: _isEdit ? '💾 Update Customer' : '➕ Add Customer',
                onTap: _save, full: true, color: C.primary),
            if (_isEdit) ...[
              const SizedBox(height: 12),
              PBtn(label: '🗑️ Delete Customer', onTap: _confirmDelete,
                  full: true, color: C.red, outline: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {
    String? hint, TextInputType? type, int maxLines = 1,
    bool required = false, ValueChanged<String>? onChanged,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: TextSpan(
          text: label.toUpperCase(),
          style: GoogleFonts.syne(fontSize: 10, fontWeight: FontWeight.w700,
              color: C.textMuted, letterSpacing: 0.5),
          children: required ? [TextSpan(text: ' *',
              style: GoogleFonts.syne(color: C.accent))] : [],
        )),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl, keyboardType: type, maxLines: maxLines,
          onChanged: onChanged,
          style: GoogleFonts.syne(fontSize: 13, color: C.text),
          decoration: InputDecoration(hintText: hint),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
              : null,
        ),
        const SizedBox(height: 12),
      ]);
}
