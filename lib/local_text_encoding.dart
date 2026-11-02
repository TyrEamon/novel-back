import 'dart:convert';
import 'dart:typed_data';

/// Share of non-ASCII code units that must be Han (U+4E00-U+9FFF) when mixed.
const localTextHanShareFloor = 0.15;
/// U+FFFD appears only when a decode already lost data.
const localTextReplacementShareCeiling = 0.001;
/// Control code units (tab/newline excluded) mean binary or a bad guess.
const localTextControlShareCeiling = 0.002;
/// Both gates read only this many code units, never the whole book.
const localTextSampleUnits = 240000;

/// A decoded TXT plus the encoding that produced it.
class LocalTextDecoding {
  const LocalTextDecoding(this.text, this.encoding);

  /// Sanitized: no BOM/NUL, `\n` line endings, no trailing blank lines.
  final String text;
  final String encoding;
}

/// BOM first, then a BOM-less UTF-16 sniff, then strict UTF-8, then a legacy
/// CJK diagnosis: there is no GB18030 table in Dart, so a GBK/Big5 file is
/// named and rejected instead of being decoded into garbage.
LocalTextDecoding decodeLocalTextBytes(List<int> bytes) {
  if (bytes.isEmpty) throw const FormatException('文件为空，请重新下载原书');
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (_startsWith(data, const [0xff, 0xfe, 0x00, 0x00]) ||
      _startsWith(data, const [0x00, 0x00, 0xfe, 0xff])) {
    throw const FormatException('这个 TXT 是 UTF-32 编码，请另存为 UTF-8 后重新导入');
  }
  if (_startsWith(data, const [0xef, 0xbb, 0xbf])) {
    return _accept(_utf8(data, 3), 'UTF-8');
  }
  if (_startsWith(data, const [0xff, 0xfe])) {
    return _accept(_utf16(data, 2, littleEndian: true), 'UTF-16LE');
  }
  if (_startsWith(data, const [0xfe, 0xff])) {
    return _accept(_utf16(data, 2, littleEndian: false), 'UTF-16BE');
  }
  final littleEndian = _utf16Endian(data);
  if (littleEndian != null) {
    // A sniff is only a hint: a bad guess falls through to UTF-8/legacy.
    final text = _sanitize(_utf16(data, 0, littleEndian: littleEndian));
    if (_acceptable(text)) {
      return LocalTextDecoding(text, littleEndian ? 'UTF-16LE' : 'UTF-16BE');
    }
  }
  try {
    // Sanitize first: Notepad leaves BOM/NUL bytes that would trip the gate.
    final text = _sanitize(utf8.decode(data, allowMalformed: false));
    if (_acceptable(text)) return LocalTextDecoding(text, 'UTF-8');
  } on FormatException {
    // Not UTF-8: fall through to the legacy encoding diagnosis.
  }
  throw FormatException(_legacyFailure(data));
}

/// Collapses CRLF, drops BOM/NUL leftovers and trailing blank lines, which is
/// what Notepad-saved TXT files need.
String _sanitize(String text) {
  if (text.isEmpty) return text;
  var value = text.startsWith('\uFEFF') ? text.substring(1) : text;
  value = value.replaceAll('\uFEFF', '').replaceAll('\u0000', '');
  value = value.replaceAll(RegExp(r'\r\n?'), '\n');
  return value.replaceAll(RegExp(r'[ \t\n]+$'), '');
}

LocalTextDecoding _accept(String text, String encoding) {
  final value = _sanitize(text);
  if (!_acceptable(value)) {
    throw const FormatException(
      '这个 TXT 解出来的正文无法识别，文件可能已损坏；请另存为 UTF-8 后重新导入',
    );
  }
  return LocalTextDecoding(value, encoding);
}

bool _startsWith(Uint8List data, List<int> prefix) {
  if (data.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix[i]) return false;
  }
  return true;
}

String _utf8(Uint8List data, int start) {
  try {
    final body = start == 0 ? data : Uint8List.sublistView(data, start);
    return utf8.decode(body, allowMalformed: false);
  } on FormatException {
    throw const FormatException('这个 TXT 不是有效的 UTF-8 文本，请另存为 UTF-8 后重新导入');
  }
}

