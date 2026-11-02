import 'dart:convert';

/// A heading never ends in a full stop, but prose that happens to open with
/// "第一章我已经看完了" does; the trailing lookahead keeps that line in the body.
const defaultLocalChapterRule =
    r'^(第[零〇一二三四五六七八九十百千万萬两兩0-9０-９]+[章节節回幕话話集篇]|chapter\s+\d+|序章|序言|引子|楔子|前言|尾声|尾聲|终章|終章|后记|後記|番外|外传|外傳|附录|附錄)(?!.*。\s*$)';
const defaultLocalVolumeRule =
    r'^(第[零〇一二三四五六七八九十百千万萬两兩0-9０-９]+[卷部]|volume\s+\d+)(?!.*。\s*$)';

/// Rules are saved with the imported original, not applied retrospectively to
/// a book whose chapter IDs already address positions and bookmarks.
class LocalImportOptions {
  const LocalImportOptions({
    this.customToc = false,
    this.chapterRule = defaultLocalChapterRule,
    this.volumeRule = defaultLocalVolumeRule,
    this.autoTitles = true,
    this.inlineEpubImages = false,
  });
  final bool customToc, autoTitles;

  /// Stored directory semantics, not a global display option. Missing in old
  /// sync bundles means the original one-spine-item-per-chapter layout.
  final bool inlineEpubImages;
  final String chapterRule, volumeRule;
  static const preferenceKey = 'localImportOptions.v1';

  bool get isDefault => !customToc && autoTitles && !inlineEpubImages;
  LocalImportOptions get effective => customToc
      ? this
      : LocalImportOptions(
          autoTitles: autoTitles,
          inlineEpubImages: inlineEpubImages,
        );
  LocalImportOptions withEpubImageLayout(bool inline) => LocalImportOptions(
    customToc: customToc,
    chapterRule: chapterRule,
    volumeRule: volumeRule,
    autoTitles: autoTitles,
    inlineEpubImages: inline,
  );
  Object get identity => (
    customToc,
    autoTitles,
    customToc ? chapterRule : '',
    customToc ? volumeRule : '',
    inlineEpubImages,
  );
  Object get directoryIdentity => (
    customToc,
    customToc ? chapterRule : '',
    customToc ? volumeRule : '',
    inlineEpubImages,
  );

  Map<String, Object> toJson() => {
    'version': inlineEpubImages ? 2 : 1,
    'customToc': customToc,
    'chapterRule': chapterRule,
    'volumeRule': volumeRule,
    'autoTitles': autoTitles,
    if (inlineEpubImages) 'inlineEpubImages': true,
  };
  String encode() => jsonEncode(toJson());
  factory LocalImportOptions.decode(String? value) => value == null
      ? const LocalImportOptions()
      : LocalImportOptions.fromJson(jsonDecode(value));
  factory LocalImportOptions.fromJson(Object? value) {
    if (value == null) return const LocalImportOptions();
    if (value is! Map ||
        !const [1, 2].contains(value['version']) ||
        value['version'] == 2 && value['inlineEpubImages'] is! bool ||
        value['customToc'] is! bool ||
        value['autoTitles'] is! bool ||
        value['chapterRule'] is! String ||
        value['volumeRule'] is! String) {
      throw const FormatException('导入目录设置格式有误');
    }
    final chapter = value['chapterRule'] as String,
        volume = value['volumeRule'] as String;
    if (chapter.length > 1024 ||
        volume.length > 1024 ||
        (value['customToc'] == true && chapter.trim().isEmpty)) {
      throw const FormatException('请填写章节表达式，每条最多 1024 个字符');
    }
    return LocalImportOptions(
      customToc: value['customToc'],
      chapterRule: chapter,
      volumeRule: volume,
      autoTitles: value['autoTitles'],
      inlineEpubImages:
          value['version'] == 2 && value['inlineEpubImages'] == true,
    );
  }
}
