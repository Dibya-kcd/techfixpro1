// ─────────────────────────────────────────────────────────────────────────────
//  screens/add_repair.dart  — New Job / Repair intake form
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
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

  // ── IMEI / barcode scan + autofill ───────────────────────────────────────
  // Opens the two-mode scanner (Barcode + OCR).
  // On return, fills ALL known fields automatically:
  //   rawValue → IMEI / Serial
  //   brand    → Brand (only if field is currently empty)
  //   model    → Model (only if field is currently empty)
  Future<void> _scanImei() async {
    final result = await Navigator.of(context).push<_ImeiScanResult>(
      MaterialPageRoute(builder: (_) => const _ImeiScannerScreen()),
    );
    if (result == null || !mounted) return;

    // Always fill IMEI/serial
    if (result.rawValue.isNotEmpty) {
      setState(() => _imei.text = result.rawValue);
    }

    // Autofill brand — only overwrite if field is empty
    if (result.brand.isNotEmpty && _brand.text.trim().isEmpty) {
      setState(() => _brand.text = result.brand);
    }

    // Autofill model — only overwrite if field is empty
    if (result.model.isNotEmpty && _model.text.trim().isEmpty) {
      setState(() => _model.text = result.model);
    }

    // Summary snackbar
    final filled = <String>[];
    if (result.rawValue.isNotEmpty) filled.add('IMEI');
    if (result.brand.isNotEmpty)    filled.add('Brand');
    if (result.model.isNotEmpty)    filled.add('Model');

    if (!mounted) return;
    if (filled.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Text('✅ ', style: TextStyle(fontSize: 16)),
          Expanded(child: Text(
            'Auto-filled: ${filled.join(', ')}',
            style: GoogleFonts.syne(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          )),
        ]),
        backgroundColor: C.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('📱 Scanned — please verify and fill brand & model',
            style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
        backgroundColor: C.bgElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
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
            // IMEI row: field + scan button side by side
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: _field('IMEI / Serial', _imei,
                  hint: 'Scan barcode or type *#06#',
                  type: TextInputType.number)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _scanImei,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.primary,
                      foregroundColor: C.bg,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code_scanner, size: 20),
                        const SizedBox(height: 2),
                        Text('Scan', style: GoogleFonts.syne(
                            fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ]),

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

// ═══════════════════════════════════════════════════════════════
//  SCAN RESULT — carries everything the scanner found
// ═══════════════════════════════════════════════════════════════
class _ImeiScanResult {
  final String rawValue; // IMEI / serial / barcode raw string
  final String brand;    // from API lookup OR OCR text parse
  final String model;    // from API lookup OR OCR text parse
  const _ImeiScanResult({
    required this.rawValue,
    this.brand = '',
    this.model = '',
  });
}

// ═══════════════════════════════════════════════════════════════
//  IMEI LOOKUP SERVICE  (free, no API key)
//  imeidb.com → GSMA TAC DB → returns brand + model
// ═══════════════════════════════════════════════════════════════
class _ImeiLookupService {
  static bool _isImei(String v) => RegExp(r'^\d{14,16}$').hasMatch(v);

  static Future<({String brand, String model})> lookup(String raw) async {
    if (!_isImei(raw)) return (brand: '', model: '');
    final tac = raw.substring(0, 8);

    // Try 1: imeidb.com
    try {
      final r = await http.get(
        Uri.parse('https://imeidb.com/api/v1/imei/$raw'),
        headers: {'Accept': 'application/json', 'User-Agent': 'TechFixPro/3.0'},
      ).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final b = (d['brandName'] ?? d['brand'] ?? '') as String;
        final m = (d['modelName'] ?? d['model'] ?? '') as String;
        if (b.isNotEmpty || m.isNotEmpty) return (brand: b, model: m);
      }
    } catch (_) {}

    // Try 2: GSMA TAC DB
    try {
      final r = await http.get(
        Uri.parse('https://tacdb.gsma.com/api/v1/tac/$tac/info'),
        headers: {'Accept': 'application/json', 'User-Agent': 'TechFixPro/3.0'},
      ).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final b = (d['manufacturer'] ?? '') as String;
        final m = (d['modelName'] ?? d['marketingName'] ?? '') as String;
        if (b.isNotEmpty || m.isNotEmpty) return (brand: b, model: m);
      }
    } catch (_) {}

    return (brand: '', model: '');
  }
}

