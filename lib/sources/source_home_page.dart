import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_interactions.dart';
import '../app_language.dart';
import '../app_ui.dart';
import '../archive_design.dart';
import '../archive_icons.dart';
import '../archive_wave.dart';
import '../book_collection_layout.dart';
import '../catalog.dart';
import '../feature_pages.dart';
import '../library_state.dart';
import '../loading_ui.dart';
import '../novel_feed_controller.dart';
import '../offline_repository.dart';
import '../pages.dart' show InlineSearchResults, NovelRow, openDetail;
import 'book_source.dart';
import 'source_pages.dart' show openSourceManager;
import 'source_repository.dart';

/// A section-level message that keeps the rule failure readable instead of
/// collapsing every kind of error into one generic line.
String _sectionFailure(Object error) => switch (error) {
  SourceFailure(:final message) => message,
  FormatException(:final message) => '$message',
  _ => '$error',
};

/// The home feed of one book source: several blocks (hot lists, per-genre
/// shelves, a cloud shelf) instead of the single flat explore entry.
class SourceHomePage extends StatefulWidget {
  const SourceHomePage({
    super.key,
    required this.sources,
    required this.source,
    required this.repository,
    required this.state,
    required this.heading,
  });
  final SourceNovelRepository sources;
  final BookSource source;
  final NovelRepository repository;
  final LibraryState state;
  final Widget heading;
  @override
  State<SourceHomePage> createState() => _SourceHomePageState();
}

class _SourceHomePageState extends State<SourceHomePage> {
  int _generation = 0;

  /// null while the account probe is in flight. The feed stays undecided
  /// instead of rendering every gated block and then yanking it away.
  bool? _signedIn;
  bool _probing = false, _pendingProbe = false;

  @override
  void initState() {
    super.initState();
    widget.sources.addListener(_changed);
    widget.sources.accountChanges.addListener(_changed);
    unawaited(_readAccount());
  }

  void _changed() {
    if (mounted) setState(() => _generation++);
    unawaited(_readAccount());
  }

  /// A block the source declares login-only is dropped from the feed until a
  /// session exists, so an anonymous profile never fires the requests that are
  /// guaranteed to bounce to the login page.
  Future<void> _readAccount() async {
    // A probe already in flight would report the pre-login state, so remember
    // that another look is owed instead of dropping the notification.
    if (_probing) {
      _pendingProbe = true;
      return;
    }
    _probing = true;
    try {
      final status = await widget.sources.accountStatus(widget.source);
      if (mounted) setState(() => _signedIn = status.signedIn);
    } catch (_) {
      // A failed probe must not hide blocks that may well answer.
      if (mounted) setState(() => _signedIn = true);
    } finally {
      _probing = false;
      if (_pendingProbe) {
        _pendingProbe = false;
        unawaited(_readAccount());
      }
    }
  }

  @override
  void dispose() {
    widget.sources.removeListener(_changed);
    widget.sources.accountChanges.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _signedIn;
    final all = widget.source.homeSections;
    // Resolved to a plain bool so the block filter never leans on null
    // promotion inside a collection-if.
    final open = signedIn == true;
    final visible = signedIn == null
        ? const <SourceHomeSection>[]
        : [
            for (final section in all)
              if (!section.requiresLogin || open) section,
          ];
    final padding = EdgeInsets.fromLTRB(
      24,
      20,
      24,
      MediaQuery.paddingOf(context).bottom + 120,
    );
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _generation++);
        await _readAccount();
        await Future<void>.delayed(Duration.zero);
      },
      child: CustomScrollView(
        key: PageStorageKey('source-home-${widget.source.key}'),
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 250,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.paddingOf(context).top +
                  FrostedHeader.toolbarHeight +
                  20,
              24,
              0,
            ),
            sliver: SliverToBoxAdapter(child: widget.heading),
          ),
          if (signedIn == null)
            SliverPadding(
              padding: padding,
              sliver: const SliverToBoxAdapter(
                child: BookCollectionSkeleton(rows: 2),
              ),
            )
          else if (visible.isEmpty)
            SliverPadding(
              padding: padding,
              sliver: SliverToBoxAdapter(child: _loginPrompt(context)),
            )
          else
            SliverPadding(
              padding: padding,
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) => _HomeSection(
                  key: ValueKey((
                    widget.source.key,
                    visible[index].id,
                    _generation,
                  )),
                  sources: widget.sources,
                  source: widget.source,
                  section: visible[index],
                  repository: widget.repository,
                  state: widget.state,
                  signedIn: open,
                  featured: index == 0,
                  order: index,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Shown when every block this source advertises is behind the login wall,
  /// which is far more honest than a list of identical failures.
  Widget _loginPrompt(BuildContext context) => ContentPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppText('此源的内容需登录后显示'),
        const SizedBox(height: 8),
        const AppText(
          '登录一次账号密码，会话会留在该源自己的浏览环境里，发现页随后自动出现。',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        GlassTextButton(
          onPressed: () => openSourceManager(
            context,
            widget.sources,
            reduceMotion: widget.state.reduceMotion,
            library: widget.state,
          ),
          child: const AppText('账号与登录'),
        ),
      ],
    ),
  );
}

