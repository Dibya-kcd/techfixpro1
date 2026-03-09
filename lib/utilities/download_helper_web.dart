// lib/utils/download_helper_web.dart
// Web implementation — triggers real browser file download.
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

void downloadCsv(String csv, String filename) {
  final bytes = utf8.encode(csv);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8;'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
