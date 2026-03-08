// lib/data/notification_service.dart
//
// Single source of truth for all outbound customer notifications.
// Imported by:
//   • lib/screens/settings.dart  — save/load config, Test Connection
//   • lib/screens/notify.dart    — actual send on the Notify sheet
//
// Firebase layout (all under shops/{shopId}/):
//   whatsappSettings/
//     apiKey        String  — Meta Bearer token
//     phoneId       String  — WhatsApp Phone Number ID from Meta console
//     autoPickup    bool    — send when job → Ready for Pickup
//     autoUpdate    bool    — send on every status change
//     autoReminder  bool    — 3-day reminder
//     tplPickup     String  — message template body
//     tplUpdate     String
//     tplReminder   String
//
//   smsSettings/
//     provider   String  — 'MSG91' | 'Twilio' | 'TextLocal' | 'Fast2SMS'
//     apiKey     String
//     senderId   String  — e.g. 'TECHFX'
//     onPickup   bool
//     onUpdate   bool

import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

// ─── Config models ────────────────────────────────────────────────────────────

class WhatsAppConfig {
  final String apiKey;
  final String phoneId;
  final bool   autoPickup;
  final bool   autoUpdate;
  final bool   autoReminder;
  final String tplPickup;
  final String tplUpdate;
  final String tplReminder;

  static const _defPickup =
      'Hi {name}! \u{1F44B} Your {device} ({job_num}) is ready for collection.\n'
      'Amount due: \u20B9{amount}. \u{1F4CD} {shop_address}';
  static const _defUpdate =
      'Hi {name}! Update on your {device}: Status changed to *{status}*. '
      'Questions? Call us at {shop_phone}.';
  static const _defReminder =
      'Hi {name}, friendly reminder: your {device} has been ready for {days} day(s). '
      'Please collect at your earliest convenience. \u{1F4CD} {shop_address}';

  const WhatsAppConfig({
    this.apiKey       = '',
    this.phoneId      = '',
    this.autoPickup   = true,
    this.autoUpdate   = false,
    this.autoReminder = true,
    this.tplPickup    = _defPickup,
    this.tplUpdate    = _defUpdate,
    this.tplReminder  = _defReminder,
  });

  bool get isConfigured => apiKey.isNotEmpty && phoneId.isNotEmpty;

  factory WhatsAppConfig.fromMap(Map<String, dynamic> d) => WhatsAppConfig(
    apiKey:       (d['apiKey']       as String?) ?? '',
    phoneId:      (d['phoneId']      as String?) ?? '',
    autoPickup:   (d['autoPickup']   as bool?)   ?? true,
    autoUpdate:   (d['autoUpdate']   as bool?)   ?? false,
    autoReminder: (d['autoReminder'] as bool?)   ?? true,
    tplPickup:    (d['tplPickup']    as String?) ?? _defPickup,
    tplUpdate:    (d['tplUpdate']    as String?) ?? _defUpdate,
    tplReminder:  (d['tplReminder']  as String?) ?? _defReminder,
  );

  Map<String, dynamic> toMap() => {
    'apiKey': apiKey,       'phoneId': phoneId,
    'autoPickup': autoPickup, 'autoUpdate': autoUpdate,
    'autoReminder': autoReminder,
    'tplPickup': tplPickup, 'tplUpdate': tplUpdate, 'tplReminder': tplReminder,
  };

  WhatsAppConfig copyWith({
    String? apiKey, String? phoneId,
    bool?   autoPickup, bool? autoUpdate, bool? autoReminder,
    String? tplPickup,  String? tplUpdate, String? tplReminder,
  }) => WhatsAppConfig(
    apiKey:       apiKey       ?? this.apiKey,
    phoneId:      phoneId      ?? this.phoneId,
    autoPickup:   autoPickup   ?? this.autoPickup,
    autoUpdate:   autoUpdate   ?? this.autoUpdate,
    autoReminder: autoReminder ?? this.autoReminder,
    tplPickup:    tplPickup    ?? this.tplPickup,
    tplUpdate:    tplUpdate    ?? this.tplUpdate,
    tplReminder:  tplReminder  ?? this.tplReminder,
  );
}

class SmsConfig {
  final String provider; // 'MSG91' | 'Twilio' | 'TextLocal' | 'Fast2SMS'
  final String apiKey;
  final String senderId;
  final bool   onPickup;
  final bool   onUpdate;

  const SmsConfig({
    this.provider = 'MSG91',
    this.apiKey   = '',
    this.senderId = 'TECHFX',
    this.onPickup = true,
    this.onUpdate = false,
  });

  bool get isConfigured => apiKey.isNotEmpty;

  factory SmsConfig.fromMap(Map<String, dynamic> d) => SmsConfig(
    provider: (d['provider'] as String?) ?? 'MSG91',
    apiKey:   (d['apiKey']   as String?) ?? '',
    senderId: (d['senderId'] as String?) ?? 'TECHFX',
    onPickup: (d['onPickup'] as bool?)   ?? true,
    onUpdate: (d['onUpdate'] as bool?)   ?? false,
  );