String _utf16(Uint8List data, int start, {required bool littleEndian}) {
  final length = data.length - start;
  if (length.isOdd) {
    throw const FormatException('这个 TXT 的 UTF-16 内容不完整，请另存为 UTF-8 后重新导入');
  }
  final units = Uint16List(length ~/ 2);
  for (var i = 0; i < units.length; i++) {
    final at = start + i * 2;
    units[i] = littleEndian
        ? data[at] | (data[at + 1] << 8)
        : (data[at] << 8) | data[at + 1];
  }
  return String.fromCharCodes(units);
}

/// BOM-less UTF-16 shows zero bytes on one parity (ASCII runs) and a clean
/// other parity; pure-CJK UTF-16 without a BOM is not guessed here.
bool? _utf16Endian(Uint8List data) {
  if (data.length < 8 || !data.length.isEven) return null;
  final limit = data.length < 4096 ? data.length : 4096;
  final pairs = limit ~/ 2;
  var evenZeros = 0;
  var oddZeros = 0;
  for (var i = 0; i < pairs * 2; i++) {
    if (data[i] != 0) continue;
    if (i.isEven) {
      evenZeros++;
    } else {
      oddZeros++;
    }
  }
  if (oddZeros * 2 > pairs && evenZeros * 20 < pairs) return true;
  if (evenZeros * 2 > pairs && oddZeros * 20 < pairs) return false;
  return null;
}

bool _acceptable(String text) {
  if (text.isEmpty) return false;
  final limit = text.length < localTextSampleUnits
      ? text.length
      : localTextSampleUnits;
  var han = 0;
  var nonAscii = 0;
  var replacement = 0;
  var control = 0;
  for (var i = 0; i < limit; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0xfffd) {
      replacement++;
    } else if (unit < 0x20) {
      if (unit != 0x09 && unit != 0x0a && unit != 0x0d) control++;
    } else if (unit > 0x7e) {
      nonAscii++;
      if (unit >= 0x4e00 && unit <= 0x9fff) han++;
    }
  }
  if (replacement > limit * localTextReplacementShareCeiling) return false;
  if (control > limit * localTextControlShareCeiling) return false;
  // English prose carries no Han characters at all; only mixed samples are
  // judged by their Han share.
  if (nonAscii * 4 < limit) return true;
  return han >= nonAscii * localTextHanShareFloor;
}

String _legacyFailure(Uint8List data) {
  if (_looksLegacyCjk(data)) {
    return '这个 TXT 不是 UTF-8，看起来是 GBK/GB18030 或 Big5 编码：请从文件重新导入，'
        '并在导入设置里把「TXT 文本编码」指定为 GB18030（或 Big5），'
        '避免把乱码正文存进书库';
  }
  return '无法识别这个 TXT 的文本编码，文件可能不是纯文本或已损坏；请另存为 UTF-8 后重新导入';
}

/// Sequential GB18030 shape check: ASCII, 4-byte runs, or 2-byte pairs whose
/// lead is 81-FE and trail is 40-FE without 7F.
bool _looksLegacyCjk(Uint8List data) {
  final limit = data.length < 65536 ? data.length : 65536;
  var pairs = 0;
  var ascii = 0;
  var i = 0;
  while (i < limit) {
    final lead = data[i];
    if (lead < 0x80) {
      ascii++;
      i++;
      continue;
    }
    if (i + 1 >= limit || lead < 0x81 || lead > 0xfe) return false;
    final trail = data[i + 1];
    if (trail >= 0x30 && trail <= 0x39) {
      if (i + 3 >= limit) return false;
      final third = data[i + 2];
      final fourth = data[i + 3];
      if (third < 0x81 || third > 0xfe || fourth < 0x30 || fourth > 0x39) {
        return false;
      }
      pairs++;
      i += 4;
      continue;
    }
    if (trail < 0x40 || trail > 0xfe || trail == 0x7f) return false;
    pairs++;
    i += 2;
  }
  return pairs > ascii ~/ 4;
}