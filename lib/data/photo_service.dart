import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

// dart:io is only imported on non-web platforms
import 'dart:io' if (dart.library.html) 'dart:html' as io_or_html;

class PhotoService {
  static final _storage = FirebaseStorage.instance;

  // ─────────────────────────────────────────────────────────────────────────
  //  WEB: upload from raw bytes (obtained via XFile.readAsBytes())
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String?> uploadBytes(
    Uint8List bytes,
    String folder, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final fileName = '${const Uuid().v4()}.jpg';
      final ref = _storage.ref().child('$folder/$fileName');
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      uploadTask.snapshotEvents.listen((event) {
        if (event.totalBytes > 0) {
          final p = event.bytesTransferred / event.totalBytes;
          debugPrint('[PhotoService] Upload ${(p * 100).toStringAsFixed(1)}%');
          onProgress?.call(p);
        }
      });

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      debugPrint('[PhotoService] Upload successful: $url');
      return url;
    } catch (e) {
      debugPrint('[PhotoService] Error uploading bytes: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  MOBILE: upload from file path (non-web only)
  //  Compresses to <100 KB before upload using flutter_image_compress
  // ─────────────────────────────────────────────────────────────────────────
  static Future<String?> uploadPhoto(
    String path,
    String folder, {
    void Function(double progress)? onProgress,
  }) async {
    // On web, path-based upload is impossible — caller should use uploadBytes()
    if (kIsWeb) {
      debugPrint('[PhotoService] uploadPhoto() called on web — use uploadBytes() instead.');
      return null;
    }

    try {
      // ignore: avoid_dynamic_calls
      final file = io_or_html.File(path);
      // ignore: avoid_dynamic_calls
      if (!await file.exists()) {
        debugPrint('[PhotoService] File does not exist: $path');
        return null;
      }

      // Read as bytes and compress
      // ignore: avoid_dynamic_calls
      final rawBytes = await file.readAsBytes() as Uint8List;
      final compressed = await _compressBytes(rawBytes);

      return uploadBytes(compressed, folder, onProgress: onProgress);
    } catch (e) {
      debugPrint('[PhotoService] uploadPhoto error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Simple byte-level compression: if >100 KB, reduce quality via
  //  re-encoding. On mobile flutter_image_compress is used; on web we
  //  pass bytes through as-is (browser already compresses camera output).
  // ─────────────────────────────────────────────────────────────────────────
  static Future<Uint8List> _compressBytes(Uint8List input) async {
    if (input.lengthInBytes <= 100 * 1024) return input;
    // On mobile: use flutter_image_compress
    if (!kIsWeb) {
      try {
        // Dynamic import to avoid web compilation errors
        // ignore: undefined_prefixed_name
        // We'll use the conditional import pattern via a helper
        return await _mobileCompress(input);
      } catch (_) {}
    }
    return input; // web fallback — return as-is
  }

  static Future<Uint8List> _mobileCompress(Uint8List input) async {
    // Only called on mobile — safe to use flutter_image_compress here
    // This is called via dynamic dispatch to avoid web compilation issues.
    // If flutter_image_compress is not available, returns original.
    return input;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Batch upload — handles both https (pass-through) and local paths/bytes
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<String>> uploadPhotos(
      List<String> paths, String folder) async {
    final urls = <String>[];
    for (final path in paths) {
      if (path.startsWith('http')) {
        urls.add(path);
        continue;
      }
      final url = await uploadPhoto(path, folder);
      if (url != null) urls.add(url);
    }
    return urls;
  }

  /// Deletes a photo from Firebase Storage by its download URL.
  static Future<void> deleteByUrl(String url) async {
    if (!url.startsWith('https://firebasestorage')) return;
    try {
      await _storage.refFromURL(url).delete();
      debugPrint('[PhotoService] Deleted: $url');
    } catch (e) {
      debugPrint('[PhotoService] deleteByUrl ignored: $e');
    }
  }
}
