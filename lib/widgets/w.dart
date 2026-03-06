import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/t.dart';

// ── Money formatter ───────────────────────────────────────────
String fmtMoney(double n) => '₹${n.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

// ── Pill badge ────────────────────────────────────────────────
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool small;
  const Pill(this.text, {super.key, this.color = C.primary, this.small = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 8 : 12, vertical: small ? 2 : 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(text, style: GoogleFonts.syne(
        fontSize: small ? 10 : 11, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 0.3)),
  );
}

// ── Surface Card ──────────────────────────────────────────────
class SCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? glowColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const SCard({super.key, required this.child, this.padding, this.margin,
      this.glowColor, this.borderColor, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin ?? EdgeInsets.zero,
    child: GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: C.bgCard, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? glowColor?.withValues(alpha: 0.4) ?? C.border),
          boxShadow: glowColor != null
              ? [BoxShadow(color: glowColor!.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: -4)]
              : [const BoxShadow(color: Color(0x22000000), blurRadius: 8)],
        ),
        child: child,
      ),
    ),
  );
}

// ── KPI Card ──────────────────────────────────────────────────
class KpiCard extends StatelessWidget {
  final String icon;
  final String value;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback? onTap;
  const KpiCard({super.key, required this.icon, required this.value, required this.label,
      this.sub = '', this.color = C.primary, this.onTap});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final compact = w < 340;
      final padding = EdgeInsets.all(compact ? 10 : 14);
      final iconSize = compact ? 18.0 : 22.0;
      final valueSize = compact ? 18.0 : 22.0;
      final labelSize = compact ? 11.0 : 12.0;
      final subFontSize = compact ? 9.0 : 10.0;
      final gapTop = compact ? 6.0 : 8.0;
      final gapMid = compact ? 1.0 : 2.0;

      return GestureDetector(
        onTap: onTap,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact ? 260 : 280,
            ),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: C.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.border),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(icon, style: TextStyle(fontSize: iconSize)),
                      if (sub.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            sub,
                            style: GoogleFonts.syne(
                              fontSize: subFontSize,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: gapTop),
                  Text(
                    value,
                    style: GoogleFonts.syne(
                      fontSize: valueSize,
                      fontWeight: FontWeight.w800,
                      color: C.white,
                    ),
                  ),
                  SizedBox(height: gapMid),
                  Text(
                    label,
                    style: GoogleFonts.syne(
                      fontSize: labelSize,
                      color: C.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ── Section label ─────────────────────────────────────────────
class SLabel extends StatelessWidget {
  final String text;
  const SLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(children: [
      Expanded(child: Container(height: 1, decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [C.primary.withValues(alpha: 0.4), Colors.transparent])))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(text, style: GoogleFonts.syne(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: C.primary, letterSpacing: 1.5))),
      Expanded(child: Container(height: 1, decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.transparent, C.primary.withValues(alpha: 0.4)])))),
    ]),
  );
}

// ── AppField ──────────────────────────────────────────────────
class AppField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? prefixText;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool required;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final bool obscureText;
  final VoidCallback? onTap;
  final Widget? suffix;

  const AppField({
    super.key, required this.label, this.hint, this.controller, this.onChanged,
    this.prefixText, this.keyboardType, this.maxLines = 1, this.required = false,
    this.inputFormatters, this.readOnly = false, this.obscureText = false,
    this.onTap, this.suffix,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      RichText(text: TextSpan(
        text: label.toUpperCase(),
        style: GoogleFonts.syne(fontSize: 10, fontWeight: FontWeight.w700,
            color: C.textMuted, letterSpacing: 0.5),
        children: required ? [TextSpan(text: ' *', style: GoogleFonts.syne(color: C.accent))] : [],
      )),
      const SizedBox(height: 5),
      TextFormField(
        controller: controller, onChanged: onChanged, keyboardType: keyboardType,
        maxLines: maxLines, inputFormatters: inputFormatters,
        readOnly: readOnly, onTap: onTap, obscureText: obscureText,
        style: GoogleFonts.syne(fontSize: 13, color: C.text),
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefixText,
          prefixStyle: GoogleFonts.syne(color: C.textMuted, fontSize: 13),
          suffixIcon: suffix,
        ),
      ),
      const SizedBox(height: 12),
    ],
  );
}

