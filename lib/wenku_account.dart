import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'library_state.dart';
import 'online_component.dart';
import 'sources/book_source.dart' show SourceFailure;
import 'sources/source_account.dart';
import 'wenku_shelf_sync.dart' show CloudShelfPlan;

class WenkuProfile {
  const WenkuProfile({
    required this.id,
    required this.username,
    required this.nickname,
    required this.score,
    required this.experience,
    required this.rank,
  });
  final int id, score, experience;
  final String username, nickname, rank;
  String get displayName => nickname.isEmpty ? username : nickname;
}

class CloudBook {
  const CloudBook({
    required this.id,
    this.title = '',
    this.updated = '',
    this.latestChapterId = 0,
    this.latestChapter = '',
  });
  final int id, latestChapterId;
  final String title, updated, latestChapter;
}

class CloudUploadResult {
  const CloudUploadResult(this.uploaded, this.remaining, this.error);
  final List<int> uploaded, remaining;
  final Object? error;
}

/// Domain-facing account state for presentation and local-library integration.
/// No requests, response parsers, service status codes or session material live here.
class WenkuAccount extends ChangeNotifier {
  /// [loadProfile] is the source-backed read of the signed-in account page; it
  /// returns null when the site says nobody is signed in. [signOut] clears the
  /// site session that made that read possible.
  WenkuAccount({
    Future<SourceAccountProfile?> Function()? loadProfile,
    Future<void> Function()? signOut,
    Future<bool> Function(String username, String password)? passwordLogin,
  }) : _loadProfile = loadProfile,
       _signOut = signOut,
       _passwordLogin = passwordLogin;
  final Future<SourceAccountProfile?> Function()? _loadProfile;
  final Future<void> Function()? _signOut;
  final Future<bool> Function(String username, String password)? _passwordLogin;
  Uint8List? avatar;
  String? avatarUrl;
  bool authenticated = false, busy = false, signedToday = false;
  String? operation, error;
  WenkuProfile? profile;
  List<CloudBook>? cloudBooks;
  int? syncedAt;
  int get sessionRevision => 0;
  int get publicationRevision => 0;
  /// The published shell has no cloud API of its own: shelf membership is
  /// merged through the source's rules, so the classic exchange stays off.
  bool get cloudCapable => false;
  static String describeError(Object error) =>
      error is SourceFailure
      ? error.message
      : error is OnlineComponentUnavailable ||
          error is OnlineAuthenticationRequired
      ? error.toString()
      : error is PlatformException && (error.message ?? '').trim().isNotEmpty
      ? error.message!.trim()
      : error is FormatException
      ? error.message.toString()
      : '网络或本地存储暂时异常，请重试';
  Future<void> initialize() => refreshProfile();
  Future<T> _unavailable<T>() async {
    error = OnlineComponentUnavailable.message;
    notifyListeners();
    throw const OnlineComponentUnavailable();
  }

  /// Reads the account page through the source and mirrors what it says. A
  /// signed-out answer is not a failure: the card falls back to its invitation
  /// instead of an error line the reader cannot act on.
  Future<void> refreshProfile() async {
    if (busy) return;
    final load = _loadProfile;
    busy = true;
    operation = 'profile';
    error = null;
    notifyListeners();
    try {
      final loaded = load == null ? null : await load();
      avatar = null;
      avatarUrl = loaded?.avatarUrl;
      authenticated = loaded != null;
      profile = loaded == null
          ? null
          : WenkuProfile(
              id: loaded.id,
              username: loaded.username,
              nickname: loaded.nickname,
              score: loaded.score,
              experience: loaded.experience,
              rank: loaded.rank,
            );
      if (loaded == null) cloudBooks = null;
    } catch (failure) {
      error = describeError(failure);
    } finally {
      busy = false;
      operation = null;
      notifyListeners();
    }
  }

  /// True when a source can carry a password into the site's own login form.
  bool get canPasswordLogin => _passwordLogin != null;

  /// Signs in with the account password. The password is handed to the source
  /// WebView for the one submission and is not kept here or in storage.
  Future<void> signIn(String username, String password) async {
    final login = _passwordLogin;
    if (login == null) return _unavailable<void>();
    if (busy) return;
    busy = true;
    operation = 'login';
    error = null;
    notifyListeners();
    var ok = false;
    try {
      ok = await login(username, password);
      if (!ok) error = '登录未完成，请检查账号与密码';
    } catch (failure) {
      error = describeError(failure);
    } finally {
      busy = false;
      operation = null;
      notifyListeners();
    }
    if (ok) await refreshProfile();
  }

  Future<void> login(String username, String password) => signIn(username, password);
  Future<void> connectPublications(String password) => _unavailable();
  Future<List<CloudBook>> refreshCloud() => _unavailable();
  Future<CloudShelfPlan> exchangeShelf({
    required Set<int> local,
    Set<int>? lastLocal,
    Set<int>? lastCloud,
  }) => _unavailable();
  Future<CloudUploadResult> uploadMissing(Set<int> localIds) => _unavailable();
  Future<void> addCloud(int id) => _unavailable();
  Future<void> removeCloud(int id) => _unavailable();
  Future<void> recommend(int id) => _unavailable();
  Future<void> postReview({
    required int bookId,
    required String title,
    required String content,
  }) => _unavailable();
  Future<void> replyReview({required int threadId, required String content}) =>
      _unavailable();
  Future<int> mergeCloudToLocal(LibraryState state) => _unavailable();
  Future<void> logout() async {
    final signOut = _signOut;
    if (signOut != null) {
      try {
        await signOut();
      } catch (_) {
        // The visible state below is what the reader asked for; a site that
        // refuses to confirm the logout must not keep the card signed in.
      }
    }
    authenticated = false;
    profile = null;
    avatar = null;
    avatarUrl = null;
    cloudBooks = null;
    signedToday = false;
    error = null;
    notifyListeners();
  }
}
