import 'package:flutter/widgets.dart';

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