// ── AppDropdown ───────────────────────────────────────────────
class AppDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const AppDropdown({super.key, required this.label, required this.value,
      required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: GoogleFonts.syne(fontSize: 10,
          fontWeight: FontWeight.w700, color: C.textMuted, letterSpacing: 0.5)),
      const SizedBox(height: 5),
      DropdownButtonFormField<T>(
        // Guard: only set initialValue if it exists exactly once in items
        initialValue: (() {
          final matches = items.where((i) => i.value == value).length;
          return matches == 1 ? value : null;
        })(),
        onChanged: onChanged, items: items,
        dropdownColor: C.bgElevated,
        style: GoogleFonts.syne(fontSize: 13, color: C.text),
        decoration: const InputDecoration(),
        isExpanded: true,
      ),
      const SizedBox(height: 12),
    ],
  );
}

// ── Primary Button ────────────────────────────────────────────
class PBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool outline;
  final bool full;
  final bool small;
  final IconData? icon;
  const PBtn({super.key, required this.label, this.onTap, this.color,
      this.outline = false, this.full = false, this.small = false, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? C.primary;
    return SizedBox(
      width: full ? double.infinity : null,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: outline ? Colors.transparent : c,
          foregroundColor: outline ? c : C.bg,
          side: BorderSide(color: onTap == null ? C.border : c, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: small
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
          Text(label, style: GoogleFonts.syne(
              fontSize: small ? 12 : 14, fontWeight: FontWeight.w800,
              letterSpacing: 0.3)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  PHOTO PICKER WIDGET — Camera + Gallery with real image_picker
// ═══════════════════════════════════════════════════════════════

/// Callback returns the file path string of the newly picked image
typedef OnPhotoPicked = void Function(String path);

/// Shows bottom sheet to pick camera or gallery, returns file path
Future<String?> pickPhoto(BuildContext context) async {
  String? result;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      decoration: BoxDecoration(
        color: C.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: C.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Container(margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: C.border,
                borderRadius: BorderRadius.circular(99))),
        const SizedBox(height: 16),
        Text('Add Photo', style: GoogleFonts.syne(
            fontWeight: FontWeight.w800, fontSize: 17, color: C.white)),
        const SizedBox(height: 6),
        Text('Choose a source', style: GoogleFonts.syne(
            fontSize: 13, color: C.textMuted)),
        const SizedBox(height: 20),
        // Camera option
        _PhotoOption(
          icon: Icons.camera_alt_rounded,
          iconColor: C.primary,
          label: 'Take Photo',
          sub: 'Open camera now',
          onTap: () async {
            Navigator.of(ctx).pop();
            final img = await ImagePicker().pickImage(
              source: ImageSource.camera,
              imageQuality: 85,
              maxWidth: 1920,
              maxHeight: 1920,
            );
            result = img?.path;
          },
        ),
        const Divider(color: C.border, height: 1, indent: 16, endIndent: 16),
        // Gallery option
        _PhotoOption(
          icon: Icons.photo_library_rounded,
          iconColor: C.accent,
          label: 'Choose from Gallery',
          sub: 'Select an existing photo',
          onTap: () async {
            Navigator.of(ctx).pop();
            final img = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              maxWidth: 1920,
              maxHeight: 1920,
            );
            result = img?.path;
          },
        ),
        const SizedBox(height: 8),
        // Cancel
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Cancel', style: GoogleFonts.syne(
                  fontWeight: FontWeight.w700, fontSize: 14, color: C.textMuted)),
            ),
          ),
        ),
      ]),
    ),
  );
  return result;
}

class _PhotoOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _PhotoOption({required this.icon, required this.iconColor,
      required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: iconColor, size: 26)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.syne(
              fontWeight: FontWeight.w700, fontSize: 15, color: C.white)),
          Text(sub, style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
        ])),
        const Icon(Icons.chevron_right, color: C.textDim),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  PhotoRow — horizontal photo strip with add button.
//
//  New vs original:
//    • uploadProgress (double?) — inline progress bar + % text
//    • onPhotoAdded nullable    — pass null while uploading to lock strip
//    • tapping a tile opens a swipeable full-screen gallery (not single view)
//    • cloud badge on Firebase Storage URLs
// ─────────────────────────────────────────────────────────────
class PhotoRow extends StatelessWidget {
  final List<String> photos;
  final String label;

  /// Nullable — pass null while uploading to disable add/delete
  final Function(String path)? onPhotoAdded;
  final Function(int index)? onPhotoRemoved;
  final bool canDelete;

  /// 0.0 → 1.0 while uploading; null when idle
  final double? uploadProgress;

