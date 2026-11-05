import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_ui.dart';
import '../archive_wave.dart';
import '../book_collection_grid.dart';
import '../book_collection_layout.dart';
import '../catalog.dart';
import '../library_state.dart';
import '../loading_ui.dart';
import '../novel_feed_controller.dart';
import '../offline_repository.dart';
import '../pages.dart' show FeedFooter, NovelRow, openDetail;
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

/// The home feed of one book source.
///
/// One listing at a time, not thirty. The source still declares its blocks
/// (rankings, tags, publisher catalogues); they are offered as a chip row and
/// exactly one of them is loaded, so opening the app costs one request instead
/// of priming a screenful of listings against a host that starts refusing after
/// a dozen calls. Everything past the featured shelf scrolls on demand.
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
  /// One listing page is the shelf's natural ceiling: asking it to hold more
  /// than a page turns it into a second list that has to pull extra pages
  /// before anything appears underneath.
  static const _shelfCap = 20;

  /// A shelf that eats the whole first page leaves an empty index. When the
  /// listing underneath falls below this many books and the site still has
  /// more, one extra page is pulled so the page never reads as a bare shelf.
  static const _indexFloor = 6;

  /// The floor above may not be met by one page (a source can return short
  /// pages), so top-ups stop after two instead of chasing the next page.
  static const _maxTopUps = 2;

  /// null while the account probe is in flight. The feed stays undecided
  /// instead of rendering every gated block and then yanking it away.
  bool? _signedIn;
  bool _probing = false, _pendingProbe = false;
  DateTime? _probedAt;

  final Object _owner = Object();
  NovelFeedController? _feed;
  SourceHomeSection? _loaded;
  SourceHomeSection? _picked;
  int _topUps = 0;

  @override
  void initState() {
    super.initState();
    widget.sources.addListener(_changed);
    widget.sources.accountChanges.addListener(_changed);
    unawaited(_readAccount());
  }

  void _changed() {
    unawaited(_readAccount());
  }

  /// The listing owns the loading / error / end-of-list story, and the footer
  /// only reports what it reads at build time, so the page has to rebuild when
  /// the feed moves or a tap on 加载更多 would change nothing on screen.
  void _onFeedChanged() {
    if (mounted) setState(() {});
  }

  /// Auto paging waits for a real gesture. A short page that fits the screen
  /// leaves almost no scroll extent, and a notification-driven load on that
  /// state pulls page after page while the reader is still looking at the top.
  bool _armed = false;

  /// A block the source declares login-only is dropped until a session exists,
  /// so an anonymous profile never fires the requests that are guaranteed to
  /// bounce to the login page.
  Future<void> _readAccount({bool force = false}) async {
    // Every listing request invalidates the cached account state, so a probe
    // per notification would queue a login check behind each page. The session
    // does not change that fast; an explicit ask still goes through.
    final last = _probedAt;
    if (!force &&
        _signedIn != null &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 10)) {
      return;
    }
    // A probe already in flight would report the pre-login state, so remember
    // that another look is owed instead of dropping the notification.
    if (_probing) {
      _pendingProbe = true;
      return;
    }
    _probing = true;
    try {
      final status = await widget.sources.accountStatus(widget.source);
      _probedAt = DateTime.now();
      if (mounted) setState(() => _signedIn = status.signedIn);
    } catch (_) {
      _probedAt = DateTime.now();
      // A failed probe must not hide blocks that may well answer.
      if (mounted) setState(() => _signedIn = true);
    } finally {
      _probing = false;
      _syncSections();
      if (_pendingProbe) {
        _pendingProbe = false;
        unawaited(_readAccount(force: true));
      }
    }
  }

  bool get _offline =>
      widget.repository is OfflineNovelRepository &&
      (widget.repository as OfflineNovelRepository).offline;

  List<SourceHomeSection>? get _sections {
    final signedIn = _signedIn;
    if (signedIn == null) return null;
    return [
      for (final section in widget.source.homeSections)
        if (!section.requiresLogin || signedIn) section,
    ];
  }

  /// The block the page shows: whatever the reader picked, otherwise the
  /// freshest one the source offers.
  SourceHomeSection? _resolve(List<SourceHomeSection> sections) {
    final picked = _picked;
    if (picked != null) {
      for (final section in sections) {
        if (section.id == picked.id) return section;
      }
    }
    for (final section in sections) {
      if (section.title.contains('最近更新') ||
          section.url.contains('sort=lastupdate')) {
        return section;
      }
    }
    return sections.isEmpty ? null : sections.first;
  }

  /// Signing in or out changes which blocks the source offers, but a probe must
  /// never replace the block the reader is on: re-resolving on every probe turn
  /// a finished tap into a silent jump back to the default block, and dropped
  /// the pages that block had already loaded. Only a block that no longer
  /// exists -- or no feed at all -- goes back through the resolver.
  void _syncSections() {
    final sections = _sections;
    if (sections == null || !mounted) return;
    final loaded = _loaded;
    final missing = loaded == null ||
        !sections.any((s) => s.id == loaded.id && s.url == loaded.url);
    if (_feed == null || missing) _syncFeed();
  }

  void _syncFeed() {
    final sections = _sections;
    if (sections == null || !mounted) return;
    final target = _resolve(sections);
    final loaded = _loaded;
    if (target != null &&
        loaded != null &&
        loaded.id == target.id &&
        loaded.url == target.url) {
      return;
    }
    _feed?.removeListener(_onFeedChanged);
    _feed?.dispose();
    _feed = null;
    _loaded = target;
    _topUps = 0;
    widget.sources.cancelHome(_owner);
    if (target == null) {
      setState(() {});
      return;
    }
    final feed = NovelFeedController(
      widget.repository,
      pageLoader: (page, refresh) {
        if (_offline) throw const SourceFailure('离线模式下请查看已缓存书籍');
        return widget.sources.homePage(
          widget.source,
          target,
          page: page,
          refresh: refresh,
          owner: _owner,
        );
      },
    );
    feed.addListener(_onFeedChanged);
    _armed = false;
    setState(() => _feed = feed);
    unawaited(feed.loadInitial());
  }

  void _select(SourceHomeSection section) {
    final loaded = _loaded;
    final same = loaded != null &&
        loaded.id == section.id &&
        loaded.url == section.url;
    // Tapping the block that is already on screen is a retry when that block
    // came back empty or failed, not a no-op the reader has to guess about.
    if (same) {
      final feed = _feed;
      if (feed != null && (feed.error != null || feed.items.isEmpty)) {
        unawaited(feed.retry());
      }
      return;
    }
    setState(() => _picked = section);
    _syncFeed();
  }

  /// Pulls one more page when the index would otherwise be a stub. Guarded so a
  /// source answering with short pages cannot make this loop.
  void _topUpIfSparse(int listed) {
    final feed = _feed;
    if (feed == null || _topUps >= _maxTopUps) return;
    if (listed >= _indexFloor) return;
    if (feed.loading || !feed.hasMore || feed.error != null) return;
    _topUps++;
    unawaited(feed.loadMore());
  }

  @override
  void dispose() {
    widget.sources.removeListener(_changed);
    widget.sources.accountChanges.removeListener(_changed);
    widget.sources.cancelHome(_owner);
    _feed?.removeListener(_onFeedChanged);
    _feed?.dispose();
    super.dispose();
  }

  /// Shown when every block this source advertises is behind the login wall,
  /// which is far more honest than a list of identical failures.
  Widget _loginPrompt(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
      24,
      MediaQuery.paddingOf(context).bottom + 120,
    ),
    child: ContentPanel(
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
    ),
  );

  Widget _chips(
    BuildContext context,
    List<SourceHomeSection> sections,
    SourceHomeSection current,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final section = sections[index];
          final selected = section.id == current.id;
          return JellyTapSurface(
            key: ValueKey('source-home-chip-${section.id}'),
            onTap: () => _select(section),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? scheme.primaryContainer : scheme.outlineVariant,
                ),
              ),
              child: AppText(
                section.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? scheme.onPrimaryContainer : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _carousel(List<Novel> books, int count) => ArchiveFileCarousel(
    key: ValueKey(('source-home-shelf', books.take(count).map((b) => b.id).join(','))),
    books: books.take(count).toList(growable: false),
    library: widget.state,
    repeatFill: widget.state.discoveryShelfPreferences.repeatFill,
    reduceMotion: widget.state.reduceMotion,
    animateEntrance: true,
    onOpen: (book, tag) => openDetail(
      context,
      book,
      widget.state,
      widget.repository,
      coverHeroTag: tag,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    if (sections == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
          24,
          24,
        ),
        child: const BookCollectionSkeleton(rows: 2),
      );
    }
    if (sections.isEmpty) return _loginPrompt(context);

    final target = _resolve(sections)!;
    final feed = _feed;
    final books = feed?.items ?? const <Novel>[];
    final mode = widget.state.discoveryViewMode;
    final shelf = mode.hasShelf
        ? math.min(
            widget.state.discoveryShelfPreferences.featuredCount(books.length),
            _shelfCap,
          )
        : 0;
    final listed = books.length - shelf;
    final failure = feed?.error;

    if (books.isNotEmpty && listed < _indexFloor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _topUpIfSparse(listed);
      });
    }

    return RefreshIndicator(
      onRefresh: () async {
        _armed = false;
        await _readAccount(force: true);
        await _feed?.refresh();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          final current = _feed;
          if (current == null) return false;
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _armed = true;
          }
          if (notification.depth == 0 &&
              _armed &&
              !current.loading &&
              current.hasMore &&
              current.error == null &&
              notification.metrics.extentAfter < 400) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => current.loadMore(),
            );
          }
          return false;
        },
        child: CustomScrollView(
          key: PageStorageKey('source-home-${widget.source.key}'),
          physics: const AlwaysScrollableScrollPhysics(),
          // A single listing means offscreen prefetch is cheap here: it is the
          // next page of the same feed, not thirty separate listings.
          cacheExtent: BookCollectionLayout.cacheExtentFor(
            MediaQuery.sizeOf(context).width - 48,
            base: 600,
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top +
                      FrostedHeader.toolbarHeight +
                      20,
                  24,
                  0,
                ),
                child: widget.heading,
              ),
            ),
            // The block picker stays reachable while the list is scrolled: with
            // one listing on screen the page can be long, and a picker that
            // scrolls away is a picker that does not exist.
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedChips(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 0, 6),
                  child: _chips(context, sections, target),
                ),
              ),
            ),
            if (books.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: failure != null
                      ? ContentNotice(
                          icon: CupertinoIcons.exclamationmark_triangle,
                          title: '此栏目暂未载入',
                          message: _sectionFailure(failure),
                          onRetry: feed?.retry,
                        )
                      : feed == null || feed.loading || !feed.hasLoaded
                      ? const BookCollectionSkeleton(rows: 2)
                      : const Center(child: AppText('此栏目暂无书籍')),
                ),
              ),
            if (books.isNotEmpty) ...[
              if (shelf > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                    child: _carousel(books, shelf),
                  ),
                ),
              if (shelf > 0 && listed > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    child: sectionHeader(context, '更多书籍', ''),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                sliver: BookCollectionSliver(
                  grid: mode.isGrid,
                  gridDensity: widget.state.discoveryGridDensity,
                  itemCount: listed,
                  itemBuilder: (context, index) {
                    final book = books[index + shelf];
                    final tag = CoverHeroTag(this, book.id);
                    return mode.isGrid
                        ? BookGridTile(
                            book: book,
                            trailing: const SizedBox.shrink(),
                            coverHeroTag: tag,
                            onTap: () => openDetail(
                              context,
                              book,
                              widget.state,
                              widget.repository,
                              coverHeroTag: tag,
                            ),
                          )
                        : NovelRow(
                            novel: book,
                            coverHeroTag: tag,
                            onTap: () => openDetail(
                              context,
                              book,
                              widget.state,
                              widget.repository,
                              coverHeroTag: tag,
                            ),
                          );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: feed == null
                    ? const SizedBox.shrink()
                    : FeedFooter(
                        feed: feed,
                        grid: mode.isGrid,
                        gridDensity: widget.state.discoveryGridDensity,
                      ),
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 90,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of block chips that stays where it is while the listing scrolls.
/// The chips scroll horizontally on their own, so the height never changes.
class _PinnedChips extends SliverPersistentHeaderDelegate {
  _PinnedChips({required this.child, required this.color});
  final Widget child;
  final Color color;
  static const _height = 54.0;
  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: color,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
  @override
  bool shouldRebuild(covariant _PinnedChips old) =>
      old.child != child || old.color != color;
}