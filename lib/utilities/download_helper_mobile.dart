// lib/utilities/download_helper_mobile.dart
// Mobile implementation — saves CSV then opens native share sheet.
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void downloadCsv(String csv, String filename) async {
  try {
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(utf8.encode(csv));
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: filename,
    );
  } catch (e) {
    rethrow;
  }
}
