import 'dart:typed_data';

import 'md/node.dart';

/// What a piece of a line is, as flags: a piece can be several at once, a
/// strong word in a link for instance.
abstract final class Mark {
  /// The characters of the syntax itself: `**`, `#`, `[`, `](url)`.
  static const markup = 1 << 0;
  static const strong = 1 << 1;
  static const emphasis = 1 << 2;
  static const strike = 1 << 3;
  static const code = 1 << 4;
  static const highlight = 1 << 5;
  static const link = 1 << 6;
  static const url = 1 << 7;
  static const quote = 1 << 8;
  static const listMarker = 1 << 9;
  static const math = 1 << 10;
  static const html = 1 << 11;
  static const heading = 1 << 12;
  static const rule = 1 << 13;
  static const fence = 1 << 14;
  static const image = 1 << 15;
  static const task = 1 << 16;
  static const table = 1 << 17;
  static const frontMatter = 1 << 18;
}

/// What the preview shows in place of a piece of a line.
enum SwapKind {
  /// Nothing: the asterisks of emphasis, the brackets of a link.
  hide,

  /// [Swap.text]: the character of an entity, the bullet of a list.
  text,

  /// The box of a task, open or done.
  box,
  doneBox,

  /// The bar of a quote.
  bar,

  /// A rule across the line.
  rule,

  /// The line folded small, showing [Swap.text]: the fence of a block of
  /// code, the underline of a heading.
  fold,
}

/// A piece of a line, in its columns, the preview shows otherwise.
typedef Swap = ({int start, int end, SwapKind kind, String text});

/// A line's pieces: [ends] are where each one ends, [marks] what it is.
final class LineSyntax {
  const LineSyntax(this.ends, this.marks, {this.heading = 0, this.block = false, this.swaps = const []});

  final List<int> ends;
  final List<int> marks;

  /// The level of the heading the line belongs to, 0 for none.
  final int heading;

  /// Whether the line belongs to a block of code or math, drawn on a
  /// background of its own.
  final bool block;

  /// What the preview shows otherwise, in order.
  final List<Swap> swaps;
}

/// Lines longer than this are shown without the marks of their text: they
/// are data pasted rather than prose.
const longLine = 10000;

/// The syntax of [line], which starts at [lo] in the coordinates of [block],
/// the block of the document holding it.
LineSyntax readLine(MdNode block, String line, int lo) {
  final r = _LineReader(line, lo)..visit(block, null);
  final ends = <int>[], kinds = <int>[];
  final marks = r.marks;
  for (var i = 0; i < marks.length; i++) {
    if (i + 1 == marks.length || marks[i + 1] != marks[i]) {
      ends.add(i + 1);
      kinds.add(marks[i]);
    }
  }
  r.swaps.sort((a, b) => a.start.compareTo(b.start));
  return LineSyntax(ends, kinds, heading: r.heading, block: r.block, swaps: r.swaps);
}

class _LineReader {
  _LineReader(this.line, this.lo)
      : hi = lo + line.length,
        marks = Uint32List(line.length);

  final String line;
  final int lo, hi;
  final Uint32List marks;
  final swaps = <Swap>[];
  var heading = 0;
  var block = false;

  /// Where the line's content starts, after the marks of its quotes and
  /// list items.
  var _content = 0;

  bool _on(MdNode n) => n.end >= lo && n.start <= hi;

  void _set(int start, int end, int flags) {
    final a = (start < lo ? lo : start) - lo, b = (end > hi ? hi : end) - lo;
    for (var i = a; i < b; i++) {
      marks[i] |= flags;
    }
  }

  void _clear(int start, int end, int flags) {
    for (var i = start - lo; i < end - lo; i++) {
      marks[i] &= ~flags;
    }
  }

  void _swap(Span s, SwapKind kind, [String text = '']) =>
      swaps.add((start: s.start - lo, end: s.end - lo, kind: kind, text: text));

