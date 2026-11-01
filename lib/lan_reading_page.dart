import 'package:flutter/widgets.dart';

import 'lan_reading_sync.dart';

/// Placeholder LAN reading page.
class LanReadingPage extends StatelessWidget {
  const LanReadingPage({super.key, this.sync, this.reduceMotion = false});

  final LanReadingSync? sync;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}