// ═══════════════════════════════════════════════════════════════
//  OCR TEXT PARSER
//  Extracts brand, model, and IMEI from raw OCR text lines.
//  Works entirely offline — pure string matching.
// ═══════════════════════════════════════════════════════════════
class _OcrParser {
  // Known phone brands — matched case-insensitively anywhere in a line
  static const _brands = [
    'Samsung', 'Apple', 'iPhone', 'OnePlus', 'Xiaomi', 'Redmi', 'POCO',
    'Realme', 'Oppo', 'Vivo', 'iQOO', 'Motorola', 'Nokia', 'Sony',
    'LG', 'Google', 'Pixel', 'Huawei', 'Honor', 'Asus', 'Lenovo',
    'Tecno', 'Infinix', 'itel', 'Micromax', 'Lava', 'Karbonn',
  ];

  // Model prefix patterns — e.g. SM-A, A54, 13 Pro, Note 20
  static final _modelPrefixes = RegExp(
    r'\b(SM-[A-Z]\d+|[A-Z]\d{2,3}|Note\s*\d+|Find\s*[A-Z]\d+|'
    r'Nord\s*[A-Z]?\d+|GT\s*\d+|\d{1,2}\s*(Pro|Ultra|Plus|Max)|'
    r'Pixel\s*\d+|iPhone\s*\d+|Galaxy\s*[A-Z]?\d+)\b',
    caseSensitive: false,
  );

  static final _imeiPattern = RegExp(r'\b\d{14,16}\b');
  static final _imeiLabel   = RegExp(r'IMEI\s*[:\-]?\s*(\d{14,16})', caseSensitive: false);

  static ({
    String imei,
    String brand,
    String model,
    List<String> allLines,
  }) parse(List<String> rawLines) {
    final lines = rawLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    String imei = '', brand = '', model = '';

    for (final line in lines) {
      // IMEI — prefer label match (IMEI: 123456789012345)
      if (imei.isEmpty) {
        final lm = _imeiLabel.firstMatch(line);
        if (lm != null) {
          imei = lm.group(1)!;
        } else {
          final im = _imeiPattern.firstMatch(line);
          if (im != null) imei = im.group(0)!;
        }
      }

      // Brand
      if (brand.isEmpty) {
        for (final b in _brands) {
          if (line.toLowerCase().contains(b.toLowerCase())) {
            brand = b == 'iPhone' ? 'Apple' : b;
            break;
          }
        }
      }

      // Model
      if (model.isEmpty) {
        final mm = _modelPrefixes.firstMatch(line);
        if (mm != null) model = mm.group(0)!.trim();
      }
    }

    return (imei: imei, brand: brand, model: model, allLines: lines);
  }
}

// ═══════════════════════════════════════════════════════════════
//  SCANNER SCREEN
//
//  Two modes:
//    • Barcode — auto-detects on every frame (mobile + web)
//    • Read Text — OCR via ML Kit on mobile, manual on web
//      (google_mlkit_text_recognition does not support Flutter Web)
//
//  pubspec.yaml — add ONE line:
//    google_mlkit_text_recognition: ^0.13.1
//
//  Autofill on return:
//    _ImeiScanResult.rawValue  → IMEI / Serial field
//    _ImeiScanResult.brand     → Brand (if empty)
//    _ImeiScanResult.model     → Model (if empty)
// ═══════════════════════════════════════════════════════════════
enum _ScanMode { barcode, ocr }

class _ImeiScannerScreen extends StatefulWidget {
  const _ImeiScannerScreen();
  @override
  State<_ImeiScannerScreen> createState() => _ImeiScannerScreenState();
}

