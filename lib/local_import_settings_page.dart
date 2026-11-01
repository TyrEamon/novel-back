import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_ui.dart';
import 'app_interactions.dart';
import 'feature_pages.dart';
import 'glass_choices.dart';
import 'local_import_options.dart';
import 'sources/source_fields.dart';

const localImportOptionsKey = 'localImportOptions';
Future<LocalImportOptions> loadLocalImportOptions(
  SharedPreferences preferences,
) async {
  final text = preferences.getString(localImportOptionsKey);
  if (text == null) return const LocalImportOptions();
  try {
    return LocalImportOptions.fromJson(jsonDecode(text) as Map);
  } on FormatException {
    throw const FormatException('导入选项读取失败，请重新保存导入选项');
  }
}

void _previewWorker((SendPort, LocalImportOptions, String) args) {
  try {
    final pattern = args.$2.compile() ?? automaticTextChapter;
    args.$1.send([
      for (final line in args.$3.split(RegExp(r'\r?\n')))
        if (matchesLocalHeading(
          line.trim(),
          pattern,
          custom: args.$2.customDirectory,
        ))
          line.trim(),
    ]);
  } catch (_) {
    args.$1.send(null);
  }
}

Future<List<String>> previewLocalDirectory(
  LocalImportOptions options,
  String sample,
) async {
  options.compile();
  if (sample.length > 16000) throw const FormatException('预览文本最多 16000 字');
  final port = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn(_previewWorker, (
      port.sendPort,
      options,
      sample,
    ), onError: port.sendPort);
    final value = await port.first.timeout(const Duration(seconds: 2));
    if (value is! List || value.any((item) => item is! String)) {
      throw const FormatException('目录预览失败，请检查正则');
    }
    return value.cast<String>();
  } on TimeoutException {
    throw const FormatException('正则处理过慢，请简化后重试');
  } finally {
    worker?.kill(priority: Isolate.immediate);
    port.close();
  }
}

class LocalImportSettingsPage extends StatefulWidget {
  const LocalImportSettingsPage({super.key});
  @override
  State<LocalImportSettingsPage> createState() =>
      _LocalImportSettingsPageState();
}

class _LocalImportSettingsPageState extends State<LocalImportSettingsPage> {
  final _pattern = TextEditingController();
  final _sample = TextEditingController(
    text: '【序幕】\n故事从这里开始。\n【第一节 相遇】\n接下来是正文。',
  );
  bool _custom = false, _numbered = false, _loading = true, _busy = false;
  String? _error;
  List<String>? _preview;
  LocalImportOptions get _options => LocalImportOptions(
    chapterPattern: _custom ? _pattern.text.trim() : '',
    generateMissingTitles: _numbered,
  );
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final options = await loadLocalImportOptions(
        await SharedPreferences.getInstance(),
      );
      if (!mounted) return;
      setState(() {
        _custom = options.customDirectory;
        _numbered = options.generateMissingTitles;
        _pattern.text = options.chapterPattern;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message : '读取导入选项失败',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  LocalImportOptions _validated() {
    if (_custom && _pattern.text.trim().isEmpty) {
      throw const FormatException('请填写目录正则，或选择自动识别');
    }
    final value = _options;
    value.compile();
    return value;
  }

  Future<void> _run(bool save) async {
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final options = _validated();
      if (save) {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(
          localImportOptionsKey,
          jsonEncode(options.toJson()),
        )) {
          throw const FormatException('导入选项未保存，请重试');
        }
        if (mounted) {
          showNovelFeedback(context, '已保存导入选项');
          Navigator.pop(context);
        }
      } else {
        final result = await previewLocalDirectory(options, _sample.text);
        if (mounted) setState(() => _preview = result);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message : '导入选项处理失败',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _pattern.dispose();
    _sample.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '导入选项',
    code: 'LOCAL / CHAPTERS',
    actions: [
      GlassIconButton(
        key: const ValueKey('save-local-import-options'),
        icon: CupertinoIcons.check_mark,
        label: '保存导入选项',
        onPressed: _loading || _busy ? null : () => _run(true),
      ),
    ],
    child: _loading
        ? const LoadingSkeleton(layout: SkeletonLayout.actions)
        : ListView(
            padding: featurePadding(context),
            children: [
              const AppText(
                '适用于之后的本地、扫描与网盘导入。已导入书籍的目录和阅读记录保持不变。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 20),
              GlassChoiceGroup<bool>(
                name: 'local-directory-mode',
                label: '目录识别',
                value: _custom,
                options: const {false: '自动识别', true: '自定义正则'},
                enabled: !_busy,
                onChanged: (value) => setState(() {
                  _custom = value;
                  _preview = null;
                }),
              ),
              AnimatedOptionSection(
                expanded: _custom,
                child: Column(
                  children: [
                    sourceField(
                      context,
                      '章节标题正则',
                      _pattern,
                      hint: r'^【.+】$',
                      lines: 3,
                      readOnly: _busy,
                    ),
                    const AppText(
                      '按整行识别标题。TXT 自动识别常见章名；EPUB 默认保留原目录，自定义正则则按正文中的匹配标题分章。',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: AppText(
                      '为无标题章节补全编号',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppControls.toggle(
                    context,
                    key: const ValueKey('number-untitled-chapters'),
                    value: _numbered,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _numbered = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppText(
                _numbered
                    ? '没有原始标题时，目录显示「第 1 章」等编号。'
                    : '没有原始标题时，目录显示「未命名章节 1」，不把它当成原书标题。',
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 24),
              sourceField(context, '试读片段', _sample, lines: 5, readOnly: _busy),
              GlassTextButton(
                key: const ValueKey('preview-local-directory'),
                onPressed: _busy ? null : () => _run(false),
                child: const AppText('预览目录'),
              ),
              if (_busy) const InlineSkeleton(label: '正在处理目录'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: AppText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (_preview case final rows?) ...[
                const SizedBox(height: 16),
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        rows.isEmpty
                            ? '没有匹配的标题，正文会保留。'
                            : '匹配 ${rows.length} 个标题',
                      ),
                      for (final (index, title) in rows.take(20).indexed)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: AppText(
                            '${index + 1}. $title',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      if (rows.length > 20) const AppText('预览展示前 20 项'),
                    ],
                  ),
                ),
              ],
            ],
          ),
  );
}
