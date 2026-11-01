import 'package:flutter/widgets.dart';

/// Placeholder for the unpublished reading report sheet.
class ReadingReportPage extends StatelessWidget {
  const ReadingReportPage({
    super.key,
    this.state,
    this.repository,
    this.now,
    this.initialRange,
  });

  final Object? state;
  final Object? repository;
  final DateTime? now;
  final Object? initialRange;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}