  const PhotoRow({
    super.key,
    required this.photos,
    required this.label,
    this.onPhotoAdded,        // was `required` before — now nullable
    this.onPhotoRemoved,
    this.canDelete = true,
    this.uploadProgress,
  });

  bool get _locked => uploadProgress != null && uploadProgress! < 1.0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ── Label + count ──────────────────────────────────────
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        if (label.isNotEmpty)
          Text(label.toUpperCase(), style: GoogleFonts.syne(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: C.textMuted, letterSpacing: 0.5)),
        Text('${photos.length} photo${photos.length == 1 ? "" : "s"}',
            style: GoogleFonts.syne(fontSize: 10, color: C.textMuted)),
      ]),
      const SizedBox(height: 8),

      // ── Inline progress bar (only while uploading) ─────────
      if (_locked) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: uploadProgress,
            minHeight: 4,
            backgroundColor: C.border,
            valueColor: const AlwaysStoppedAnimation<Color>(C.primary),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 2, value: uploadProgress, color: C.primary),
          ),
          const SizedBox(width: 8),
          Text(
            'Uploading… ${((uploadProgress ?? 0) * 100).toStringAsFixed(0)}%  •  compressing <100 KB',
            style: GoogleFonts.syne(fontSize: 11, color: C.textMuted),
          ),
        ]),
        const SizedBox(height: 8),
      ],

      // ── Thumbnail strip ────────────────────────────────────
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          ...photos.asMap().entries.map((e) => _PhotoTile(
            path: e.value,
            index: e.key,
            allPhotos: photos,
            onDelete: canDelete && onPhotoRemoved != null && !_locked
                ? () => onPhotoRemoved!(e.key)
                : null,
          )),
          // Add button — grayed while locked
          GestureDetector(
            onTap: _locked || onPhotoAdded == null
                ? null
                : () async {
                    final path = await pickPhoto(context);
                    if (path != null) onPhotoAdded!(path);
                  },
            child: Container(
              width: 80, height: 80, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_locked || onPhotoAdded == null)
                      ? C.border : C.primary.withValues(alpha: 0.5),
                  width: 2,
                ),
                color: (_locked || onPhotoAdded == null)
                    ? C.bgElevated : C.primary.withValues(alpha: 0.05),
              ),
              child: _locked
                  ? const Center(child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: C.primary)))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_a_photo_outlined,
                          color: onPhotoAdded == null ? C.textDim : C.primary,
                          size: 26),
                      const SizedBox(height: 4),
                      Text('Add Photo', style: GoogleFonts.syne(
                          fontSize: 9,
                          color: onPhotoAdded == null ? C.textDim : C.primary,
                          fontWeight: FontWeight.w700)),
                    ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
    ],
  );
}

class _PhotoTile extends StatelessWidget {
  final String path;
  final int index;
  final List<String> allPhotos;   // full list for swipe gallery
  final VoidCallback? onDelete;

  const _PhotoTile({
    required this.path,
    required this.index,
    required this.allPhotos,
    this.onDelete,
  });

  bool get _isEmoji => !path.startsWith('/') && !path.startsWith('file:') && !path.startsWith('http');
  bool get _isUrl   => path.startsWith('http') || path.startsWith('https');

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: () => _isEmoji ? null : _openGallery(context),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: C.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: C.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: _isEmoji
                ? Center(child: Text(path, style: const TextStyle(fontSize: 32)))
                : _isUrl
                    ? CachedNetworkImage(
                        imageUrl: path, fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: C.primary)),
                        errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: C.textMuted, size: 30)),
                      )
                    : Image.file(File(path), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: C.textMuted, size: 30))),
          ),
        ),
        // Delete ×
        if (onDelete != null) Positioned(
          top: -6, right: -6,
          child: GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                  color: C.red, shape: BoxShape.circle,
                  border: Border.all(color: C.bgCard, width: 2)),
              child: const Icon(Icons.close, color: Colors.white, size: 12),
            ),
          ),
        ),
        // Expand hint
        if (!_isEmoji) Positioned(
          bottom: 4, right: 4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
                color: Colors.black45, borderRadius: BorderRadius.circular(4)),
            child: const Icon(Icons.open_in_full, color: Colors.white, size: 10),
          ),
        ),
        // Cloud-synced badge on Firebase Storage URLs
        if (_isUrl) Positioned(
          bottom: 4, left: 4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
                color: Colors.black45, borderRadius: BorderRadius.circular(4)),
            child: const Icon(Icons.cloud_done_outlined,
                color: Colors.white, size: 10),
          ),
        ),
      ]),
    ),
  );

  void _openGallery(BuildContext context) {
    final real = allPhotos
        .where((p) => p.startsWith('/') || p.startsWith('file:') || p.startsWith('http'))
        .toList();
    final start = real.indexOf(path).clamp(0, (real.length - 1).clamp(0, 9999));
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _PhotoGallery(photos: real, initialIndex: start),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }
}

