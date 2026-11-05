import 'book_source.dart';

/// Only safe, host-owned account metadata crosses the platform boundary.
class SourceAccountStatus {
  const SourceAccountStatus({
    this.status = 'none',
    this.hasSession = false,
    this.loginAvailable = false,
    this.canVerify = false,
    this.canSync = false,
    this.canCheckIn = false,
    this.checkedInToday = false,
    this.configurationError = false,
    this.checkedAt,
  });
  factory SourceAccountStatus.fromMap(Map<dynamic, dynamic> value) {
    final capabilities = value['capabilities'] as Map? ?? const {};
    return SourceAccountStatus(
      status: '${value['status'] ?? 'none'}',
      hasSession: value['hasSession'] == true,
      loginAvailable: value['loginAvailable'] == true,
      canVerify: capabilities['verify'] == true,
      canSync: capabilities['shelf'] == true,
      canCheckIn: capabilities['checkIn'] == true,
      checkedInToday: value['checkedInToday'] == true,
      configurationError: value['configurationError'] == true,
      checkedAt: value['checkedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (value['checkedAt'] as num).toInt(),
            )
          : null,
    );
  }
  final String status;
  final bool hasSession;
  final bool loginAvailable, canVerify, canSync, canCheckIn;
  final bool checkedInToday, configurationError;
  final DateTime? checkedAt;

  /// True when blocks gated behind a login have a session worth using. A
  /// session the source has already rejected does not count, so a stale cookie
  /// does not keep firing requests that are known to bounce.
  bool get signedIn => hasSession && status != 'signedOut';
  String get label => switch (status) {
    'verified' => '已验证登录',
    'signedOut' => '登录已失效',
    'saved' => '已保存会话',
    'unchecked' => '待验证登录',
    'error' => '验证未完成',
    _ => loginAvailable || canVerify ? '未登录' : '未提供登录',
  };
  String? get explanation => configurationError
      ? '账号扩展规则不完整，请编辑书源检查。'
      : switch (status) {
          'saved' => '本机会话已保存${canVerify ? '，可验证是否仍有效。' : '；书源未提供独立登录验证。'}',
          'unchecked' => '登录操作已结束${canVerify ? '，请验证当前状态。' : '；书源未提供独立登录验证。'}',
          'signedOut' => '书源未接受当前登录，请重新登录。',
          'error' => '暂未确认登录状态，可稍后重新验证。',
          'verified' => checkedAt == null ? null : '最近验证 ${_time(checkedAt!)}',
          _ => null,
        };
  static String _time(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

bool sourceCanVerifyAccount(BookSource source) {
  final rules = source.data['ruleAccount'];
  if (rules is! Map || rules['verify'] is! Map) return false;
  final verify = rules['verify'] as Map;
  return verify['url'] is String &&
      (verify['url'] as String).isNotEmpty &&
      verify['loggedIn'] is String &&
      (verify['loggedIn'] as String).isNotEmpty;
}

bool sourceCanReadProfile(BookSource source) {
  final rules = source.data['ruleAccount'];
  if (rules is! Map) return false;
  final profile = rules['profile'];
  if (profile is! Map) return false;
  return profile['url'] is String && profile['name'] is String;
}

/// What the source's own profile rules read off the signed-in account page.
/// Presenting these values is the whole point of the account card, so they stay
/// plain strings/ints rather than raw rule output.
class SourceAccountProfile {
  const SourceAccountProfile({
    required this.id,
    required this.username,
    this.nickname = '',
    this.rank = '',
    this.score = 0,
    this.experience = 0,
    this.avatarUrl = '',
  });
  factory SourceAccountProfile.fromMap(Map<dynamic, dynamic> value) {
    String text(String key) => '${value[key] ?? ''}'.trim();
    int number(String key) {
      final raw = value[key];
      if (raw is num) return raw.toInt();
      final digits = RegExp(r'\d+').firstMatch('${raw ?? ''}')?.group(0);
      return int.tryParse(digits ?? '') ?? 0;
    }

    return SourceAccountProfile(
      id: number('id'),
      username: text('name'),
      nickname: text('nickname'),
      rank: text('rank'),
      score: number('score'),
      experience: number('experience'),
      avatarUrl: text('avatar'),
    );
  }
  final int id, score, experience;
  final String username, nickname, rank, avatarUrl;
  String get displayName => nickname.isEmpty ? username : nickname;
}
