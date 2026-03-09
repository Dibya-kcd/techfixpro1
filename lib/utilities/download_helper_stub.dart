// lib/utilities/download_helper_stub.dart
// Fallback stub — should never be called at runtime.
// Only exists so the conditional export in download_helper.dart compiles
// on any platform Dart doesn't recognise.

void downloadCsv(String csv, String filename) {
  throw UnsupportedError('downloadCsv is not supported on this platform');
}
