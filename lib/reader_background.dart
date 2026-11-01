import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import 'library_state.dart';
import 'reader_preferences.dart';

/// Gallery selections become private, bounded PNGs. Preferences/backup carry
/// only the owned ID, not an external URI or the user's original file path.
class ReaderBackgroundStore {
  ReaderBackgroundStore({Directory? directory}) : _directory = directory;
  static final shared = ReaderBackgroundStore();
  static const maxBytes = 32 * 1024 * 1024;
  Directory? _directory;
  Future<Directory> _root() async => _directory ??= Directory(
    '${(await getApplicationSupportDirectory()).path}/reader-backgrounds',
  );

  Future<File?> file(String id) async {
    if (!ReaderPreferences.validBackgroundId(id)) return null;
    final file = File('${(await _root()).path}/$id.png');
    return await file.exists() ? file : null;
  }

  Future<String> importFile(String path) async {
    final source = File(path);
    final length = await source.length();
    if (length < 8 || length > maxBytes) {
      throw const FormatException('背景图片需要在 32 MiB 以内');
    }
    final handle = await source.open();
    try {
      final signature = await handle.read(8);
      if (signature.join(',') != '137,80,78,71,13,10,26,10') {
        throw const FormatException('背景图片未能正确处理，请重新选择');
      }
    } finally {
      await handle.close();
    }
    final root = await _root();
    await root.create(recursive: true);
    final id =
        'bg_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${math.Random.secure().nextInt(0x100000000).toRadixString(36)}';
    final partial = File('${root.path}/$id.part');
    try {
      await source.copy(partial.path);
      await partial.rename('${root.path}/$id.png');
    } finally {
      if (await partial.exists()) await partial.delete();
    }
    return id;
  }

  Future<void> remove(String id) async {
    final image = await file(id);
    if (image == null) return;
    await FileImage(image).evict();
    await image.delete();
  }
}

/// One stable viewport wallpaper, outside the scroll/page content. Image changes
/// repaint the surface; they do not invalidate text shaping or pagination.
class ReaderBackground extends StatefulWidget {
  const ReaderBackground({
    super.key,
    required this.state,
    required this.child,
    this.store,
  });
  final LibraryState state;
  final Widget child;
  final ReaderBackgroundStore? store;
  @override
  State<ReaderBackground> createState() => _ReaderBackgroundState();
}

class _ReaderBackgroundState extends State<ReaderBackground> {
  final _viewport = GlobalKey();
  String? _id;
  double? _opacity;
  ImageProvider? _image;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    widget.state.readerSettingsChanges.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(ReaderBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state || oldWidget.store != widget.store) {
      oldWidget.state.readerSettingsChanges.removeListener(_changed);
      widget.state.readerSettingsChanges.addListener(_changed);
      ++_ticket;
      _id = null;
      _image = null;
      _changed();
    }
  }

  void _changed() {
    final preferences = widget.state.readerPreferences;
    final id = preferences.backgroundImage;
    if (_id != id) {
      _id = id;
      _image = null;
      final ticket = ++_ticket;
      if (id != null) _load(id, ticket);
      setState(() {});
    }
    if (_opacity != preferences.backgroundOpacity) {
      setState(() => _opacity = preferences.backgroundOpacity);
    }
  }

  Future<void> _load(String id, int ticket) async {
    File? file;
    try {
      file = await (widget.store ?? ReaderBackgroundStore.shared).file(id);
    } on FileSystemException {
      file = null;
    }
    if (!mounted || ticket != _ticket) return;
    setState(() => _image = file == null ? null : FileImage(file));
  }

  @override
  void dispose() {
    ++_ticket;
    widget.state.readerSettingsChanges.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BackgroundScope(
    viewport: _viewport,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      image: _image == null
          ? null
          : DecorationImage(
              image: _image!,
              fit: BoxFit.cover,
              opacity: _opacity ?? .25,
              filterQuality: FilterQuality.low,
              onError: (_, _) {},
            ),
    ),
    child: Stack(
      key: _viewport,
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: RepaintBoundary(
            child: ReaderBackgroundPanel(
              key: ValueKey('reader-background-surface'),
            ),
          ),
        ),
        widget.child,
      ],
    ),
  );
}

class _BackgroundScope extends InheritedWidget {
  const _BackgroundScope({
    required this.viewport,
    required this.decoration,
    required super.child,
  });
  final GlobalKey viewport;
  final BoxDecoration decoration;
  @override
  bool updateShouldNotify(_BackgroundScope oldWidget) =>
      viewport != oldWidget.viewport || decoration != oldWidget.decoration;
}

/// A covered/reconfigured page samples the same viewport image, rather than
/// drawing a differently cropped rectangle or flashing a solid sheet over it.
class ReaderBackgroundPanel extends StatelessWidget {
  const ReaderBackgroundPanel({super.key, this.child});
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_BackgroundScope>();
    final decoration = scope?.decoration;
    if (decoration?.image == null) {
      return ColoredBox(
        color: decoration?.color ?? Theme.of(context).colorScheme.surface,
        child: child,
      );
    }
    return _BackgroundPanel(
      viewport: scope!.viewport,
      decoration: decoration!,
      configuration: createLocalImageConfiguration(context),
      child: child,
    );
  }
}

class _BackgroundPanel extends SingleChildRenderObjectWidget {
  const _BackgroundPanel({
    required this.viewport,
    required this.decoration,
    required this.configuration,
    super.child,
  });
  final GlobalKey viewport;
  final BoxDecoration decoration;
  final ImageConfiguration configuration;
  @override
  _BackgroundPanelRender createRenderObject(BuildContext context) =>
      _BackgroundPanelRender(viewport, decoration, configuration);
  @override
  void updateRenderObject(
    BuildContext context,
    _BackgroundPanelRender render,
  ) => render.update(viewport, decoration, configuration);
}

class _BackgroundPanelRender extends RenderProxyBox {
  _BackgroundPanelRender(this.viewport, this.decoration, this.configuration);
  GlobalKey viewport;
  BoxDecoration decoration;
  ImageConfiguration configuration;
  BoxPainter? _painter;
  void update(GlobalKey key, BoxDecoration next, ImageConfiguration config) {
    if (viewport == key && decoration == next && configuration == config) {
      return;
    }
    viewport = key;
    decoration = next;
    configuration = config;
    _painter?.dispose();
    _painter = null;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final root = viewport.currentContext?.findRenderObject();
    final extent = root is RenderBox && root.hasSize ? root.size : size;
    final origin = root is RenderBox && root.attached
        ? MatrixUtils.transformPoint(getTransformTo(root), Offset.zero)
        : Offset.zero;
    _painter ??= decoration.createBoxPainter(markNeedsPaint);
    context.canvas.save();
    context.canvas.clipRect(offset & size);
    _painter!.paint(
      context.canvas,
      offset - origin,
      configuration.copyWith(size: extent),
    );
    context.canvas.restore();
    super.paint(context, offset);
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }
}
