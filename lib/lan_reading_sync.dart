import 'package:flutter/widgets.dart';

/// Placeholder LAN handoff receipt.
class LanHandoffReceipt {
  const LanHandoffReceipt({this.online = false, this.bookId, this.position});

  final bool online;
  final Object? bookId;
  final Object? position;
}

/// Placeholder LAN handoff. The unpublished original discovered peers over
/// mDNS and merged reading positions; this records nothing.
class LanHandoff {
  LanHandoff();

  LanHandoffReceipt? get received => null;

  Future<({Object? book, Object? position})?> resolveReceipt(
    LanHandoffReceipt receipt,
  ) async => null;
}

/// Placeholder sync coordinator.
class LanReadingSync {
  LanReadingSync({this.state, this.preferences, this.books, this.repository});

  final Object? state;
  final Object? preferences;
  final Object? books;
  final Object? repository;

  LanHandoff? get handoff => null;
}

class LanSyncScope extends InheritedWidget {
  const LanSyncScope({super.key, required this.sync, required super.child});

  final LanReadingSync? sync;

  static LanReadingSync? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LanSyncScope>()
      ?.sync;

  @override
  bool updateShouldNotify(LanSyncScope oldWidget) => oldWidget.sync != sync;
}