import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'host.dart';

/// The Markdown of a link: `[@Alice](user:42)`.
String linkMarkdown(String text, Uri uri) {
  text = text.replaceAllMapped(RegExp(r'[\\\[\]*_`<]'), (c) => '\\${c[0]}');
  var dest = uri.toString();
  if (RegExp(r'[\s()<>]').hasMatch(dest)) dest = '<${dest.replaceAll('<', '%3C').replaceAll('>', '%3E')}>';
  return '[$text]($dest)';
}

/// What a trigger being typed proposes, under the line of the caret or over
/// it when there is no room below. [anchor] is the caret, in the
/// coordinates of the overlay.
class MentionMenu extends StatelessWidget {
  const MentionMenu({super.key, required this.anchor, required this.found, required this.chosen, required this.onPick});

  final Rect anchor;
  final List<Mention> found;
  final int chosen;
  final ValueChanged<Mention> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomSingleChildLayout(
      delegate: _Below(anchor),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainer,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, m) in found.indexed)
                  InkWell(
                    canRequestFocus: false,
                    onTap: () => onPick(m),
                    child: Container(
                      color: i == chosen ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          if (m.icon != null) ...[SizedBox.square(dimension: 24, child: m.icon), const SizedBox(width: 10)],
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(m.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (m.detail case final detail?)
                                  Text(
                                    detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Below extends SingleChildLayoutDelegate {
  _Below(this.anchor);

  final Rect anchor;

  static const _gap = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = math.max(anchor.top, constraints.maxHeight - anchor.bottom) - _gap * 2;
    return BoxConstraints.loose(Size(constraints.maxWidth, math.max(0, room)));
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final below = anchor.bottom + _gap + child.height <= size.height || anchor.top < child.height + _gap;
    final x = math.min(math.max(anchor.left, 0.0), math.max(0.0, size.width - child.width));
    return Offset(x, below ? anchor.bottom + _gap : anchor.top - _gap - child.height);
  }

  @override
  bool shouldRelayout(_Below old) => old.anchor != anchor;
}
