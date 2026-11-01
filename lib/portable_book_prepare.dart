import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show RootIsolateToken;

typedef PreparedBookDocument = ({String name, String? path, String? error});

/// Minimal stand-in for the unpublished portable import pipeline. The native
/// conversion entry point is kept; Kindle/PDF pre-extraction is skipped.
class PortableBookPreparer {
  PortableBookPreparer({
    required this.directory,
    required this.textCodecToken,
    required this.decodeNames,
    required this.convert,
    required this.extractKindle,
    this.extractPdf,
  });

  final Directory directory;
  final RootIsolateToken? textCodecToken;
  final Future<List<String>> Function(List<String> names) decodeNames;
  final Future<List<PreparedBookDocument>> Function(String name, String path)
  convert;
  final Future<int> Function(String source, String output) extractKindle;
  final Future<void> Function(String name, String source, String output)?
  extractPdf;

  static Future<void> clearPreviousRuns(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      /* Scratch space is disposable. */
    }
    try {
      await directory.create(recursive: true);
    } catch (_) {
      /* A missing scratch directory only delays the next import. */
    }
  }

  Future<List<PreparedBookDocument>> prepare(String name, String path) =>
      convert(name, path);

  /// Discard staged copies once the importer has consumed them. The scratch
  /// directory is recreated on the next run, so nothing else needs cleanup.
  Future<void> releasePaths(Iterable<String> paths) async {}
}