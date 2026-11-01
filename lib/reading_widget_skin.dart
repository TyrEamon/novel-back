/// Desktop widget skin. The unpublished original shipped a larger set of
/// illustrated faces; only the two referenced by published code are kept here.
enum ReadingWidgetSkin {
  original('原版'),
  seasons('四季');

  const ReadingWidgetSkin(this.label);

  final String label;

  static ReadingWidgetSkin fromId(String? id) => values.firstWhere(
    (value) => value.name == id,
    orElse: () => ReadingWidgetSkin.original,
  );
}

/// Clamp a stored daily goal to a sane minute range.
int readingDailyGoal(int? minutes) => (minutes ?? 0).clamp(0, 24 * 60);

String readingGoalCaption(int goalMinutes, int? verifiedTodaySeconds) {
  final done = (verifiedTodaySeconds ?? 0) ~/ 60;
  return '今日已读 $done 分钟 · 目标 $goalMinutes 分钟';
}