  Map<String, dynamic> toMap() => {
    'provider': provider, 'apiKey': apiKey, 'senderId': senderId,
    'onPickup': onPickup, 'onUpdate': onUpdate,
  };

  SmsConfig copyWith({
    String? provider, String? apiKey, String? senderId,
    bool? onPickup, bool? onUpdate,
  }) => SmsConfig(
    provider: provider ?? this.provider,
    apiKey:   apiKey   ?? this.apiKey,
    senderId: senderId ?? this.senderId,
    onPickup: onPickup ?? this.onPickup,
    onUpdate: onUpdate ?? this.onUpdate,
  );
}

// ─── Result ───────────────────────────────────────────────────────────────────

class NotifResult {
  final bool   ok;
  final String message;
  const NotifResult.success(this.message) : ok = true;
  const NotifResult.failure(this.message) : ok = false;
}

// ─── Service ──────────────────────────────────────────────────────────────────

class NotificationService {
  NotificationService._(); // static-only — never instantiate

  // ── Firebase load / save ──────────────────────────────────────────────────

  static Future<WhatsAppConfig> loadWhatsApp(String shopId) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('shops/$shopId/whatsappSettings').get();
      if (snap.exists && snap.value is Map) {
        return WhatsAppConfig.fromMap(
            Map<String, dynamic>.from(snap.value as Map));
      }
    } catch (_) {}
    return const WhatsAppConfig();
  }

  static Future<void> saveWhatsApp(String shopId, WhatsAppConfig cfg) =>
      FirebaseDatabase.instance
          .ref('shops/$shopId/whatsappSettings')
          .update(cfg.toMap());

  static Future<SmsConfig> loadSms(String shopId) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('shops/$shopId/smsSettings').get();
      if (snap.exists && snap.value is Map) {
        return SmsConfig.fromMap(
            Map<String, dynamic>.from(snap.value as Map));
      }
    } catch (_) {}
    return const SmsConfig();
  }

  static Future<void> saveSms(String shopId, SmsConfig cfg) =>
      FirebaseDatabase.instance
          .ref('shops/$shopId/smsSettings')
          .update(cfg.toMap());

  // ── Template interpolation ────────────────────────────────────────────────

  static String fill(String tpl, {
    String name        = '',
    String device      = '',
    String jobNum      = '',
    String amount      = '',
    String status      = '',
    String shopAddress = '',
    String shopPhone   = '',
    String days        = '3',
  }) => tpl
      .replaceAll('{name}',         name)
      .replaceAll('{device}',       device)
      .replaceAll('{job_num}',      jobNum)
      .replaceAll('{amount}',       amount)
      .replaceAll('{status}',       status)
      .replaceAll('{shop_address}', shopAddress)
      .replaceAll('{shop_phone}',   shopPhone)
      .replaceAll('{days}',         days);

  // ── Phone normalisation ───────────────────────────────────────────────────

  /// Strips formatting. Prepends 91 if 10-digit Indian number.
  static String _e164(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length == 10) return '91$digits';
    return digits;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WhatsApp Cloud API  (Meta graph.facebook.com/v19.0)
  // Docs: developers.facebook.com/docs/whatsapp/cloud-api/messages
  // ─────────────────────────────────────────────────────────────────────────

  static Future<NotifResult> sendWhatsApp({
    required WhatsAppConfig cfg,
    required String toPhone,
    required String body,
  }) async {
    if (!cfg.isConfigured) {
      return const NotifResult.failure(
          'WhatsApp not set up. Add API Key + Phone Number ID in '
          'Settings \u2192 WhatsApp Business.');
    }

    final phone = _e164(toPhone);
    final url = Uri.parse(
        'https://graph.facebook.com/v19.0/${cfg.phoneId}/messages');

    try {
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${cfg.apiKey}',
          'Content-Type':  'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'recipient_type':    'individual',
          'to':                phone,
          'type':              'text',
          'text': {'preview_url': false, 'body': body},
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data  = jsonDecode(res.body) as Map<String, dynamic>;
        final msgId = (data['messages'] as List?)?.firstOrNull?['id'] as String? ?? '';
        return NotifResult.success('\u{1F4AC} WhatsApp sent (id: $msgId)');
      }

      final err = _tryJson(res.body);
      final msg = err?['error']?['message'] as String? ?? res.body;
      return NotifResult.failure('Meta API ${res.statusCode}: $msg');
    } on Exception catch (e) {
      return NotifResult.failure('Network error: $e');
    }
  }

  /// Sends a quick test message to the shop's own number.
  static Future<NotifResult> testWhatsApp(
      WhatsAppConfig cfg, String shopPhone) =>
      sendWhatsApp(
        cfg:     cfg,
        toPhone: shopPhone.isNotEmpty ? shopPhone : cfg.phoneId,
        body:    '\u2705 TechFix Pro \u2014 WhatsApp connection test successful! '
                 'You are all set to send customer notifications.',
      );

  // ─────────────────────────────────────────────────────────────────────────
  // SMS — dispatches to chosen provider
  // ─────────────────────────────────────────────────────────────────────────

  static Future<NotifResult> sendSms({
    required SmsConfig cfg,
    required String toPhone,
    required String body,
  }) async {
    if (!cfg.isConfigured) {
      return const NotifResult.failure(
          'SMS not set up. Add API Key in Settings \u2192 SMS Gateway.');
    }
    final phone = _e164(toPhone);
    switch (cfg.provider) {
      case 'MSG91':     return _msg91(cfg, phone, body);
      case 'Twilio':    return _twilio(cfg, phone, body);
      case 'TextLocal': return _textLocal(cfg, phone, body);
      case 'Fast2SMS':  return _fast2sms(cfg, phone, body);
      default: return NotifResult.failure(
          'Unknown SMS provider: ${cfg.provider}');
    }
  }

  static Future<NotifResult> testSms(SmsConfig cfg, String shopPhone) =>
      sendSms(
        cfg:     cfg,
        toPhone: shopPhone.isNotEmpty ? shopPhone : '9999999999',
        body:    '\u2705 TechFix Pro \u2014 SMS gateway test successful!',
      );

  // ── MSG91 ─────────────────────────────────────────────────────────────────
  // Docs: docs.msg91.com — transactional route 4
  static Future<NotifResult> _msg91(
      SmsConfig cfg, String phone, String body) async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://api.msg91.com/api/sendhttp.php'
          '?authkey=${Uri.encodeComponent(cfg.apiKey)}'
          '&mobiles=$phone'
          '&message=${Uri.encodeComponent(body)}'
          '&sender=${Uri.encodeComponent(cfg.senderId)}'
          '&route=4'   // 4 = transactional
          '&country=0' // auto-detect
        ),
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 15));

      // MSG91 returns a numeric request ID on success, error string otherwise
      final b = res.body.trim();
      if (res.statusCode == 200 && RegExp(r'^\d+$').hasMatch(b)) {
        return NotifResult.success('\u{1F4F1} SMS sent via MSG91 (req: $b)');
      }
      return NotifResult.failure('MSG91: $b');
    } on Exception catch (e) {
      return NotifResult.failure('Network error: $e');
    }
  }

  // ── Twilio ────────────────────────────────────────────────────────────────
  // apiKey format: "AccountSID:AuthToken"
  static Future<NotifResult> _twilio(
      SmsConfig cfg, String phone, String body) async {
    final parts = cfg.apiKey.split(':');
    if (parts.length != 2) {
      return const NotifResult.failure(
          'Twilio API Key must be "AccountSID:AuthToken" (colon-separated)');
    }
    final sid = parts[0], token = parts[1];
    try {
      final res = await http.post(
        Uri.parse(
            'https://api.twilio.com/2010-04-01/Accounts/$sid/Messages.json'),
        headers: {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$sid:$token'))}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'To':   '+$phone',
          'From': cfg.senderId.startsWith('+')
              ? cfg.senderId : '+${cfg.senderId}',
          'Body': body,
        },
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return NotifResult.success(
            '\u{1F4F1} SMS sent via Twilio (sid: ${data['sid']})');
      }
      final err = _tryJson(res.body);
      return NotifResult.failure(
          'Twilio ${res.statusCode}: ${err?['message'] ?? res.body}');
    } on Exception catch (e) {
      return NotifResult.failure('Network error: $e');
    }
  }

  // ── TextLocal ─────────────────────────────────────────────────────────────
  static Future<NotifResult> _textLocal(
      SmsConfig cfg, String phone, String body) async {
    try {
      final res = await http.post(
        Uri.parse('https://api.textlocal.in/send/'),
        body: {
          'apikey':  cfg.apiKey,
          'numbers': phone,
          'message': body,
          'sender':  cfg.senderId,
        },
      ).timeout(const Duration(seconds: 15));

      final data = _tryJson(res.body);
      if (data?['status'] == 'success') {
        return NotifResult.success('\u{1F4F1} SMS sent via TextLocal');
      }
      return NotifResult.failure(
          'TextLocal: ${data?['errors']?.toString() ?? res.body}');
    } on Exception catch (e) {
      return NotifResult.failure('Network error: $e');
    }
  }

  // ── Fast2SMS ──────────────────────────────────────────────────────────────
  static Future<NotifResult> _fast2sms(
      SmsConfig cfg, String phone, String body) async {
    try {
      final res = await http.post(
        Uri.parse('https://www.fast2sms.com/dev/bulkV2'),
        headers: {
          'authorization': cfg.apiKey,
          'Content-Type':  'application/json',
        },
        body: jsonEncode({
          'route':     'q',
          'message':   body,
          'language':  'english',
          'flash':     0,
          'numbers':   phone,
          'sender_id': cfg.senderId,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = _tryJson(res.body);
      if (data?['return'] == true) {
        return NotifResult.success('\u{1F4F1} SMS sent via Fast2SMS');
      }
      return NotifResult.failure(
          'Fast2SMS: ${data?['message']?.toString() ?? res.body}');
    } on Exception catch (e) {
      return NotifResult.failure('Network error: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Map<String, dynamic>? _tryJson(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; }
    catch (_) { return null; }
  }
}
