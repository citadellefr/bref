import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'host.dart';
import 'strings.dart';

/// The Markdown of a link: `[@Alice](user:42)`.
String linkMarkdown(String text, Uri uri) {
  text = text.replaceAllMapped(RegExp(r'[\\\[\]*_`<]'), (c) => '\\${c[0]}');
  var dest = uri.toString();
  if (RegExp(r'[\s()<>]').hasMatch(dest)) dest = '<${dest.replaceAll('<', '%3C').replaceAll('>', '%3E')}>';
  return '[$text]($dest)';
}

/// A row of the menu: what it reads as, and what choosing it does.
@immutable
class Proposal {
  const Proposal(this.text, this.take, {this.detail, this.icon});

  final String text;
  final String? detail;
  final Widget? icon;
  final VoidCallback take;
}

/// The keyword written after an `@`, as [typed] holds it or with what the
/// accents of a keyboard made of it; null when it is none of [commands].
Command? commandIn(List<Command> commands, String typed) {
  final space = typed.indexOf(' ');
  if (space < 0) return null;
  final keyword = _fold(typed.substring(0, space));
  return commands.where((c) => _fold(c.keyword) == keyword).firstOrNull;
}

/// The keywords [typed] starts, all of them for a bare `@`.
Iterable<Command> commandsStarting(List<Command> commands, String typed) {
  final start = _fold(typed);
  return commands.where((c) => _fold(c.keyword).startsWith(start));
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
  'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n',
};

String _fold(String text) => text.toLowerCase().split('').map((c) => _accents[c] ?? c).join();

/// What a trigger being typed proposes, under the line of the caret or over
/// it when there is no room below. [anchor] is the caret, in the
/// coordinates of the overlay.
///
/// Once a keyword is written, the menu is headed by it and by what is
/// [typed] after it: a search, or a question whose answer is on its way
/// while [steps] is not null.
class MentionMenu extends StatelessWidget {
  const MentionMenu({
    super.key,
    required this.anchor,
    required this.found,
    required this.chosen,
    required this.strings,
    this.command,
    this.typed = '',
    this.busy = false,
    this.note,
    this.steps,
    this.onCancel,
  });

  final Rect anchor;
  final List<Proposal> found;
  final int chosen;
  final BrefStrings strings;
  final Command? command;
  final String typed;
  final bool busy;

  /// What to say when there is nothing to choose.
  final String? note;

  /// What the answer on its way said it was doing, the latest last.
  final List<String>? steps;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final command = this.command;
    final steps = this.steps;
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
                if (command != null) _heading(theme, command),
                if (steps != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (steps.isEmpty) Text(strings.thinking, style: muted),
                        for (final (i, step) in steps.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              step,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: i == steps.length - 1 ? theme.textTheme.bodySmall : muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: onCancel, child: Text(strings.cancel)),
                  ),
                ] else if (found.isNotEmpty)
                  for (final (i, p) in found.indexed)
                    InkWell(
                      canRequestFocus: false,
                      onTap: p.take,
                      child: Container(
                        color: i == chosen ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            if (p.icon != null) ...[SizedBox.square(dimension: 24, child: p.icon), const SizedBox(width: 10)],
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(p.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  if (p.detail case final detail?)
                                    Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                else if (note case final note?)
                  Padding(padding: const EdgeInsets.all(12), child: Text(note, style: muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The search or the question as the note holds it.
  Widget _heading(ThemeData theme, Command command) {
    final colors = theme.colorScheme;
    final empty = command.answer == null ? strings.searchIn(command.keyword) : strings.questionFor(command.keyword);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
      child: Row(
        children: [
          Icon(command.icon ?? Icons.alternate_email, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              typed.isEmpty ? empty : typed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: typed.isEmpty ? colors.onSurfaceVariant : null),
            ),
          ),
          if (busy) const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
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
