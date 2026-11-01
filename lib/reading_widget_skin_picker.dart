import 'package:flutter/material.dart';

import 'reading_widget_reference.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

/// Placeholder picker: the published code only needs a selectable list of the
/// skins this build supports, each rendered by the caller's preview builder.
class ReadingWidgetSkinPicker extends StatelessWidget {
  const ReadingWidgetSkinPicker({
    super.key,
    required this.previewBuilder,
    required this.value,
    required this.size,
    required this.snapshot,
    this.onChanged,
  });

  final Widget Function(ReadingWidgetSkin skin) previewBuilder;
  final ReadingWidgetSkin value;
  final ReadingDesktopSize size;
  final ReadingWidgetSnapshot snapshot;
  final ValueChanged<ReadingWidgetSkin>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      for (final skin in ReadingWidgetSkin.values)
        GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(skin),
          child: SizedBox(
            width: 120,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                previewBuilder(skin),
                const SizedBox(height: 6),
                Text(
                  skin.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: skin == value
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}