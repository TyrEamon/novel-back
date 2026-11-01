/// Parsing choices are a snapshot per import, never a mutation of an existing
/// book's chapter IDs, bookmarks or progress.
class LocalImportOptions {
  const LocalImportOptions({
    this.chapterPattern = '',
    this.generateMissingTitles = false,
  });
  final String chapterPattern;
  final bool generateMissingTitles;
  bool get customDirectory => chapterPattern.trim().isNotEmpty;
  RegExp? compile() {
    if (!customDirectory) return null;
    if (chapterPattern.length > 512) {
      throw const FormatException('目录正则最多 512 个字符');
    }
    try {
      return RegExp(chapterPattern, caseSensitive: false);
    } on FormatException {
      throw const FormatException('目录正则格式不正确，请检查括号与转义');
    }
  }

  String missingTitle(int index) =>
      generateMissingTitles ? '第 $index 章' : '未命名章节 $index';
  Map<String, Object> toJson() => {
    'chapterPattern': chapterPattern,
    'generateMissingTitles': generateMissingTitles,
  };
  factory LocalImportOptions.fromJson(Map<dynamic, dynamic> value) =>
      LocalImportOptions(
        chapterPattern: value['chapterPattern'] is String
            ? value['chapterPattern'] as String
            : '',
        generateMissingTitles: value['generateMissingTitles'] == true,
      );
}

final automaticTextChapter = RegExp(
  r'^(第[零〇一二三四五六七八九十百千万两0-9０-９]+[章节回幕话話]|chapter\s+\d+|序章|序言|楔子|尾声|尾聲|后记|後記|番外)',
  caseSensitive: false,
);
final automaticTextVolume = RegExp(
  r'^(第[零〇一二三四五六七八九十百千万两0-9０-９]+[卷部]|volume\s+\d+)',
  caseSensitive: false,
);

bool matchesLocalHeading(String text, RegExp pattern, {bool custom = false}) =>
    text.isNotEmpty &&
    text.length <= (custom ? 256 : 90) &&
    pattern.hasMatch(text);