class _HomeSection extends StatefulWidget {
  const _HomeSection({
    super.key,
    required this.sources,
    required this.source,
    required this.section,
    required this.repository,
    required this.state,
    required this.signedIn,
    required this.featured,
    required this.order,
  });
  final SourceNovelRepository sources;
  final BookSource source;
  final SourceHomeSection section;
  final NovelRepository repository;
  final LibraryState state;
  final bool signedIn;
  final bool featured;
  final int order;
  @override
  State<_HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends State<_HomeSection>
    with AutomaticKeepAliveClientMixin {
  final _owner = Object();
  bool _preparing = false, _locked = false;
  String? _error;
  bool get _offline =>
      widget.repository is OfflineNovelRepository &&
      (widget.repository as OfflineNovelRepository).offline;
  late final _feed = NovelFeedController(
    widget.repository,
    initialItems: 10,
    pageLoader: (page, refresh) {
      if (_offline) throw const SourceFailure('离线模式下请查看已缓存书籍');
      return widget.sources.homePage(
        widget.source,
        widget.section,
        page: page,
        refresh: refresh,
        owner: _owner,
      );
    },
  );
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_preparing) return;
    setState(() {
      _preparing = true;
      _locked = false;
      _error = null;
    });
    try {
      if (_offline) throw const SourceFailure('离线模式下请查看已缓存书籍');
      // This port keeps the source account flows on the source manager page, so
      // a login-only block reports its requirement instead of opening a
      // dedicated account route.
      if (widget.section.requiresLogin && !widget.signedIn) {
        setState(() => _locked = true);
        return;
      }
      if (_feed.hasLoaded) {
        await _feed.refresh();
      } else {
        await _feed.loadInitial();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _sectionFailure(error));
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _more() async {
    await pushNovelPage<void>(
      context,
      ArchiveFeaturePage(
        key: ValueKey('source-home-all-${widget.section.id}'),
        title: widget.section.title,
        code: '${widget.source.name} / FULL INDEX',
        child: InlineSearchResults(
          state: widget.state,
          repository: widget.repository,
          feed: _feed,
          onOpenBook: () {},
          emptyQueryTitle: widget.section.title,
        ),
      ),
      reduceMotion: widget.state.reduceMotion,
    );
  }

  @override
  void dispose() {
    widget.sources.cancelHome(_owner);
    _feed.dispose();
    super.dispose();
  }

  Widget _books(List<Novel> books) {
    if (widget.featured) {
      return ArchiveFileCarousel(
        books: books,
        reduceMotion: widget.state.reduceMotion,
        animateEntrance: true,
        library: widget.state,
        onOpen: (book, tag) => openDetail(
          context,
          book,
          widget.state,
          widget.repository,
          coverHeroTag: tag,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = BookCollectionLayout.columnsFor(constraints.maxWidth);
        return Column(
          children: [
            for (var row = 0; row < (books.length / columns).ceil(); row++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column != 0)
                      const SizedBox(width: BookCollectionLayout.gap),
                    Expanded(
                      child: row * columns + column < books.length
                          ? NovelRow(
                              novel: books[row * columns + column],
                              coverHeroTag: CoverHeroTag(
                                this,
                                books[row * columns + column].id,
                              ),
                              onTap: () => openDetail(
                                context,
                                books[row * columns + column],
                                widget.state,
                                widget.repository,
                                coverHeroTag: CoverHeroTag(
                                  this,
                                  books[row * columns + column].id,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: _feed,
      builder: (context, _) {
        final books = _feed.items.take(10).toList(growable: false);
        final failure =
            _error ?? (_feed.error == null ? null : _sectionFailure(_feed.error!));
        return Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            key: ValueKey('source-home-section-${widget.section.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ArchiveSection(
                title: widget.section.title,
                code:
                    '${(widget.order + 1).toString().padLeft(2, '0')} / ARCHIVE INDEX',
                moreKey: ValueKey('source-home-more-${widget.section.id}'),
                onMore: _more,
              ),
              const SizedBox(height: 12),
              if (_locked)
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText('登录此平台后可见云端收藏'),
                      const SizedBox(height: 8),
                      GlassTextButton(
                        onPressed: () => openSourceManager(
                          context,
                          widget.sources,
                          reduceMotion: widget.state.reduceMotion,
                          library: widget.state,
                        ),
                        child: const AppText('账号与登录'),
                      ),
                    ],
                  ),
                )
              else if (books.isNotEmpty)
                _books(books)
              else if (_preparing ||
                  _feed.loading ||
                  !_feed.hasLoaded && failure == null)
                const BookCollectionSkeleton(rows: 2)
              else if (failure == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: AppText('此栏目暂无书籍'),
                ),
              if (failure != null)
                ContentNotice(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  title: '此栏目暂未载入',
                  message: failure,
                  onRetry: _load,
                ),
              if (books.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: JellyTapSurface(
                      key: ValueKey(
                        'source-home-more-bottom-${widget.section.id}',
                      ),
                      onTap: _more,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppText('查看更多', style: TextStyle(fontSize: 14)),
                            SizedBox(width: 8),
                            ArchiveIcon(
                              CupertinoIcons.arrow_up_right,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}