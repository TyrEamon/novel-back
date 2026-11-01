import 'dart:convert';
import 'dart:io';
import 'catalog.dart';
import 'local_import_options.dart';

/// Even a book with no newline keeps only a bounded physical-line fragment.
/// Decoder preserves UTF-8 sequences; fragment boundaries preserve surrogates.
Stream<({String text, bool heading})> _lines(File file) async* {
  var tail = '', split = false, first = true;
  await for (var chunk in file.openRead().transform(utf8.decoder)) {
    if (first) {
      chunk = chunk.replaceFirst(RegExp('^\uFEFF'), '');
      first = false;
    }
    var start = 0;
    for (final end in [
      ...RegExp(r'[\r\n]').allMatches(chunk).map((m) => m.start),
      chunk.length,
    ]) {
      final value = tail + chunk.substring(start, end);
      var at = 0;
      while (value.length - at > 4000) {
        var next = at + 4000;
        final last = value.codeUnitAt(next - 1);
        if (last >= 0xd800 && last <= 0xdbff) next--;
        yield (text: value.substring(at, next), heading: false);
        at = next;
        split = true;
      }
      tail = value.substring(at);
      if (end < chunk.length) {
        yield (text: tail, heading: !split);
        tail = '';
        split = false;
      }
      start = end + 1;
    }
  }
  if (tail.isNotEmpty) yield (text: tail, heading: !split);
}

/// Called inside the import worker; emits each chapter straight to staging.
Future<List<NovelChapter>> importTextChapters(
  File file,
  String name,
  void Function(int index, String body) save, {
  LocalImportOptions options = const LocalImportOptions(),
}) async {
  final builder = LocalTextChapterBuilder(save, options: options);
  await for (final line in _lines(file)) {
    builder.add(line.text, heading: line.heading);
  }
  return builder.finish();
}

/// Shared by byte-based and streaming TXT imports, so their boundaries, titles
/// and bounded paragraphs cannot drift. Heading text remains in the chapter
/// title; all non-heading text, including illustration placeholders, is kept.
class LocalTextChapterBuilder {
  LocalTextChapterBuilder(
    this.save, {
    this.options = const LocalImportOptions(),
  }) : pattern = options.compile() ?? automaticTextChapter;
  final void Function(int index, String body) save;
  final LocalImportOptions options;
  final RegExp pattern;
  final chapters = <NovelChapter>[];
  final _paragraphs = <String>[];
  int _length = 0, _volumeId = 0, _part = 0;
  String _volume = '';
  String? _title;
  void _flush() {
    if (_paragraphs.isEmpty) return;
    if (chapters.length >= 10000) {
      throw const FormatException('TXT 章节超过 10000 个，请拆分原书后导入');
    }
    final title = _title == null
        ? options.missingTitle(chapters.length + 1)
        : _part == 0
        ? _title!
        : '$_title · 片段 ${_part + 1}';
    chapters.add(
      NovelChapter(
        title,
        '',
        id: chapters.length + 1,
        volumeTitle: _volume,
        volumeId: _volumeId,
      ),
    );
    save(chapters.length, _paragraphs.join('\n\n'));
    _paragraphs.clear();
    _length = 0;
    _part++;
  }

  void add(String raw, {bool heading = true}) {
    final value = raw.trim();
    if (value.isEmpty) return;
    if (heading && matchesLocalHeading(value, automaticTextVolume)) {
      _flush();
      _volume = value;
      _volumeId++;
      _title = null;
      _part = 0;
    } else if (heading &&
        matchesLocalHeading(value, pattern, custom: options.customDirectory)) {
      _flush();
      _title = value;
      _part = 0;
    } else {
      for (var start = 0; start < value.length;) {
        var end = (start + 4000).clamp(0, value.length);
        if (end < value.length &&
            value.codeUnitAt(end - 1) >= 0xd800 &&
            value.codeUnitAt(end - 1) <= 0xdbff) {
          end--;
        }
        final part = value.substring(start, end);
        _paragraphs.add(part);
        _length += part.length + 2;
        if (_length >= 100000) _flush();
        start = end;
      }
    }
  }

  List<NovelChapter> finish() {
    _flush();
    if (chapters.isEmpty) throw const FormatException('文件中没有可阅读的正文');
    return chapters;
  }
}
