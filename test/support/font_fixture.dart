import 'dart:io';
import 'package:flutter/services.dart';

ByteData? _fontBytes;
Future<void> loadFontFixture() async {
  _fontBytes = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
}

/// Reuse Flutter's own small SDK font to exercise real SFNT import/loading.
/// No application text font or proprietary system font is bundled for tests.
Future<File> createFontFixture(Directory directory) async {
  if (_fontBytes == null) await loadFontFixture();
  final bytes = _fontBytes!;
  return File('${directory.path}/fixture.otf').writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
}