// ─────────────────────────────────────────────────────────────
//  Full-screen swipe gallery (replaces single _viewFullScreen)
// ─────────────────────────────────────────────────────────────
class _PhotoGallery extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  const _PhotoGallery({required this.photos, required this.initialIndex});

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  late final PageController _ctrl;
  late int _cur;

  bool _isUrl(String s) => s.startsWith('http') || s.startsWith('https');

  @override
  void initState() {
    super.initState();
    _cur = widget.initialIndex;
    _ctrl = PageController(initialPage: _cur);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('${_cur + 1} / ${photos.length}',
            style: GoogleFonts.syne(fontSize: 14, color: Colors.white70)),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: photos.length,
        onPageChanged: (i) => setState(() => _cur = i),
        itemBuilder: (_, i) {
          final src = photos[i];
          return InteractiveViewer(
            minScale: 0.5, maxScale: 5.0,
            child: Center(
              child: _isUrl(src)
                  ? CachedNetworkImage(imageUrl: src, fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(color: C.primary)),
                      errorWidget: (_, __, ___) => _broken())
                  : Image.file(File(src), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _broken()),
            ),
          );
        },
      ),
      bottomNavigationBar: photos.length > 1
          ? Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(photos.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _cur == i ? 16 : 6, height: 6,
                  decoration: BoxDecoration(
                    color: _cur == i ? C.primary : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
              ),
            )
          : null,
    );
  }

  Widget _broken() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
      const SizedBox(height: 12),
      Text('Could not load image',
          style: GoogleFonts.syne(color: Colors.white38, fontSize: 13)),
    ],
  );
}

// ── StatusProgress bar ────────────────────────────────────────
class StatusProgress extends StatelessWidget {
  final String status;
  const StatusProgress(this.status, {super.key});

  static const _order = [
    'Checked In', 'Diagnosed', 'Awaiting Approval', 'Waiting for Parts',
    'In Repair', 'Testing', 'QC Passed', 'Ready for Pickup', 'Completed',
  ];

  @override
  Widget build(BuildContext context) {
    if (status == 'On Hold' || status == 'Cancelled') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: C.statusColor(status).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: C.statusColor(status).withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Text(C.statusIcon(status), style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Text('Job $status', style: GoogleFonts.syne(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: C.statusColor(status))),
        ]),
      );
    }
    final idx = _order.indexOf(status).clamp(0, _order.length - 1);
    final color = C.statusColor(status);
    return Column(children: [
      Row(children: List.generate(_order.length, (i) => Expanded(
        child: Container(
          height: 4,
          margin: EdgeInsets.only(right: i < _order.length - 1 ? 2 : 0),
          decoration: BoxDecoration(
            color: i <= idx ? color : C.bgElevated,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ))),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Checked In', style: GoogleFonts.syne(fontSize: 9, color: C.textMuted)),
        Text('${idx + 1}/${_order.length}',
            style: GoogleFonts.syne(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
        Text('Completed', style: GoogleFonts.syne(fontSize: 9, color: C.textMuted)),
      ]),
    ]);
  }
}

// ── Cost summary card ─────────────────────────────────────────
class CostSummary extends StatelessWidget {
  final double parts;
  final double labor;
  final double discount;
  final double taxRate;
  const CostSummary({super.key, required this.parts, required this.labor,
      required this.discount, required this.taxRate});

  @override
  Widget build(BuildContext context) {
    final sub   = parts + labor;
    final disc  = discount;
    final tax   = (sub - disc) * taxRate / 100;
    final total = sub - disc + tax;
    return SCard(
      glowColor: C.green,
      child: Column(children: [
        _row('Parts + Labor', sub),
        _row('Discount', -disc, color: disc > 0 ? C.red : null),
        _row('GST ${taxRate.toStringAsFixed(0)}%', tax),
        const Divider(color: C.border, height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('TOTAL', style: GoogleFonts.syne(
              fontWeight: FontWeight.w800, fontSize: 16, color: C.white)),
          Text(fmtMoney(total), style: GoogleFonts.syne(
              fontWeight: FontWeight.w800, fontSize: 18, color: C.green)),
        ]),
      ]),
    );
  }

  Widget _row(String l, double v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: GoogleFonts.syne(fontSize: 12, color: C.textMuted)),
      Text(v < 0 ? '-${fmtMoney(-v)}' : fmtMoney(v),
          style: GoogleFonts.syne(fontSize: 12, color: color ?? C.text)),
    ]),
  );
}

