// lib/utils/download_helper.dart
//
// Platform-aware CSV download helper.
// Web    → browser triggers a file download automatically.
// Mobile → native share sheet opens (save to Files, Drive, email, etc.)
//
// Usage in settings.dart:
//   import '../utils/download_helper.dart';
//   ...
//   downloadCsv(csvString, 'jobs_export.csv');
//
// Conditional import: Dart picks the right implementation at compile time.
// No runtime checks needed — zero performance cost.

export 'download_helper_stub.dart'
    if (dart.library.js_interop) 'download_helper_web.dart'
    if (dart.library.io)         'download_helper_mobile.dart';
