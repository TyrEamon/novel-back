import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../app_language.dart';
import '../catalog.dart';
import '../book_search.dart';
import '../offline_repository.dart';
import '../tag_catalogue.dart';
import '../library_state.dart';
import 'book_source.dart';
import 'source_account.dart';
import 'source_platform.dart';
import 'source_store.dart';
import 'source_image_locator.dart';

SourceNovelRepository? sourceRepositoryOf(NovelRepository? repository) {
  final remote = repository is OfflineNovelRepository
      ? repository.remote
      : repository;
  return remote is SourceNovelRepository ? remote : null;
}

typedef _ListingKey = ({
  String source,
  String operation,
  String term,
  Object scope,
});
typedef _SourceQuery = ({BookSource source, String operation, String term});

class _SourceSearchPlan {
  _SourceSearchPlan(this.queries);
  final List<_SourceQuery> queries;
  final pages = <_SourceQuery, int>{};
  final ended = <_SourceQuery>{};
  int nextIndex = 0;
  _SourceQuery? next({Set<_SourceQuery> excluding = const {}}) {
    for (var i = 0; i < queries.length; i++) {
      final index = (nextIndex + i) % queries.length;
      final query = queries[index];
      if (!ended.contains(query) && !excluding.contains(query)) {
        nextIndex = (index + 1) % queries.length;
        return query;
      }
    }
    return null;
  }

  bool get exhausted => ended.length == queries.length;
}

class _SourceListing {
  int remotePage = 0;
  String? nextUrl;
  bool ended = false, cancelled = false;
  final seen = <int>{};
  final visited = <String>{};
  final requests = <String>{};
}

