import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'syntax.dart';

/// How a note looks: the style of its text, of each kind of mark, and the
/// colors of selections. [BrefTheme.of] derives it from the app's theme.
@immutable
class BrefTheme {
  const BrefTheme({
    required this.text,
    required this.monospace,
    required this.markup,
    required this.accent,
    required this.muted,
    required this.codeBackground,
    required this.highlight,
    required this.selection,
    required this.caret,
    required this.peers,
    this.headings = const [1.8, 1.5, 1.3, 1.15, 1.05, 1.0],
  });

  factory BrefTheme.of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme.bodyLarge!.copyWith(color: colors.onSurface, height: 1.5);
    return BrefTheme(
      text: text,
      monospace: const TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: ['Menlo', 'Consolas', 'DejaVu Sans Mono', 'Liberation Mono', 'Roboto Mono'],
      ),
      markup: colors.onSurface.withValues(alpha: 0.4),
      accent: colors.primary,
      muted: colors.onSurfaceVariant,
      codeBackground: colors.surfaceContainerHighest,
      highlight: Color.alphaBlend(Colors.amber.withValues(alpha: 0.35), colors.surface),
      selection: colors.primary.withValues(alpha: 0.25),
      caret: colors.primary,
      peers: const [
        Color(0xFFE8590C),
        Color(0xFF2F9E44),
        Color(0xFF7048E8),
        Color(0xFFD6336C),
        Color(0xFF1098AD),
        Color(0xFFF08C00),
        Color(0xFF4263EB),
        Color(0xFF5C940D),
      ],
    );
  }

  final TextStyle text;

  /// Code and math: only the family and its fallbacks are taken.
  final TextStyle monospace;
  final Color markup;
  final Color accent;
  final Color muted;
  final Color codeBackground;
  final Color highlight;
  final Color selection;
  final Color caret;

  /// The colors of the others, by the number of their connection.
  final List<Color> peers;

  /// The size of headings, from level 1 to 6, relative to the text.
  final List<double> headings;

  Color peer(int sid) => peers[sid % peers.length];

  /// The style of a piece of text with these marks, in a heading of this
  /// level or 0.
  TextStyle style(int marks, int heading) {
    var style = text;
    if (heading > 0) {
      style = style.copyWith(
        fontSize: (text.fontSize ?? 16) * headings[heading - 1],
        fontWeight: FontWeight.w700,
        height: 1.3,
      );
    }
    if (marks & (Mark.code | Mark.math | Mark.fence | Mark.frontMatter) != 0) {
      style = style.copyWith(
        fontFamily: monospace.fontFamily,
        fontFamilyFallback: monospace.fontFamilyFallback,
        fontSize: (style.fontSize ?? 16) * 0.9,
      );
    }
    if (marks & Mark.code != 0 && marks & Mark.fence == 0) {
      style = style.copyWith(backgroundColor: codeBackground);
    }
    if (marks & Mark.strong != 0) style = style.copyWith(fontWeight: FontWeight.w700);
    if (marks & Mark.emphasis != 0) style = style.copyWith(fontStyle: FontStyle.italic);
    if (marks & Mark.strike != 0) style = style.copyWith(decoration: TextDecoration.lineThrough);
    if (marks & Mark.highlight != 0) style = style.copyWith(backgroundColor: highlight);
    if (marks & (Mark.quote | Mark.frontMatter) != 0) style = style.copyWith(color: muted);
    if (marks & (Mark.link | Mark.listMarker | Mark.task) != 0) style = style.copyWith(color: accent);
    if (marks & (Mark.url | Mark.math | Mark.html) != 0) style = style.copyWith(color: muted);
    if (marks & Mark.markup != 0 && marks & (Mark.listMarker | Mark.task) == 0) style = style.copyWith(color: markup);
    return style;
  }

  @override
  bool operator ==(Object other) =>
      other is BrefTheme &&
      other.text == text &&
      other.monospace == monospace &&
      other.markup == markup &&
      other.accent == accent &&
      other.muted == muted &&
      other.codeBackground == codeBackground &&
      other.highlight == highlight &&
      other.selection == selection &&
      other.caret == caret &&
      listEquals(other.peers, peers) &&
      listEquals(other.headings, headings);

  @override
  int get hashCode => Object.hash(text, monospace, markup, accent, muted, codeBackground, highlight, selection, caret,
      Object.hashAll(peers), Object.hashAll(headings));
}
