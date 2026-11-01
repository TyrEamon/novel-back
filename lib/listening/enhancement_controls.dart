import 'package:flutter/widgets.dart';

/// Placeholder settings panel. The unpublished original exposed per-effect
/// sliders; this renders nothing so the surrounding sheet stays intact.
class ListeningEnhancementSettings extends StatelessWidget {
  const ListeningEnhancementSettings({
    super.key,
    this.enhancement,
    this.onChanged,
  });

  final Object? enhancement;
  final Object? onChanged;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}