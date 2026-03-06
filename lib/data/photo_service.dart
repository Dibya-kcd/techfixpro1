import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class PhotoService {
  static final _storage = FirebaseStorage.instance;

  /// Compresses an image to be below 100 KB
  static Future<File?> compressImage(String path) async {
    final file = File(path);
    final size = await file.length();
    
    // If already below 100 KB, no need to compress heavily
    if (size < 100 * 1024) return file;

    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/${const Uuid().v4()}.jpg';

    // Start with quality 80 and reduce until < 100 KB or quality < 10
    int quality = 80;
    XFile? result;
    
    while (quality > 10) {
      result = await FlutterImageCompress.compressAndGetFile(
        path,
        targetPath,
        quality: quality,
        minWidth: 1024,
        minHeight: 1024,
      );
      
      if (result == null) break;
      final newSize = await File(result.path).length();
      if (newSize < 100 * 1024) break;
      quality -= 15;
    }
    
    return result != null ? File(result.path) : file;
  }

  /// Uploads a photo to Firebase Storage and returns the download URL.
  /// [onProgress] receives 0.0 → 1.0 as bytes transfer for live progress bars.
  static Future<String?> uploadPhoto(
    String path,
    String folder, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[PhotoService] File does not exist at path: $path');
        return null;
      }

      // 1. Compress to < 100 KB
      final compressed = await compressImage(path);
      if (compressed == null) {
        debugPrint('[PhotoService] Compression failed for: $path');
        return null;
      }

      // 2. Upload to Firebase Storage
      final fileName = '${const Uuid().v4()}.jpg';
      final ref = _storage.ref().child('$folder/$fileName');
      final uploadTask = ref.putFile(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Pipe progress to caller and debug log
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
      debugPrint('[PhotoService] Error uploading photo: $e');
      return null;
    }
  }

  /// Batch upload — already-https paths pass through unchanged.
  static Future<List<String>> uploadPhotos(List<String> paths, String folder) async {
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
  /// Silent no-op for non-Storage URLs or network failures.
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