class SourceNovelRepository extends ChangeNotifier
    implements NovelRepository, ProgressiveTagCatalogue {
  SourceNovelRepository({
    required this.store,
    this.legacyBook,
    this.platform = const SourcePlatform(),
  }) {
    store.addListener(_changed);
  }
  final SourceStore store;
  final Novel? Function(int)? legacyBook;
  final SourcePlatform platform;
  final accountChanges = ChangeNotifier();
  final _accountStates =
      <String, ({BookSource definition, Future<SourceAccountStatus> value})>{};
  final _accountRequests = <String>{};
  final _accountBusy = <String>{};
  Future<SourceAccountStatus> accountStatus(BookSource source) {
    final cached = _accountStates[source.key];
    if (cached != null && identical(cached.definition.data, source.data)) {
      return cached.value;
    }
    final value = platform.accountStatus(source);
    _accountStates[source.key] = (definition: source, value: value);
    return value;
  }

  void refreshAccount([String? key]) {
    if (key == null) {
      _accountStates.clear();
    } else {
      _accountStates.remove(key);
    }
    if (!_disposed) accountChanges.notifyListeners();
  }

  Future<bool> verifyAccount(BookSource source, {String? requestId}) async {
    try {
      return await platform.run(
            source,
            'accountVerify',
            requestId: requestId,
          ) ==
          true;
    } finally {
      refreshAccount(source.key);
    }
  }

  Future<void> loginFinished(BookSource source, {String? requestId}) async {
    sessionChanged();
    if (source.enabled && sourceCanVerifyAccount(source)) {
      // A failed account check must not disguise a completed login command.
      // Its own state is displayed on the source card/login page.
      try {
        await verifyAccount(source, requestId: requestId);
      } catch (_) {}
    }
  }

  Future<bool> checkIn(BookSource source, {required String requestId}) async {
    try {
      final result =
          await platform.run(source, 'accountCheckIn', requestId: requestId)
              as Map;
      return result['already'] == true;
    } finally {
      refreshAccount(source.key);
    }
  }

  /// Explicit, one-way merge from a source-declared shelf. A failed/cancelled
  /// page never publishes a partial shelf, and remote absences never delete books.
  Future<int> syncSourceShelf(
    BookSource source,
    LibraryState library, {
    required String requestId,
  }) async {
    if (!_accountBusy.add(source.key)) throw const SourceFailure('此书源正在同步');
    final revision = _revision;
    _accountRequests.add(requestId);
    final rows = <String, Map<String, dynamic>>{};
    final visited = <String>{};
    String? nextUrl;
    var complete = false;
    void check() {
      if (_disposed ||
          revision != _revision ||
          !_accountRequests.contains(requestId)) {
        throw const SourceFailure('书架同步已取消，未更改本机书架');
      }
    }

    try {
      for (var page = 1; page <= 64; page++) {
        check();
        final result =
            await platform.run(
                  source,
                  'accountShelf',
                  url: nextUrl,
                  page: page,
                  requestId: requestId,
                )
                as Map;
        check();
        final pageUrl = result['pageUrl'] as String?;
        if (pageUrl != null && !visited.add(pageUrl)) {
          throw const SourceFailure('书源云书架分页重复，未更改本机书架');
        }
        final items = result['items'] as List;
        var added = 0;
        for (final raw in items) {
          final row = Map<String, dynamic>.from(raw as Map);
          final url = '${row['bookUrl'] ?? ''}'.trim();
          if (url.isEmpty || '${row['name'] ?? ''}'.trim().isEmpty) {
            throw const SourceFailure('云书架中有书籍缺少名称或地址，未更改本机书架');
          }
          if (!rows.containsKey(url)) added++;
          rows[url] = row;
        }
        if (rows.length > 5000) {
          throw const SourceFailure('云书架超过 5000 本，请在书源中缩小范围后重试');
        }
        if (result['hasMore'] != true) {
          complete = true;
          break;
        }
        if (items.isEmpty || added == 0) {
          throw const SourceFailure('书源云书架分页没有前进，未更改本机书架');
        }
        nextUrl = result['nextUrl'] as String?;
      }
      if (!complete) throw const SourceFailure('云书架超过 64 页，未更改本机书架');
      check();
      final books = rows.values
          .map((row) => store.remember(source, row))
          .toList();
      await store.flush();
      check();
      final additions = books
          .where((book) => !library.contains(book.id))
          .length;
      await library.addShelfBooks(books);
      return additions;
    } finally {
      _accountRequests.remove(requestId);
      _accountBusy.remove(source.key);
      refreshAccount(source.key);
    }
  }

  Future<void> cancelAccountRequest(String requestId) async {
    _accountRequests.remove(requestId);
    await platform.cancel(requestId);
  }

  final failures = <String, String>{};
  final _detailWarnings = <int, List<String>>{};
  List<String> detailWarnings(int id) => _detailWarnings[id] ?? const [];
  final _pending = <String, Future<dynamic>>{};
  final _listings = <_ListingKey, _SourceListing>{};
  final _searchSeen = <int>{};
  final _searchFailed = <String>{};
  final _searchFinished = <String>{};
  final _searchQueries = <String, Future<_SourceSearchPlan>>{};
  int _nextSearchSource = 0;
  final _explores = <String, List<SourceExplore>>{};
  final _exploreRequests = <String>{};
  bool _disposed = false;
  int _revision = 0;
  static int _nextRequest = 0;
  int _searchEpoch = 0;
  String? searchSource;
  Object? _searchKey;
  final _searchRequests = <String>{};
  List<BookSource> get enabled => store.enabled;
  BookSource? get discoverySource =>
      store.source(store.selectedSource)?.exploreEnabled == true
      ? store.source(store.selectedSource)
      : enabled.where((s) => s.exploreEnabled).firstOrNull;
  List<SourceExplore> get exploreChoices =>
      _explores[discoverySource?.key] ?? const [];
  String get discoveryTitle =>
      exploreChoices
          .where((e) => e.url == store.selectedExplore)
          .firstOrNull
          ?.title ??
      discoverySource?.name ??
      '发现';

  /// Login can change both scripted discovery choices and protected listings.
  /// Invalidate failed/finished cursors and notify the existing feed listeners.
  void sessionChanged() => _changed();

  void _changed() {
    _revision++;
    for (final id in _accountRequests.toList()) {
      unawaited(cancelAccountRequest(id));
    }
    refreshAccount();
    _cancelExplores();
    unawaited(cancelSearch());
    _searchKey = '';
    _nextSearchSource = 0;
    if (searchSource != null && !enabled.any((s) => s.key == searchSource)) {
      searchSource = null;
    }
    for (final listing in _listings.values) {
      _cancelListing(listing);
    }
    _listings.clear();
    _searchSeen.clear();
    _searchFailed.clear();
    _searchFinished.clear();
    _searchQueries.clear();
    _explores.clear();
    failures.clear();
    _detailWarnings.clear();
    notifyListeners();
  }

  Future<void> selectSearchSource(String? key) async {
    searchSource = key;
    _searchKey = '';
    await cancelSearch();
    notifyListeners();
  }

  Future<void> selectExplore(BookSource source, SourceExplore? explore) =>
      store.select(source.key, explore?.url);
  Future<List<SourceExplore>> explores(BookSource source) async {
    if (_explores[source.key] case final cached?) return cached;
    final revision = _revision;
    return _once('explores:$revision:${source.key}', () async {
      final request = 'source-choices-${++_nextRequest}';
      _exploreRequests.add(request);
      try {
        final raw = await platform.run(source, 'explores', requestId: request);
        if (_disposed || revision != _revision) {
          throw const SourceFailure('书源请求已取消');
        }
        var group = '';
        final values = <SourceExplore>[];
        for (final e in raw as List) {
          final title = '${e['title'] ?? ''}'.trim();
          final url = '${e['url'] ?? ''}'.trim();
          if (url.isEmpty) group = title;
          final style = e['style'];
          final fraction = style is Map
              ? style['layout_flexBasisPercent']
              : null;
          values.add(
            SourceExplore(
              title: title,
              url: url,
              group: '${e['group'] ?? group}',
              columnFraction: fraction is num ? fraction.toDouble() : null,
            ),
          );
        }
        _explores[source.key] = List.unmodifiable(values);
        return _explores[source.key]!;
      } finally {
        _exploreRequests.remove(request);
      }
    });
  }

  void _cancelExplores() {
    final requests = _exploreRequests.toList();
    _exploreRequests.clear();
    for (final request in requests) {
      unawaited(platform.cancel(request));
    }
  }

  Future<void> cancelSearch() async {
    _searchEpoch++;
    final requests = _searchRequests.toList();
    _searchRequests.clear();
    await Future.wait(requests.map(platform.cancel));
  }

  void _cancelListing(_SourceListing listing) {
    listing.cancelled = true;
    for (final id in listing.requests) {
      unawaited(platform.cancel(id));
    }
  }

  void _cancelScope(Object scope) {
    _listings.removeWhere((key, listing) {
      if (key.scope != scope) return false;
      _cancelListing(listing);
      return true;
    });
  }

  _ListingKey _listingKey(
    BookSource source,
    String operation,
    String term,
    Object scope,
  ) => (source: source.key, operation: operation, term: term, scope: scope);

  Future<T> _once<T>(String key, Future<T> Function() action) async {
    if (_pending[key] case final pending?) return await pending as T;
    final future = action();
    _pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  @override
  Future<List<Novel>> list() async => (await browse()).items;
  @override
  Future<List<Novel>> search(String query) async =>
      (await searchPage(query)).items;
  @override
  Future<Novel?> find(int id) async {
    await store.load();
    return store.book(id) ?? legacyBook?.call(id);
  }

  BookSource _source(Novel book) {
    final source = store.source(book.sourceId);
    if (source == null || !source.enabled) {
      throw const SourceFailure('本书尚未关联可用书源，已缓存章节仍可阅读');
    }
    return source;
  }

  @override
  Future<Novel> detail(Novel novel) => _once('detail:${novel.id}', () async {
    final current = store.book(novel.id) ?? novel;
    if (current.sourceId == null) return current;
    final source = _source(current);
    final value = Map<String, dynamic>.from(
      await platform.run(
            source,
            'detail',
            url: current.bookUrl,
            // The selected listing can be newer than a previously parsed
            // detail. Do not feed a polluted stored title back as its own
            // identity evidence on every subsequent request.
            book: {..._book(current), 'name': novel.title},
          )
          as Map,
    );
    value['bookUrl'] = current.bookUrl;
    _detailWarnings[novel.id] = List.unmodifiable([
      for (final message in value['ruleWarnings'] as List? ?? const [])
        if (message is String && message.startsWith('书源')) message,
    ]);
    final full = store.remember(source, value);
    await store.flush();
    return full;
  });
  Map<String, dynamic> _book(Novel book) => {
    ...book.toSnapshot(),
    'name': book.title,
    'author': book.author,
    'kind': book.genre,
    'intro': book.summary,
    'latestChapterTitle': book.lastUpdate,
    'origin': book.sourceId,
    'bookUrl': book.bookUrl,
    'tocUrl': book.tocUrl,
  };
  @override
  Future<List<NovelChapter>> chapters(int id) => _once('toc:$id', () async {
    final book = await find(id);
    if (book == null) throw const SourceFailure('找不到书籍，请重新从书源添加');
    if (book.sourceId == null) {
      if (book.chapters.isNotEmpty) return book.chapters;
      throw const SourceFailure('旧版书籍目录尚未缓存，请导入并关联对应书源');
    }
    final source = _source(book);
    final raw = await platform.run(
      source,
      'toc',
      url: book.tocUrl ?? book.bookUrl,
      book: _book(book),
    );
    return store.rememberChapters(id, [
      for (final c in raw as List) Map<String, dynamic>.from(c),
    ]);
  });
  @override
  Future<String> chapterContent(int novelId, NovelChapter chapter) => _once(
    'body:$novelId:${chapter.id}',
    () async {
      final book = await find(novelId);
      if (book == null) throw const SourceFailure('找不到书籍');
      final source = _source(book);
      final raw = await platform.run(
        source,
        'content',
        url: chapter.url,
        book: _book(book),
        chapter: {
          'title': chapter.title,
          'url': chapter.url,
          'index':
              store.directory(novelId)?.indexWhere((c) => c.id == chapter.id) ??
              0,
          'nextChapterUrl': _nextChapter(novelId, chapter.id),
        },
      );
      final text = '$raw';
      if (text.trim().isEmpty) throw const SourceFailure('正文为空，请检查书源正文规则');
      return text.replaceAllMapped(
        RegExp(r'<!--image-->(.*?)<!--image-->', dotAll: true),
        (m) {
          final locator = sourceImageLocator(
            novelId,
            m[1]!.trim(),
            referrer: chapter.url ?? '',
          );
          return locator == null ? '[插图]' : '<!--image-->$locator<!--image-->';
        },
      );
    },
  );
  String? _nextChapter(int id, int chapter) {
    final chapters = store.directory(id) ?? const <NovelChapter>[];
    final index = chapters.indexWhere((c) => c.id == chapter);
    return index >= 0 && index + 1 < chapters.length
        ? chapters[index + 1].url
        : null;
  }

  @override
  Future<NovelPage> browse({
    NovelSort sort = NovelSort.lastUpdate,
    int page = 1,
    bool refresh = false,
  }) async {
    await store.load();
    final source = discoverySource;
    if (source == null) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    final choices = _explores[source.key] ?? await explores(source);
    final explore =
        choices
            .where((e) => e.url.isNotEmpty && e.url == store.selectedExplore)
            .firstOrNull ??
        choices.where((e) => e.url.isNotEmpty).firstOrNull;
    if (explore == null) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    return _page(source, 'explore', explore.url, page, refresh);
  }

  Future<NovelPage> _page(
    BookSource source,
    String operation,
    String term,
    int page,
    bool refresh, {
    Object? scope,
    bool Function()? current,
  }) async {
    final key = _listingKey(source, operation, term, scope ?? operation);
    if (page == 1) {
      final old = _listings.remove(key);
      if (old != null) _cancelListing(old);
    }
    final listing = _listings.putIfAbsent(key, _SourceListing.new);
    if (listing.ended) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    final ticket = _revision;
    final isSearch =
        (operation == 'search' && scope == null) || scope == 'search';
    void checkCurrent(String request) {
      if (ticket != _revision ||
          listing.cancelled ||
          current?.call() == false ||
          !identical(_listings[key], listing) ||
          (isSearch && !_searchRequests.contains(request))) {
        throw const SourceFailure('书源请求已取消');
      }
    }

    // A duplicate/filtered server page is not the end of a collection. Follow
    // its cursor before publishing, without letting a broken source loop forever.
    for (var attempt = 0; attempt < 8; attempt++) {
      final request = 'source-${++_nextRequest}';
      listing.requests.add(request);
      if (isSearch) _searchRequests.add(request);
      try {
        checkCurrent(request);
        final raw = await platform.run(
          source,
          operation,
          url: listing.nextUrl ?? (operation == 'explore' ? term : null),
          key: operation == 'search' ? term : '',
          page: listing.remotePage + 1,
          requestId: request,
        );
        checkCurrent(request);
        final result = Map<String, dynamic>.from(raw as Map);
        final books = [
          for (final item in result['items'] as List)
            store.remember(source, Map<String, dynamic>.from(item)),
        ];
        final fresh = books.where((b) => listing.seen.add(b.id)).toList();
        listing.remotePage++;
        final pageUrl = result['pageUrl'];
        if (pageUrl is String) listing.visited.add(pageUrl);
        final next = result['nextUrl'];
        listing.nextUrl = next is String && next.isNotEmpty ? next : null;
        listing.ended =
            result['hasMore'] == false ||
            (listing.nextUrl != null &&
                listing.visited.contains(listing.nextUrl));
        if (fresh.isNotEmpty || listing.ended) {
          await store.flush();
          checkCurrent(request);
          failures.remove(source.key);
          return NovelPage(
            items: fresh,
            page: page,
            totalPages: listing.ended ? page : page + 1,
          );
        }
      } finally {
        listing.requests.remove(request);
        _searchRequests.remove(request);
      }
    }
    throw const SourceFailure('连续多个分页没有返回新书目，请检查书源分页规则');
  }

  @override
  Future<NovelPage> searchPage(
    String query, {
    int page = 1,
    bool refresh = false,
  }) => _textSearchPage(query, page: page, refresh: refresh);

  Future<NovelPage> _textSearchPage(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
  }) async {
    final intent = _searchEpoch;
    await store.load();
    if (query.trim().isEmpty) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    final candidates = enabled
        .where(
          (s) =>
              s.searchable && (searchSource == null || s.key == searchSource),
        )
        .toList();
    if (candidates.isEmpty) {
      if (enabled.isNotEmpty) {
        throw SourceFailure(
          searchSource == null
              ? '已启用的书源没有配置搜索规则，请在书源管理中检查搜索地址与规则'
              : '所选书源没有配置搜索规则，请选择可搜索的书源',
        );
      }
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    final variants = await ChineseText.searchVariants(query);
    if (intent != _searchEpoch) throw const SourceFailure('搜索已取消');
    final pattern = BookSearch(query, field: field);
    return _aggregateSearch(
      searchKey: ('text', query, field, searchSource),
      candidates: candidates,
      resolve: (source) async => [
        for (final term in variants)
          (source: source, operation: 'search', term: term),
      ],
      page: page,
      refresh: refresh,
      accept: (book) => pattern.matches(
        title: book.title,
        author: book.author,
        tags: book.genre,
        summary: book.summary,
        id: '${book.id}',
      ),
    );
  }

  Future<NovelPage> _aggregateSearch({
    required Object searchKey,
    required List<BookSource> candidates,
    required Future<List<_SourceQuery>> Function(BookSource) resolve,
    required int page,
    required bool refresh,
    bool Function()? current,
    bool Function(Novel)? accept,
  }) async {
    if (_searchKey != searchKey || page == 1) {
      await cancelSearch();
      _searchKey = searchKey;
      _searchSeen.clear();
      _searchFailed.clear();
      _searchFinished.clear();
      _searchQueries.clear();
      _nextSearchSource = 0;
      _cancelScope('search');
    }
    final epoch = _searchEpoch;
    final results = <NovelPage>[];
    final attempted = <_SourceQuery>{};
    final deferred = <String>{};
    Object? firstError;
    // Round-robin source batches publish a usable first page without waiting
    // for hundreds of imported sources. Each source retains its own page cursor.
    while (true) {
      if (_searchKey != searchKey ||
          epoch != _searchEpoch ||
          current?.call() == false) {
        throw const SourceFailure('搜索已取消');
      }
      final active = <BookSource>[];
      for (var i = 0; i < candidates.length; i++) {
        final source = candidates[(_nextSearchSource + i) % candidates.length];
        if (!_searchFailed.contains(source.key) &&
            !_searchFinished.contains(source.key) &&
            !deferred.contains(source.key)) {
          active.add(source);
        }
      }
      final batch = active.take(3).toList();
      if (batch.isEmpty) break;
      _nextSearchSource =
          (candidates.indexWhere((s) => s.key == batch.last.key) + 1) %
          candidates.length;
      await Future.wait(
        batch.map((source) async {
          _SourceSearchPlan? plan;
          _SourceQuery? query;
          try {
            plan = await _searchQueries.putIfAbsent(
              source.key,
              () async => _SourceSearchPlan(await resolve(source)),
            );
            if (epoch != _searchEpoch ||
                _searchKey != searchKey ||
                current?.call() == false) {
              throw const SourceFailure('搜索已取消');
            }
            query = plan.next(excluding: attempted);
            if (query == null) {
              if (plan.queries.isEmpty) {
                throw const SourceFailure('书源未提供相应的分类或作者作品入口，可从书籍详情进入该书单');
              }
              // Try each spelling once per visible page, not every page of an
              // unrelated catalogue. Remaining cursors stay available to load more.
              deferred.add(source.key);
              return;
            }
            attempted.add(query);
            final sourcePage = (plan.pages[query] ?? 0) + 1;
            final result = await _page(
              source,
              query.operation,
              query.term,
              sourcePage,
              refresh,
              scope: 'search',
              current: current,
            );
            if (epoch != _searchEpoch || _searchKey != searchKey) {
              throw const SourceFailure('搜索已取消');
            }
            results.add(
              NovelPage(
                items: result.items
                    .where((book) => accept?.call(book) ?? true)
                    .where((b) => _searchSeen.add(b.id))
                    .toList(),
                page: result.page,
                totalPages: result.totalPages,
              ),
            );
            plan.pages[query] = sourcePage;
            if (!result.hasMore) plan.ended.add(query);
            if (plan.exhausted) _searchFinished.add(source.key);
          } catch (error) {
            firstError ??= error;
            if (epoch == _searchEpoch && _searchKey == searchKey) {
              if (query != null) plan?.ended.add(query);
              if (query == null || plan!.exhausted) {
                _searchFailed.add(source.key);
              }
              failures[source.key] = sourceErrorMessage(error);
            }
          }
        }),
      );
      if (results.any((r) => r.items.isNotEmpty)) break;
    }
    if (epoch != _searchEpoch || current?.call() == false) {
      throw const SourceFailure('搜索已取消');
    }
    if (results.every((r) => r.items.isEmpty) && firstError != null) {
      throw firstError!;
    }
    final items = [for (final result in results) ...result.items];
    // Source identities stay distinct even when title/author are identical.
    items.sort(
      (a, b) => candidates
          .indexWhere((s) => s.key == a.sourceId)
          .compareTo(candidates.indexWhere((s) => s.key == b.sourceId)),
    );
    return NovelPage(
      items: items,
      page: page,
      totalPages:
          candidates.any(
            (s) =>
                !_searchFailed.contains(s.key) &&
                !_searchFinished.contains(s.key),
          )
          ? page + 1
          : page,
    );
  }

  @override
  Future<NovelPage> searchFilteredPage(
    String query, {
    BookSearchField field = BookSearchField.all,
    int page = 1,
    bool refresh = false,
  }) async {
    if (field == BookSearchField.author) {
      return authorPage(query, page: page, refresh: refresh);
    }
    if (field == BookSearchField.tags) {
      return tagPage(query, page: page, refresh: refresh);
    }
    return _textSearchPage(query, field: field, page: page, refresh: refresh);
  }

  @override
  Future<NovelPage> authorPage(
    String author, {
    int page = 1,
    bool refresh = false,
  }) async {
    return _relatedSearch(author, tag: false, page: page, refresh: refresh);
  }

  @override
  Future<NovelPage> tagPage(
    String tag, {
    int page = 1,
    bool refresh = false,
    bool Function()? current,
  }) async {
    return _relatedSearch(
      tag,
      tag: true,
      page: page,
      refresh: refresh,
      current: current,
    );
  }

  Future<NovelPage> _relatedSearch(
    String label, {
    required bool tag,
    required int page,
    required bool refresh,
    bool Function()? current,
  }) async {
    await store.load();
    await ChineseText.prepare();
    if (label.trim().isEmpty) {
      return NovelPage(items: const [], page: page, totalPages: page);
    }
    return _aggregateSearch(
      searchKey: (tag ? 'tag' : 'author', label, searchSource),
      candidates: enabled
          .where((s) => searchSource == null || s.key == searchSource)
          .toList(),
      page: page,
      refresh: refresh,
      current: current,
      resolve: (source) async {
        String? link(Novel b) => tag
            ? b.tagUrls.entries
                  .where((e) => _labelKey(e.key) == _labelKey(label))
                  .firstOrNull
                  ?.value
            : b.authorUrl;
        final known = store.books
            .where(
              (b) =>
                  b.sourceId == source.key &&
                  (tag
                      ? b.tags.any((t) => _labelKey(t) == _labelKey(label))
                      : sameNovelAuthor(
                          ChineseText.searchKey(b.author),
                          ChineseText.searchKey(label),
                        )),
            )
            .toList();
        String? url = known.map(link).whereType<String>().firstOrNull;
        if (url == null && known.isNotEmpty) {
          url = link(await detail(known.first));
        }
        if (url == null && tag && source.exploreEnabled) {
          final choices = _explores[source.key] ?? await explores(source);
          url = choices
              .where(
                (e) => !e.isHeading && _labelKey(e.title) == _labelKey(label),
              )
              .firstOrNull
              ?.url;
        }
        return [
          if (url != null) (source: source, operation: 'explore', term: url),
        ];
      },
    );
  }

  Future<Uint8List> cover(int id) async {
    final book = await find(id);
    if (book?.coverUrl == null) throw const SourceFailure('暂无封面');
    return platform.image(
      url: book!.coverUrl!,
      source: store.source(book.sourceId),
      sourceKey: book.sourceId,
      referrer: book.bookUrl,
      isCover: true,
      book: _book(book),
      cachedOnly:
          book.sourceId == null || store.source(book.sourceId)?.enabled != true,
    );
  }

  Future<Uint8List> illustration(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri?.scheme != 'source-image') {
      return platform.image(url: raw, cachedOnly: true);
    }
    final book = await find(int.tryParse(uri!.host) ?? 0);
    if (book == null) throw const SourceFailure('插图所属书籍不存在');
    return platform.image(
      url: uri.queryParameters['url'] ?? '',
      source: store.source(book.sourceId),
      sourceKey: book.sourceId,
      referrer: uri.queryParameters['ref'],
      book: _book(book),
      cachedOnly: store.source(book.sourceId)?.enabled != true,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final id in _accountRequests.toList()) {
      unawaited(cancelAccountRequest(id));
    }
    accountChanges.dispose();
    _cancelExplores();
    unawaited(cancelSearch());
    for (final listing in _listings.values) {
      _cancelListing(listing);
    }
    store.removeListener(_changed);
    super.dispose();
  }
}

