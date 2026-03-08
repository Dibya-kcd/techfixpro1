import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/m.dart';
import '../data/providers.dart';
import '../theme/t.dart';
import '../widgets/w.dart';

class NotifySheet extends ConsumerStatefulWidget {
  final Job job;
  const NotifySheet({super.key, required this.job});

  @override
  ConsumerState<NotifySheet> createState() => _NotifySheetState();
}

class _NotifySheetState extends ConsumerState<NotifySheet> {
  String _channel = 'WhatsApp';
  late TextEditingController _msgCtrl;

  @override
  void initState() {
    super.initState();
    _msgCtrl = TextEditingController(text: _buildMessage());

    assert(() {
      debugPrint(
        '[NotifySheet] init job=${widget.job.jobId} status=${widget.job.status} total=${widget.job.totalAmount}',
      );
      return true;
    }());
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  String _buildMessage() {
    final j = widget.job;
    final settings = ref.read(settingsProvider);
    final shopName = settings.shopName.isEmpty ? 'our shop' : settings.shopName;
    final phone    = settings.phone.isEmpty    ? '' : '\n📞 ${settings.phone}';
    return 'Hi ${j.customerName}! 👋\n\n'
        'Your ${j.brand} ${j.model} (${j.jobNumber}) is ready for pickup at $shopName.\n\n'
        '📋 Repair: ${j.problem}\n'
        '💰 Total: ${fmtMoney(j.totalAmount)}\n\n'
        'Please bring this message and a valid ID.$phone\n\n'
        'Thank you! 🔧';
  }

  String get _recipient {
    if (_channel == 'Email') return widget.job.customerPhone; // placeholder
    return widget.job.customerPhone;
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    assert(() {
      debugPrint(
        '[NotifySheet] build channel=$_channel recipient=$_recipient job=${j.jobId}',
      );
      return true;
    }());
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: C.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(99)),
            )),
            const SizedBox(height: 14),

            // Header
            Row(children: [
              const Text('📣', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Notify Customer', style: GoogleFonts.syne(
                    fontWeight: FontWeight.w800, fontSize: 18, color: C.white)),
                Text(j.customerName, style: GoogleFonts.syne(
                    fontSize: 13, color: C.textMuted)),
              ])),
              if (j.notificationSent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: C.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: C.green.withValues(alpha: 0.4)),
                  ),
                  child: Text('Previously Sent', style: GoogleFonts.syne(
                      fontSize: 11, fontWeight: FontWeight.w700, color: C.green)),
                ),
            ]),
            const SizedBox(height: 16),

            // Channel selector
            Text('SEND VIA', style: GoogleFonts.syne(
                fontSize: 10, fontWeight: FontWeight.w700, color: C.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Row(children: [
              _channelChip('💬', 'WhatsApp', C.green),
              const SizedBox(width: 8),
              _channelChip('📱', 'SMS', C.primary),
              const SizedBox(width: 8),
              _channelChip('📧', 'Email', C.accent),
            ]),
            const SizedBox(height: 16),

            // Recipient
            SCard(
              child: Row(children: [
                const Icon(Icons.person_outline, color: C.textMuted, size: 18),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('To', style: GoogleFonts.syne(fontSize: 11, color: C.textMuted)),
                  Text(_recipient, style: GoogleFonts.syne(
                      fontSize: 14, fontWeight: FontWeight.w700, color: C.white)),
                ]),
              ]),
            ),
            const SizedBox(height: 12),

            // Amount card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: C.green.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Amount to Collect', style: GoogleFonts.syne(
                    fontSize: 13, color: C.textMuted)),
                Text(fmtMoney(j.totalAmount), style: GoogleFonts.syne(
                    fontSize: 20, fontWeight: FontWeight.w800, color: C.green)),
              ]),
            ),
            const SizedBox(height: 16),

            // Message editor
            Text('MESSAGE PREVIEW', style: GoogleFonts.syne(
                fontSize: 10, fontWeight: FontWeight.w700, color: C.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _msgCtrl,
              maxLines: 10,
              style: GoogleFonts.syne(fontSize: 12, color: C.text, height: 1.6),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 16),

            // Actions
            Row(children: [
              Expanded(child: PBtn(
                label: 'Cancel',
                onTap: () => Navigator.of(context).pop(),
                outline: true,
                color: C.textMuted,
                full: true,
              )),
              const SizedBox(width: 12),
              Expanded(child: PBtn(
                label: '${_channelIcon()} Send via $_channel',
                onTap: _send,
                color: _channelColor(),
                full: true,
              )),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _channelChip(String icon, String label, Color color) {
    final sel = _channel == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _channel = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? color.withValues(alpha: 0.15) : C.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? color : C.border, width: sel ? 2 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 3),
            Text(label, style: GoogleFonts.syne(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: sel ? color : C.textMuted)),
          ]),
        ),
      ),
    );
  }

  String _channelIcon() {
    return {'WhatsApp': '💬', 'SMS': '📱', 'Email': '📧'}[_channel] ?? '📣';
  }

  Color _channelColor() {
    return {'WhatsApp': C.green, 'SMS': C.primary, 'Email': C.accent}[_channel] ?? C.primary;
  }

  void _send() {
    // markNotified is now async (writes to Firebase) but UI doesn't need to wait
    ref.read(jobsProvider.notifier).markNotified(widget.job.jobId, _channel);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_channelIcon()} Message sent via $_channel!',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
      backgroundColor: _channelColor(),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}
