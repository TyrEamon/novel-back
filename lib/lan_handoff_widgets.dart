import 'package:flutter/widgets.dart';

import 'catalog.dart';
import 'lan_reading_sync.dart';

/// Placeholder handoff monitor. The unpublished original watched for peer
/// receipts and offered a "continue on this device" notice; this renders only
/// the wrapped child.
class LanHandoffMonitor extends StatelessWidget {
  const LanHandoffMonitor({
    super.key,
    this.handoff,
    this.onContinue,
    this.reduceMotion = false,
    this.noticeWrapper,
    required this.child,
  });

  final LanHandoff? handoff;
  final Object? onContinue;
  final bool reduceMotion;
  final Widget Function(Widget notice)? noticeWrapper;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Placeholder "send this book to a nearby device" sheet.
class LanSendBookSheet extends StatelessWidget {
  const LanSendBookSheet({
    super.key,
    this.sync,
    this.book,
    this.position,
    this.reduceMotion = false,
  });

  final LanReadingSync? sync;
  final Novel? book;
  final Object? position;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}