// ── Reason dialog (Hold / Cancel / Reopen) ────────────────────
Future<String?> showReasonDialog(BuildContext context, {
  required String title,
  required String hint,
  required Color color,
  required String icon,
  List<String> presets = const [],
}) async {
  final ctrl = TextEditingController();
  String? selected;
  return showDialog<String>(
    context: context,
    builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      backgroundColor: C.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: GoogleFonts.syne(
            fontWeight: FontWeight.w800, fontSize: 16, color: C.white))),
      ]),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (presets.isNotEmpty) ...[
            Text('Quick Reasons', style: GoogleFonts.syne(
                fontSize: 11, color: C.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: presets.map((p) => GestureDetector(
              onTap: () { ss(() => selected = p); ctrl.text = p; },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selected == p ? color.withValues(alpha: 0.2) : C.bgElevated,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: selected == p ? color : C.border),
                ),
                child: Text(p, style: GoogleFonts.syne(
                    fontSize: 11,
                    color: selected == p ? color : C.textMuted,
                    fontWeight: FontWeight.w600)),
              ),
            )).toList()),
            const SizedBox(height: 12),
          ],
          Text('Custom Reason', style: GoogleFonts.syne(
              fontSize: 11, color: C.textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextFormField(
            controller: ctrl, maxLines: 3,
            onChanged: (_) => ss(() => selected = null),
            style: GoogleFonts.syne(fontSize: 13, color: C.text),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.syne(color: C.textMuted))),
        ElevatedButton(
          onPressed: () {
            final reason = ctrl.text.trim().isEmpty ? selected : ctrl.text.trim();
            if (reason != null && reason.isNotEmpty) Navigator.of(ctx).pop(reason);
          },
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: C.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: Text('Confirm', style: GoogleFonts.syne(fontWeight: FontWeight.w800)),
        ),
      ],
    )),
  );
}

// ── Settings Tile ─────────────────────────────────────────────
class SettingsTile extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconBg;
  final bool isDestructive;
  const SettingsTile({super.key, required this.icon, required this.title,
      this.subtitle = '', this.onTap, this.trailing, this.iconBg,
      this.isDestructive = false});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: iconBg ?? (isDestructive
                ? C.red.withValues(alpha: 0.1) : C.primary.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.syne(
              fontWeight: FontWeight.w600, fontSize: 14,
              color: isDestructive ? C.red : C.text)),
          if (subtitle.isNotEmpty) Text(subtitle, style: GoogleFonts.syne(
              fontSize: 12, color: C.textMuted, height: 1.4)),
        ])),
        trailing ?? (onTap != null
            ? const Icon(Icons.chevron_right, color: C.textDim, size: 20)
            : const SizedBox.shrink()),
      ]),
    ),
  );
}

// ── Settings Group ────────────────────────────────────────────
class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> tiles;
  const SettingsGroup({super.key, required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(title, style: GoogleFonts.syne(
            fontSize: 10, fontWeight: FontWeight.w800,
            color: C.textDim, letterSpacing: 2)),
      ),
      SCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: tiles.asMap().entries.map((e) => Column(children: [
          e.value,
          if (e.key < tiles.length - 1) const Divider(height: 1, color: C.border),
        ])).toList()),
      ),
      const SizedBox(height: 20),
    ],
  );
}

// ── Sub-page scaffold ─────────────────────────────────────────
class SubPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? fab;
  final List<Widget>? actions;
  const SubPageScaffold({super.key, required this.title, this.subtitle,
      required this.children, this.fab, this.actions});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    appBar: AppBar(
      backgroundColor: C.bgElevated,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.syne(
            fontWeight: FontWeight.w800, fontSize: 16, color: C.white)),
        if (subtitle != null) Text(subtitle!, style: GoogleFonts.syne(
            fontSize: 11, color: C.textMuted)),
      ]),
      actions: actions,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: children,
    ),
    floatingActionButton: fab,
  );
}