  void visit(MdNode n, MdNode? parent) {
    if (!_on(n)) return;
    var flags = 0, markFlags = Mark.markup;
    SwapKind? swap = SwapKind.hide;
    switch (n.kind) {
      case MdKind.quote:
        flags = Mark.quote;
        swap = SwapKind.bar;
      case MdKind.heading:
        flags = Mark.heading;
        heading = n.level;
      case MdKind.codeBlock:
        flags = Mark.code;
        markFlags = Mark.fence | Mark.markup;
        swap = SwapKind.fold;
        block = true;
      case MdKind.mathBlock:
        flags = Mark.math;
        markFlags = Mark.math | Mark.markup;
        swap = SwapKind.fold;
        block = true;
      case MdKind.htmlBlock:
        flags = Mark.html;
      case MdKind.frontMatter:
        flags = Mark.frontMatter;
        markFlags = Mark.frontMatter | Mark.markup;
        swap = null;
      case MdKind.thematicBreak:
        markFlags = Mark.rule | Mark.markup;
        swap = SwapKind.rule;
      case MdKind.table || MdKind.row:
        markFlags = Mark.table | Mark.markup;
        swap = null;
      case MdKind.definition:
        swap = null;
      case MdKind.item:
        _item(n, parent!);
        swap = null;
      case MdKind.emphasis:
        flags = Mark.emphasis;
      case MdKind.strong:
        flags = Mark.strong;
      case MdKind.strike:
        flags = Mark.strike;
      case MdKind.highlight:
        flags = Mark.highlight;
      case MdKind.code:
        flags = Mark.code;
        markFlags = Mark.code | Mark.markup;
      case MdKind.link:
        flags = n.form == LinkForm.bare || n.form == LinkForm.angle ? Mark.url : Mark.link;
      case MdKind.image:
        flags = Mark.link | Mark.image;
      case MdKind.inlineHtml:
        flags = Mark.html;
      case MdKind.math:
        flags = Mark.math;
        markFlags = Mark.math | Mark.markup;
      case MdKind.entity:
        if (n.start >= lo && n.end <= hi) _swap((start: n.start, end: n.end), SwapKind.text, n.literal);
      default:
    }
    final inline = n.kind.index >= MdKind.text.index;
    if (flags != 0) _set(inline ? n.start : (n.start > lo + _content ? n.start : lo + _content), n.end, flags);
    if (n.kind != MdKind.item) {
      for (final m in n.marks) {
        if (m.start < lo || m.end > hi) continue;
        if (inline) _clear(m.start, m.end, flags);
        _set(m.start, m.end, markFlags);
        if (n.kind == MdKind.quote) _content = m.end - lo;
        if (swap == null) continue;
        switch (n.kind) {
          case MdKind.codeBlock || MdKind.mathBlock:
            _swap(m, SwapKind.fold, m.start == n.start ? n.info : '');
          case MdKind.heading when n.start < lo:
            _swap(m, SwapKind.fold);
          default:
            _swap(m, swap);
        }
      }
    }
    if ((n.kind == MdKind.link || n.kind == MdKind.image || n.kind == MdKind.definition) && n.url.end > n.url.start) {
      _set(n.url.start, n.url.end, Mark.url);
    }
    final inlines = n.kind == MdKind.paragraph || n.kind == MdKind.heading || n.kind == MdKind.cell;
    if (inlines && line.length > longLine) return;
    _children(n);
  }

  void _item(MdNode n, MdNode list) {
    for (var k = 0; k < n.marks.length; k++) {
      final m = n.marks[k];
      if (m.start < lo || m.end > hi) continue;
      _content = m.end - lo;
      if (k == 0) {
        _set(m.start, m.end, Mark.listMarker | Mark.markup);
        if (!list.ordered) _swap(m, SwapKind.text, '•');
      } else {
        _set(m.start, m.end, Mark.task | Mark.markup);
        _swap(m, n.task == Task.done ? SwapKind.doneBox : SwapKind.box);
      }
    }
  }

  /// Visits the children of [n] on the line, found by halving: a list may
  /// have thousands of items.
  void _children(MdNode n) {
    final c = n.children;
    var a = 0, b = c.length;
    while (a < b) {
      final mid = (a + b) >> 1;
      if (c[mid].end < lo) {
        a = mid + 1;
      } else {
        b = mid;
      }
    }
    for (var i = a; i < c.length && c[i].start <= hi; i++) {
      visit(c[i], n);
    }
  }
}