class _ImeiScannerScreenState extends State<_ImeiScannerScreen>
    with WidgetsBindingObserver {

  // ── camera ────────────────────────────────────────────────────
  late final MobileScannerController _ctrl;
  bool _torchOn = false;

  // ── state ─────────────────────────────────────────────────────
  _ScanMode _mode     = _ScanMode.barcode;
  bool _processing    = false;
  bool _barcodeActive = true; // false after first hit
  String? _lastBarcode;

  // ── OCR ───────────────────────────────────────────────────────
  // ML Kit is only available on Android/iOS — guarded by kIsWeb
  dynamic _recognizer; // TextRecognizer? — late-bound to avoid web compile error
  bool _ocrDone         = false;
  List<String> _ocrAllLines    = [];
  String _ocrImei       = '';
  String _ocrBrand      = '';
  String _ocrModel      = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing:         CameraFacing.back,
      torchEnabled:   false,
      returnImage:    false, // frame bytes not needed — OCR uses image_picker
      formats: const [
        BarcodeFormat.code128, BarcodeFormat.code39,
        BarcodeFormat.ean13,   BarcodeFormat.ean8,
        BarcodeFormat.qrCode,  BarcodeFormat.dataMatrix,
        BarcodeFormat.upcA,    BarcodeFormat.upcE,
      ],
    );
    // Only initialise ML Kit on mobile — web would throw at import time
    // We use a try/catch + dynamic type to stay web-safe at runtime
    if (!kIsWeb) {
      _initRecognizer();
    }
  }

  void _initRecognizer() {
    // Wrapped so web build never executes this code path
    try {
      _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    try { (_recognizer as dynamic)?.close(); } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _ctrl.stop();
    } else if (state == AppLifecycleState.resumed && !_processing) {
      _ctrl.start();
    }
  }

  // ── Barcode auto-detect ────────────────────────────────────────
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_mode != _ScanMode.barcode || !_barcodeActive || _processing) return;
    final hits = capture.barcodes
        .where((b) => b.rawValue?.isNotEmpty == true)
        .toList();
    if (hits.isEmpty) return;

    final raw = hits.first.rawValue!;
    if (raw == _lastBarcode) return;
    _lastBarcode = raw;

    HapticFeedback.mediumImpact();
    setState(() { _barcodeActive = false; _processing = true; });
    await _ctrl.stop();

    final info = await _ImeiLookupService.lookup(raw);

    if (mounted) {
      Navigator.of(context).pop(_ImeiScanResult(
        rawValue: raw,
        brand:    info.brand,
        model:    info.model,
      ));
    }
  }

  // ── OCR capture (mobile only) ──────────────────────────────────
  // ── OCR CAPTURE ───────────────────────────────────────────────
  // Uses image_picker to take a photo (camera on mobile, file-pick on web).
  // ML Kit runs on Android/iOS; on web we skip OCR and go straight to
  // the results panel showing whatever the picker returned — user can
  // fall through to manual entry.
  Future<void> _captureOcr() async {
    if (_processing) return;

    // On web, ML Kit is unavailable — go straight to manual entry
    if (kIsWeb) {
      _manualEntry();
      return;
    }

    // Pause the barcode scanner while the camera picker is open
    await _ctrl.stop();

    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (_) {}

    // Restart scanner whether or not the user picked a photo
    if (!_processing) _ctrl.start();

    if (photo == null || !mounted) return;

    setState(() { _processing = true; _ocrDone = false; });

    try {
      final inputImage = InputImage.fromFilePath(photo.path);
      final result     = await (_recognizer as TextRecognizer).processImage(inputImage);

      // Delete temp file quietly
      try { File(photo.path).delete(); } catch (_) {}

      final rawLines = result.blocks
          .expand((b) => b.lines)
          .map((l) => l.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final parsed = _OcrParser.parse(rawLines);

      if (!mounted) return;

      if (parsed.allLines.isEmpty) {
        setState(() => _processing = false);
        _ctrl.start();
        _showSnack('No text found — try better lighting or move closer', isError: true);
        return;
      }

      setState(() {
        _processing  = false;
        _ocrDone     = true;
        _ocrAllLines = parsed.allLines;
        _ocrImei     = parsed.imei;
        _ocrBrand    = parsed.brand;
        _ocrModel    = parsed.model;
      });

      // Auto-confirm when IMEI + at least one of brand/model found
      if (_ocrImei.isNotEmpty && (_ocrBrand.isNotEmpty || _ocrModel.isNotEmpty)) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) _confirmOcr();
      }

    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        _ctrl.start();
        _showSnack('OCR failed: $e', isError: true);
      }
    }
  }

  // ── Confirm OCR result and return to form ──────────────────────
  void _confirmOcr() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(_ImeiScanResult(
      rawValue: _ocrImei,
      brand:    _ocrBrand,
      model:    _ocrModel,
    ));
  }

  // ── User manually picks a different IMEI candidate ─────────────
  Future<void> _useImei(String imei) async {
    setState(() { _processing = true; });
    await _ctrl.stop();
    HapticFeedback.mediumImpact();
    final info = await _ImeiLookupService.lookup(imei);
    if (mounted) {
      Navigator.of(context).pop(_ImeiScanResult(
        rawValue: imei,
        brand:    _ocrBrand.isNotEmpty ? _ocrBrand : info.brand,
        model:    _ocrModel.isNotEmpty ? _ocrModel : info.model,
      ));
    }
  }

  // ── Switch mode ────────────────────────────────────────────────
  void _switchMode(_ScanMode m) {
    if (m == _mode) return;
    setState(() {
      _mode          = m;
      _barcodeActive = true;
      _ocrDone       = false;
      _ocrAllLines   = [];
      _ocrImei = _ocrBrand = _ocrModel = '';
    });
    if (!_processing) _ctrl.start();
  }

  // ── Manual entry fallback ─────────────────────────────────────
  void _manualEntry() {
    final ctrl = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Enter IMEI / Serial',
            style: GoogleFonts.syne(fontWeight: FontWeight.w800, color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Dial *#06# on the device to find the IMEI',
              style: GoogleFonts.syne(fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl, autofocus: true,
            keyboardType: TextInputType.number,
            style: GoogleFonts.syne(color: Colors.white),
            decoration: InputDecoration(
              hintText: '15-digit IMEI or serial number',
              hintStyle: GoogleFonts.syne(color: Colors.white38),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c),
              child: Text('Cancel', style: GoogleFonts.syne(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Confirm', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ).then((entered) async {
      if (entered == null || entered.isEmpty || !mounted) return;
      setState(() { _processing = true; _lastBarcode = entered; });
      await _ctrl.stop();
      final info = await _ImeiLookupService.lookup(entered);
      if (mounted) {
        Navigator.of(context).pop(_ImeiScanResult(
          rawValue: entered,
          brand:    info.brand,
          model:    info.model,
        ));
      }
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.syne(fontWeight: FontWeight.w700)),
      backgroundColor: isError ? Colors.red.shade800 : Colors.orange.shade800,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  // ── BUILD ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [

        // Camera
        MobileScanner(controller: _ctrl, onDetect: _onDetect),

        // Barcode overlay
        if (_mode == _ScanMode.barcode)
          CustomPaint(painter: _BarcodeOverlayPainter()),

        // OCR full-frame vignette
        if (_mode == _ScanMode.ocr && !_ocrDone)
          CustomPaint(painter: _OcrVignettePainter()),

        // ── TOP BAR ─────────────────────────────────────────────
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            _circleBtn(Icons.close, () => Navigator.pop(context)),
            const Spacer(),
            _ModePill(mode: _mode, onChanged: _switchMode),
            const Spacer(),
            _circleBtn(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              () async {
                await _ctrl.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              },
              bg: _torchOn ? Colors.amber.withValues(alpha: 0.75) : null,
            ),
          ]),
        )),

        // ── BARCODE HINT ─────────────────────────────────────────
        if (_mode == _ScanMode.barcode && !_processing)
          Positioned(
            top: h * 0.27, left: 0, right: 0,
            child: Center(child: _pill('Align barcode within the frame')),
          ),

        // ── OCR INSTRUCTIONS ─────────────────────────────────────
        if (_mode == _ScanMode.ocr && !_processing && !_ocrDone)
          Positioned(
            top: h * 0.13, left: 20, right: 20,
            child: Center(child: _pill(
              kIsWeb
                ? 'OCR not available on web — tap Capture to enter manually'
                : 'Aim at device label, retail box or Settings screen\nthen tap Capture',
            )),
          ),

        // ── OCR CAPTURE BUTTON ───────────────────────────────────
        if (_mode == _ScanMode.ocr && !_processing && !_ocrDone)
          Positioned(
            bottom: bottom + 44, left: 0, right: 0,
            child: Center(child: GestureDetector(
              onTap: _captureOcr,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 32),
              ),
            )),
          ),

        // ── OCR RESULTS PANEL ────────────────────────────────────
        if (_mode == _ScanMode.ocr && _ocrDone && !_processing)
          _OcrResultPanel(
            imei:     _ocrImei,
            brand:    _ocrBrand,
            model:    _ocrModel,
            allLines: _ocrAllLines,
            onConfirm:    _confirmOcr,
            onUseImei:    _useImei,
            onRetry:      () => setState(() {
              _ocrDone = false;
              _ocrAllLines = [];
              _ocrImei = _ocrBrand = _ocrModel = '';
            }),
          ),

        // ── PROCESSING SPINNER ───────────────────────────────────
        if (_processing)
          Container(
            color: Colors.black.withValues(alpha: 0.78),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                _mode == _ScanMode.ocr ? 'Reading text on device…' : 'Looking up device…',
                style: GoogleFonts.syne(fontSize: 15,
                    fontWeight: FontWeight.w700, color: Colors.white)),
            ])),
          ),

        // ── BARCODE BOTTOM ACTIONS ───────────────────────────────
        if (_mode == _ScanMode.barcode && !_processing)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 24),
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
              )),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text("Can't scan? Switch to Read Text ↑ or enter manually",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(fontSize: 11, color: Colors.white54)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _manualEntry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Text('⌨️  Type IMEI / Serial',
                        style: GoogleFonts.syne(
                            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback fn, {Color? bg}) =>
      GestureDetector(
        onTap: fn,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: bg ?? Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(99)),
    child: Text(text, textAlign: TextAlign.center,
        style: GoogleFonts.syne(fontSize: 12, color: Colors.white70)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  MODE TOGGLE PILL
// ─────────────────────────────────────────────────────────────────────────────
class _ModePill extends StatelessWidget {
  final _ScanMode mode;
  final ValueChanged<_ScanMode> onChanged;
  const _ModePill({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _tab('Barcode',    Icons.qr_code_scanner, _ScanMode.barcode),
      _tab('Read Text',  Icons.text_fields,      _ScanMode.ocr),
    ]),
  );

  Widget _tab(String label, IconData icon, _ScanMode m) {
    final sel = mode == m;
    return GestureDetector(
      onTap: () => onChanged(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF6C63FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.syne(
              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  OCR RESULT PANEL
//  Shows parsed IMEI, brand, model at the top (auto-confirmed if complete).
//  Falls through to let user pick alternative IMEI or line.
// ─────────────────────────────────────────────────────────────────────────────
class _OcrResultPanel extends StatelessWidget {
  final String imei, brand, model;
  final List<String> allLines;
  final VoidCallback onConfirm;
  final Future<void> Function(String) onUseImei;
  final VoidCallback onRetry;

  const _OcrResultPanel({
    required this.imei,  required this.brand, required this.model,
    required this.allLines, required this.onConfirm,
    required this.onUseImei, required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final hasResult = imei.isNotEmpty || brand.isNotEmpty || model.isNotEmpty;

    // Other IMEI candidates (14-16 digit strings not equal to primary imei)
    final altImeis = allLines
        .where((l) => RegExp(r'^\d{14,16}$').hasMatch(l) && l != imei)
        .toList();

    // Text lines (non-IMEI, long enough to be useful)
    final infoLines = allLines
        .where((l) => !RegExp(r'^\d{14,16}$').hasMatch(l) && l.length >= 3)
        .take(16)
        .toList();

    return Positioned.fill(
      top: MediaQuery.of(context).padding.top + 60,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.97),
                     Colors.black.withValues(alpha: 0.65)],
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Primary result card ───────────────────────────────
            if (hasResult) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF6C63FF), width: 1.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 16),
                    const SizedBox(width: 6),
                    Text('Device Detected', style: GoogleFonts.syne(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: const Color(0xFF6C63FF), letterSpacing: 0.5)),
                  ]),
                  const SizedBox(height: 10),
                  if (imei.isNotEmpty)
                    _row('IMEI / Serial', imei, mono: true),
                  if (brand.isNotEmpty)
                    _row('Brand', brand),
                  if (model.isNotEmpty)
                    _row('Model', model),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity, height: 46,
                    child: ElevatedButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                      label: Text('Use These Details',
                          style: GoogleFonts.syne(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── Alternate IMEI candidates ─────────────────────────
            if (altImeis.isNotEmpty) ...[
              _sectionLabel('Other IMEI Numbers Found'),
              const SizedBox(height: 8),
              ...altImeis.map((im) => GestureDetector(
                onTap: () => onUseImei(im),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.smartphone, color: Colors.white54, size: 16),
                    const SizedBox(width: 10),
                    Expanded(child: Text(im, style: GoogleFonts.syne(
                        fontSize: 14, color: Colors.white70, letterSpacing: 1.2))),
                    Text('USE', style: GoogleFonts.syne(
                        fontSize: 10, fontWeight: FontWeight.w800,
                        color: const Color(0xFF6C63FF))),
                  ]),
                ),
              )),
              const SizedBox(height: 12),
            ],

            // ── All text lines ────────────────────────────────────
            if (infoLines.isNotEmpty) ...[
              _sectionLabel('All Text Recognised'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: infoLines.map((line) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Text(line, style: GoogleFonts.syne(
                      fontSize: 11, color: Colors.white60)),
                )).toList(),
              ),
              const SizedBox(height: 20),
            ],

            // ── Retry ─────────────────────────────────────────────
            Center(child: GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text('🔄  Scan Again',
                    style: GoogleFonts.syne(fontSize: 13,
                        fontWeight: FontWeight.w700, color: Colors.white70)),
              ),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: GoogleFonts.syne(
          fontSize: 11, color: Colors.white54))),
      Expanded(child: Text(value, style: mono
          ? const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white,
                            letterSpacing: 1.5)
          : GoogleFonts.syne(fontSize: 13, fontWeight: FontWeight.w700,
                              color: Colors.white))),
    ]),
  );

  Widget _sectionLabel(String t) => Text(t,
      style: GoogleFonts.syne(fontSize: 10, fontWeight: FontWeight.w700,
          color: Colors.white38, letterSpacing: 0.5));
}

