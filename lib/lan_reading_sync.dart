import 'package:flutter/widgets.dart';

import 'catalog.dart';

/// Placeholder LAN handoff receipt.
class LanHandoffReceipt {
  const LanHandoffReceipt({this.online, this.bookId, this.position});

  final bool? online;
  final Object? bookId;
  final Object? position;
}

/// Placeholder LAN handoff. The unpublished original discovered peers over
/// mDNS and merged reading positions; this records nothing and never resolves.
class LanHandoff {
  LanHandoff();

  LanHandoffReceipt? get received => null;

  Future<({Novel book, dynamic position})> resolveReceipt(
    LanHandoffReceipt receipt,
  ) async => throw const FormatException('局域网续读未启用');

  void dismissReceipt() {}
}

/// Placeholder sync coordinator.
class LanReadingSync {
  LanReadingSync({this.state, this.preferences, this.books, this.repository});

  final Object? state;
  final Object? preferences;
  final Object? books;
  final Object? repository;

  LanHandoff? get handoff => null;

  Future<void> initialize() async {}

  void dispose() {}
}

/// Publishes the LAN coordinator to reader pages.
class LanSyncScope extends InheritedWidget {
  const LanSyncScope({super.key, this.sync, required super.child});

  final LanReadingSync? sync;

  static LanReadingSync? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanSyncScope>()?.sync;

  @override
  bool updateShouldNotify(LanSyncScope oldWidget) => oldWidget.sync != sync;
}