String _labelKey(String value) => ChineseText.searchKey(
  value,
).replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').toLowerCase();

/// A related view owns its listing cursor and native requests. Searching or
/// opening another author/tag never consumes or cancels this view's pages.
class SourceRelatedCollection {
  SourceRelatedCollection(
    this.repository, {
    required this.origin,
    required this.label,
    this.tag = false,
    Object? scope,
  }) : _scope = scope ?? Object();
  final SourceNovelRepository repository;
  final Novel origin;
  final String label;
  final bool tag;
  final Object _scope;
  String? _url;
  Future<String>? _resolving;
  bool _disposed = false;

  Future<String> _resolve(BookSource source) => _resolving ??=
      (() async {
        await ChineseText.prepare();
        var book = repository.store.book(origin.id) ?? origin;
        String? link(Novel b) => tag
            ? b.tagUrls.entries
                  .where((e) => _labelKey(e.key) == _labelKey(label))
                  .firstOrNull
                  ?.value
            : b.authorUrl;
        var url = link(book);
        if (url == null) {
          book = await repository.detail(book);
          url = link(book);
        }
        if (url == null && tag) {
          final choices =
              repository._explores[source.key] ??
              await repository.explores(source);
          url = choices
              .where(
                (e) => !e.isHeading && _labelKey(e.title) == _labelKey(label),
              )
              .firstOrNull
              ?.url;
        }
        if (url == null || url.isEmpty) {
          throw SourceFailure(
            tag ? '这个书源未提供「$label」的完整标签书单入口' : '这个书源未提供「$label」的完整作者作品入口',
          );
        }
        return _url = url;
      })().catchError((Object e, StackTrace s) {
        _resolving = null;
        Error.throwWithStackTrace(e, s);
      });

  Future<NovelPage> page({
    int page = 1,
    bool refresh = false,
    bool Function()? current,
  }) async {
    if (_disposed || current?.call() == false) {
      throw const SourceFailure('书源请求已取消');
    }
    final source = repository._source(origin);
    final url = _url ?? await _resolve(source);
    if (_disposed || current?.call() == false) {
      throw const SourceFailure('书源请求已取消');
    }
    return repository._page(
      source,
      'explore',
      url,
      page,
      refresh,
      scope: _scope,
      current: () => !_disposed && current?.call() != false,
    );
  }

  void dispose() {
    _disposed = true;
    repository._cancelScope(_scope);
  }
}

String sourceErrorMessage(Object error) => error is SourceFailure
    ? error.message
    : error is FormatException
    ? error.message
    : error is PlatformException
    ? error.message ?? '书源操作未完成'
    : '书源操作未完成，请检查规则与网络后重试';