// ─────────────────────────────────────────────────────────────────────────────
//  OVERLAY PAINTERS
// ─────────────────────────────────────────────────────────────────────────────
class _BarcodeOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sw = size.width * 0.82;
    final sh = sw * 0.35;
    final l = (size.width - sw) / 2, t = size.height * 0.36;
    final r = l + sw, b = t + sh;
    final rect = Rect.fromLTRB(l, t, r, b);

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)))
        ..fillType = PathFillType.evenOdd,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    const cl = 22.0;
    final p = Paint()..color = const Color(0xFF00C2FF)
        ..strokeWidth = 3.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;

    void br(Offset a, Offset c, Offset d) {
      canvas.drawLine(a, c, p); canvas.drawLine(c, d, p);
    }
    br(Offset(l, t+cl), Offset(l,t), Offset(l+cl,t));
    br(Offset(r-cl,t),  Offset(r,t), Offset(r,t+cl));
    br(Offset(l,b-cl),  Offset(l,b), Offset(l+cl,b));
    br(Offset(r-cl,b),  Offset(r,b), Offset(r,b-cl));

    canvas.drawLine(Offset(l+6, t+sh/2), Offset(r-6, t+sh/2),
        Paint()..color = const Color(0xFF00C2FF).withValues(alpha: 0.7)
               ..strokeWidth = 2);
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

class _OcrVignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = RadialGradient(
        center: Alignment.center, radius: 0.85,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.4)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    const m = 28.0, cl = 30.0;
    final p = Paint()..color = Colors.white.withValues(alpha: 0.65)
        ..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    void br(Offset a, Offset c, Offset d) {
      canvas.drawLine(a, c, p); canvas.drawLine(c, d, p);
    }
    br(Offset(m,m+cl),                       Offset(m,m),                       Offset(m+cl,m));
    br(Offset(size.width-m-cl,m),             Offset(size.width-m,m),            Offset(size.width-m,m+cl));
    br(Offset(m,size.height-m-cl),            Offset(m,size.height-m),           Offset(m+cl,size.height-m));
    br(Offset(size.width-m-cl,size.height-m), Offset(size.width-m,size.height-m),Offset(size.width-m,size.height-m-cl));
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}
