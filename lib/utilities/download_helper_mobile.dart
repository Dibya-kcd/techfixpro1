// lib/utils/download_helper_mobile.dart
// Mobile implementation — saves CSV to Downloads folder and opens share sheet.
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void downloadCsv(String csv, String filename) async {
  try {
    // Write to temp directory first
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(utf8.encode(csv));

    // Open native share sheet — user can save to Files, Drive, email, etc.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: filename,
      ),
    );
  } catch (e) {
    // silently fail — caller handles UI
    rethrow;
  }
}
