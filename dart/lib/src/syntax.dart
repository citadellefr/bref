import 'dart:typed_data';

import 'highlight.dart';
import 'host.dart';
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

  /// The pieces of a block of code, one flag for each [Token].
  static int token(Token t) => 1 << (19 + t.index);

  static const tokens = 31 << 19;

  /// The header of a callout, of this kind.
  static int callout(CalloutKind k) => 1 << 24 | k.index << 25;

  static const callouts = 1 << 24;
}

/// What a callout looks like: its color tells them apart.
enum CalloutKind { note, tip, warning, danger, quote }

final _calloutKinds = {
  for (final k in ['tip', 'hint', 'important', 'success', 'check', 'done']) k: CalloutKind.tip,
  for (final k in ['warning', 'caution', 'attention', 'question', 'help', 'faq']) k: CalloutKind.warning,
  for (final k in ['danger', 'error', 'failure', 'fail', 'missing', 'bug']) k: CalloutKind.danger,
  for (final k in ['quote', 'cite', 'example']) k: CalloutKind.quote,
};

/// A quote opened by `[!kind] title`, which reads as a callout: [start] to
/// [end] of its first line is the `[!kind]` and the spaces after it, [name]
/// what it says.
typedef Callout = ({CalloutKind kind, String name, int start, int end});

final _calloutHead = RegExp(r'^([ \t]*)\[!([A-Za-z][A-Za-z0-9-]*)\][+-]?[ \t]*');

/// The callout [line] opens, the text of the quote starting at column [from].
Callout? calloutOf(String line, int from) {
  final m = _calloutHead.firstMatch(line.substring(from));
  if (m == null) return null;
  final name = m[2]!;
  return (kind: _calloutKinds[name.toLowerCase()] ?? CalloutKind.note, name: name, start: from + m[1]!.length, end: from + m.end);
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

  /// The picture [Swap.text] leads to, once the host gave it; its
  /// description until then.
  picture,

  /// The text of a link to [Swap.text] as the host labels it, once it did.
  label,
}

/// A piece of a line, in its columns, the preview shows otherwise.
typedef Swap = ({int start, int end, SwapKind kind, String text});

/// A line's pieces: [ends] are where each one ends, [marks] what it is.
final class LineSyntax {
  const LineSyntax(this.ends, this.marks, {this.heading = 0, this.block = false, this.callout, this.swaps = const []});

  final List<int> ends;
  final List<int> marks;

  /// The level of the heading the line belongs to, 0 for none.
  final int heading;

  /// Whether the line belongs to a block of code or math, drawn on a
  /// background of its own.
  final bool block;

  /// The kind of callout the line belongs to, if it does.
  final CalloutKind? callout;

  /// What the preview shows otherwise, in order.
  final List<Swap> swaps;

  /// This line of [length] with [runs] of code marked on top of what it is,
  /// the code starting at column [from].
  LineSyntax coded(int length, int from, Iterable<Run> runs) {
    final each = Uint32List(length);
    var at = 0;
    for (var k = 0; k < ends.length; k++) {
      each.fillRange(at, ends[k], marks[k]);
      at = ends[k];
    }
    for (final r in runs) {
      final flag = Mark.token(r.kind);
      for (var c = from + r.start; c < from + r.end; c++) {
        each[c] |= flag;
      }
    }
    final ends2 = <int>[], marks2 = <int>[];
    for (var c = 0; c < length; c++) {
      if (c + 1 == length || each[c + 1] != each[c]) {
        ends2.add(c + 1);
        marks2.add(each[c]);
      }
    }
    return LineSyntax(ends2, marks2, heading: heading, block: block, callout: callout, swaps: swaps);
  }
}

/// Lines longer than this are shown without the marks of their text: they
/// are data pasted rather than prose.
const longLine = 10000;

/// The syntax of [line], which starts at [lo] in the coordinates of [block],
/// the block of the document holding it.
///
/// A line of a callout comes with the [callout] it belongs to; its first line
/// is the [header].
LineSyntax readLine(MdNode block, String line, int lo, {Callout? callout, bool header = false}) {
  final r = _LineReader(line, lo, callout)..visit(block, null);
  if (header) r.header();
  final ends = <int>[], kinds = <int>[];
  final marks = r.marks;
  for (var i = 0; i < marks.length; i++) {
    if (i + 1 == marks.length || marks[i + 1] != marks[i]) {
      ends.add(i + 1);
      kinds.add(marks[i]);
    }
  }
  r.swaps.sort((a, b) => a.start != b.start ? a.start - b.start : (a.end != b.end ? b.end - a.end : a.kind.index - b.kind.index));
  return LineSyntax(ends, kinds, heading: r.heading, block: r.block, callout: callout?.kind, swaps: r.swaps);
}

class _LineReader {
  _LineReader(this.line, this.lo, this.callout)
      : hi = lo + line.length,
        marks = Uint32List(line.length);

  final String line;
  final Callout? callout;
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

  /// The first line of a callout: its title is shown in its color, and its
  /// kind stands for it when it has none.
  void header() {
    final c = callout!;
    final flag = Mark.callout(c.kind);
    final text = c.name.isEmpty ? '' : '${c.name[0].toUpperCase()}${c.name.substring(1)}';
    for (var i = c.start; i < line.length; i++) {
      marks[i] |= flag;
    }
    swaps.add((start: c.start, end: c.end, kind: c.end == line.length ? SwapKind.text : SwapKind.hide, text: text));
  }

  void visit(MdNode n, MdNode? parent) {
    if (!_on(n)) return;
    var flags = 0, markFlags = Mark.markup;
    SwapKind? swap = SwapKind.hide;
    switch (n.kind) {
      case MdKind.quote:
        flags = callout == null ? Mark.quote : 0;
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
        final address = n.form == LinkForm.bare || n.form == LinkForm.angle;
        flags = address ? Mark.url : Mark.link;
        if (!address && n.marks.length > 1 && n.dest.isNotEmpty) {
          final text = (start: n.marks[0].end, end: n.marks[1].start);
          if (text.start >= lo && text.end <= hi && text.start < text.end) _swap(text, SwapKind.label, _uri(n));
        }
      case MdKind.image:
        flags = Mark.link | Mark.image;
        if (n.start >= lo && n.end <= hi && n.dest.isNotEmpty) _swap((start: n.start, end: n.end), SwapKind.picture, _uri(n));
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

  /// Where a link or a picture leads, as the host is asked about it.
  static String _uri(MdNode n) => n.form == LinkForm.wiki ? wikiUri(n.dest).toString() : n.dest;

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
