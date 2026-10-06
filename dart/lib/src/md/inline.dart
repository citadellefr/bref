import 'block.dart';
import 'entities.dart';
import 'node.dart';

/// Reads the inlines of a leaf block, links resolved by [refs].
List<MdNode> parseInlines(Leaf leaf, Refs refs, int syntax) =>
    InlineParser(leaf.lines, refs, syntax, table: leaf.table).parse();

/// An inline being read, in a list its siblings share, which emphasis and
/// links take nodes out of.
class _Inl {
  _Inl(this.n);

  final MdNode n;
  _Inl? parent, prev, next, first, last;

  void append(_Inl c) {
    c
      ..unlink()
      ..parent = this
      ..prev = last;
    if (last != null) {
      last!.next = c;
    } else {
      first = c;
    }
    last = c;
  }

  void unlink() {
    if (prev != null) {
      prev!.next = next;
    } else if (parent != null) {
      parent!.first = next;
    }
    if (next != null) {
      next!.prev = prev;
    } else if (parent != null) {
      parent!.last = prev;
    }
    parent = prev = next = null;
  }

  void insertAfter(_Inl s) {
    s
      ..unlink()
      ..parent = parent
      ..prev = this
      ..next = next;
    if (next != null) {
      next!.prev = s;
    } else if (parent != null) {
      parent!.last = s;
    }
    next = s;
  }
}

class _Delimiter {
  _Delimiter(this.char, this.count, this.node, this.prev, {required this.canOpen, required this.canClose}) : orig = count;

  final int char;
  int count;
  final int orig;
  final _Inl node;
  _Delimiter? prev, next;
  final bool canOpen, canClose;
}

class _Bracket {
  _Bracket(this.node, this.prev, this.prevDelim, this.index, {required this.image});

  final _Inl node;
  final _Bracket? prev;
  final _Delimiter? prevDelim;
  final int index;
  final bool image;
  bool active = true;
  bool bracketAfter = false;
}

/// Reads the inlines of a leaf block. Its [text] is the content of the
/// block, its lines joined by "\n" and trimmed; offsets in it map back to
/// the source line by line.
class InlineParser {
  InlineParser(this._lines, this._refs, this._syntax, {this.table = false}) {
    final b = StringBuffer();
    var at = 0;
    for (var i = 0; i < _lines.length; i++) {
      final l = _lines[i];
      if (i > 0) {
        b.write('\n');
        at++;
      }
      _starts.add(at);
      b
        ..write(' ' * l.pad)
        ..write(l.line.substring(l.from, l.to));
      at += l.pad + l.to - l.from;
    }
    final text = b.toString();
    var hi = text.length;
    while (hi > 0 && _isTrim(text.codeUnitAt(hi - 1))) {
      hi--;
    }
    while (_lo < hi && _isTrim(text.codeUnitAt(_lo))) {
      _lo++;
    }
    this.text = text.substring(_lo, hi);
  }

  final List<Segment> _lines;
  final Refs _refs;
  final int _syntax;
  final bool table;
  final _starts = <int>[];
  var _lo = 0;
  late final String text;

  int pos = 0;
  _Delimiter? _delims;
  _Bracket? _brackets;

  // what searches found, for runs of openers not to search the rest of the
  // text each
  final _finds = <String, (int, int)>{};
  Map<int, List<int>>? _ticks;
  int _noMath = 0, _mathTo = -1;

  static bool _isTrim(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  bool _ext(int e) => _syntax & e != 0;

  int _lineIndex(int i) {
    var lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= i) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The offset in the source of offset [i] of the text.
  int src(int i) {
    i += _lo;
    final k = _lineIndex(i);
    final l = _lines[k];
    final off = i - _starts[k] - l.pad;
    return off >= 0 ? l.start + off : l.start - 1;
  }

  /// The index of the line holding offset [i] of the text.
  int lineOf(int i) => _lineIndex(i + _lo);

  /// The spans of [a] to [b] of the text, line by line.
  List<Span> _marks(int a, int b) {
    final out = <Span>[];
    while (a < b) {
      var e = text.indexOf('\n', a);
      if (e < 0 || e > b) e = b;
      if (e > a) out.add((start: src(a), end: src(e)));
      a = e + 1;
    }
    return out;
  }

  MdNode _node(MdKind kind, int a, int b) => MdNode(kind, src(a), src(b));

  List<MdNode> parse() {
    final root = _Inl(MdNode(MdKind.document, 0));
    while (pos < text.length) {
      _inline(root);
    }
    _processEmphasis(null);
    var nodes = _children(root);
    if (_ext(MdSyntax.autolinks)) nodes = _splitEmails(nodes);
    for (final n in nodes) {
      n.walk((n) {
        if (n.kind == MdKind.text) n.literal = _literal(n.literal);
        return true;
      });
    }
    return nodes;
  }

  /// The nodes of a list, adjacent texts merged.
  static List<MdNode> _children(_Inl p) {
    final out = <MdNode>[];
    final run = StringBuffer();
    var merging = false;
    void flush() {
      if (merging) out.last.literal = run.toString();
      run.clear();
      merging = false;
    }

    for (var c = p.first; c != null; c = c.next) {
      final n = c.n;
      if (c.first != null) n.children = _children(c);
      if (n.kind == MdKind.text) {
        if (n.literal.isEmpty) continue;
        if (out.isNotEmpty && run.isNotEmpty && out.last.end == n.start) {
          run.write(n.literal);
          merging = true;
          out.last.end = n.end;
          continue;
        }
      }
      flush();
      if (n.kind == MdKind.text) run.write(n.literal);
      out.add(n);
    }
    flush();
    return out;
  }

  _Inl _add(_Inl p, MdNode n) {
    final c = _Inl(n);
    p.append(c);
    return c;
  }

  _Inl _addText(_Inl p, int a, int b) => _add(p, _node(MdKind.text, a, b)..literal = text.substring(a, b));

  static String _literal(String s) => s.replaceAll('\u0000', '\uFFFD');

  void _inline(_Inl p) {
    final c = text.codeUnitAt(pos);
    final ok = switch (c) {
      0x0A => _newline(p),
      0x5C => _backslash(p),
      0x60 => _backticks(p),
      0x2A || 0x5F => _delim(c, p),
      0x7E => _ext(MdSyntax.strike) && _delim(c, p),
      0x3D => _ext(MdSyntax.highlight) && _delim(c, p),
      0x5B => _openBracket(p),
      0x21 => _bang(p),
      0x5D => _closeBracket(p),
      0x3C => _autolink(p) || _htmlTag(p),
      0x26 => _entity(p),
      0x24 => _ext(MdSyntax.math) && _math(p),
      _ => _bareLink(p) || _str(p),
    };
    if (!ok) {
      final n = _isHigh(c) && pos + 1 < text.length && _isLow(text.codeUnitAt(pos + 1)) ? 2 : 1;
      _addText(p, pos, pos + n);
      pos += n;
    }
  }

  bool _special(int c) => switch (c) {
        0x0A || 0x60 || 0x5B || 0x5D || 0x5C || 0x21 || 0x3C || 0x26 || 0x2A || 0x5F => true,
        0x7E => _ext(MdSyntax.strike),
        0x3D => _ext(MdSyntax.highlight),
        0x24 => _ext(MdSyntax.math),
        _ => false,
      };

  bool _str(_Inl p) {
    final start = pos;
    var i = start;
    while (i < text.length && !_special(text.codeUnitAt(i)) && (i == start || !_linkAt(i))) {
      i++;
    }
    if (i == start) return false;
    _addText(p, start, i);
    pos = i;
    return true;
  }

  bool _newline(_Inl p) {
    final at = pos++;
    final n = _node(MdKind.softBreak, at, at);
    final l = p.last;
    if (l != null && l.n.kind == MdKind.text && l.n.literal.endsWith(' ')) {
      final lit = l.n.literal;
      var trimmed = lit.length;
      while (trimmed > 0 && lit.codeUnitAt(trimmed - 1) == 0x20) {
        trimmed--;
      }
      final removed = lit.length - trimmed;
      l.n
        ..literal = lit.substring(0, trimmed)
        ..end -= removed;
      if (removed >= 2) {
        n
          ..kind = MdKind.hardBreak
          ..start = l.n.end
          ..end = l.n.end + removed
          ..mark(l.n.end, l.n.end + removed);
      }
    }
    _add(p, n);
    while (pos < text.length && text.codeUnitAt(pos) == 0x20) {
      pos++;
    }
    return true;
  }

  bool _backslash(_Inl p) {
    final at = pos++;
    if (pos < text.length && text.codeUnitAt(pos) == 0x0A) {
      pos++;
      final n = _node(MdKind.hardBreak, at, at + 1);
      _add(p, n..mark(n.start, n.end));
    } else if (pos < text.length && isEscapable(text.codeUnitAt(pos))) {
      pos++;
      _add(
        p,
        _node(MdKind.escape, at, at + 2)
          ..mark(src(at), src(at + 1))
          ..literal = text[at + 1],
      );
    } else {
      _addText(p, at, at + 1);
    }
    return true;
  }

  bool _backticks(_Inl p) {
    final start = pos;
    while (pos < text.length && text.codeUnitAt(pos) == 0x60) {
      pos++;
    }
    final open = pos;
    final n = open - start;
    final i = _closingTicks(n, open);
    if (i < 0) {
      _addText(p, start, open);
      return true;
    }
    final j = i + n;
    var content = text.substring(open, i).replaceAll('\n', ' ');
    if (content.length > 1 && content.startsWith(' ') && content.endsWith(' ') && content.replaceAll(' ', '').isNotEmpty) {
      content = content.substring(1, content.length - 1);
    }
    if (table) content = content.replaceAll(r'\|', '|');
    _add(
      p,
      _node(MdKind.code, start, j)
        ..mark(src(start), src(open))
        ..mark(src(i), src(j))
        ..literal = _literal(content),
    );
    pos = j;
    return true;
  }

  /// Where the first run of [n] backticks from offset [from] starts, or -1.
  int _closingTicks(int n, int from) {
    final ticks = _ticks ??= _tickRuns();
    final runs = ticks[n];
    if (runs == null) return -1;
    var lo = 0, hi = runs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (runs[mid] < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < runs.length ? runs[lo] : -1;
  }

  Map<int, List<int>> _tickRuns() {
    final ticks = <int, List<int>>{};
    for (var i = 0; i < text.length;) {
      if (text.codeUnitAt(i) != 0x60) {
        i++;
        continue;
      }
      var j = i;
      while (j < text.length && text.codeUnitAt(j) == 0x60) {
        j++;
      }
      (ticks[j - i] ??= []).add(i);
      i = j;
    }
    return ticks;
  }

  /// Where [sub] is first found from offset [from], or -1; offsets only grow
  /// from one call to the next.
  int _find(String sub, int from) {
    final f = _finds[sub];
    if (f != null && from >= f.$1 && (f.$2 < 0 || f.$2 >= from)) return f.$2;
    final at = text.indexOf(sub, from);
    _finds[sub] = (from, at);
    return at;
  }

  /// The character before offset [i], a newline at the start.
  int _codePointBefore(int i) {
    if (i == 0) return 0x0A;
    final c = text.codeUnitAt(i - 1);
    if (_isLow(c) && i >= 2 && _isHigh(text.codeUnitAt(i - 2))) {
      return 0x10000 + ((text.codeUnitAt(i - 2) - 0xD800) << 10) + (c - 0xDC00);
    }
    return c;
  }

  int _codePointAt(int i) {
    if (i >= text.length) return 0x0A;
    return codePointAt(text, i);
  }

  bool _delim(int c, _Inl p) {
    final start = pos;
    while (pos < text.length && text.codeUnitAt(pos) == c) {
      pos++;
    }
    final n = pos - start;
    final before = _codePointBefore(start), after = _codePointAt(pos);
    final afterSpace = isUnicodeSpace(after), afterPunct = isPunct(after);
    final beforeSpace = isUnicodeSpace(before), beforePunct = isPunct(before);
    final left = !afterSpace && (!afterPunct || beforeSpace || beforePunct);
    final right = !beforeSpace && (!beforePunct || afterSpace || afterPunct);
    var canOpen = left, canClose = right;
    if (c == 0x5F) {
      canOpen = left && (!right || beforePunct);
      canClose = right && (!left || afterPunct);
    }
    final node = _addText(p, start, pos);
    final push = (canOpen || canClose) &&
        switch (c) {
          0x7E => n <= 2,
          0x3D => n == 2,
          _ => true,
        };
    if (push) {
      final d = _Delimiter(c, n, node, _delims, canOpen: canOpen, canClose: canClose);
      _delims?.next = d;
      _delims = d;
    }
    return true;
  }

  void _removeDelim(_Delimiter d) {
    d.prev?.next = d.next;
    if (d.next == null) {
      _delims = d.prev;
    } else {
      d.next!.prev = d.prev;
    }
  }

  static int _delimIndex(_Delimiter d) {
    var i = switch (d.char) {
      0x5F => 1,
      0x7E => 2,
      0x3D => 3,
      _ => 0,
    };
    if (d.canOpen) i += 4;
    return i * 3 + d.orig % 3;
  }

  /// Pairs the delimiters above [bottom], as CommonMark asks.
  void _processEmphasis(_Delimiter? bottom) {
    final openersBottom = List<_Delimiter?>.filled(24, bottom);
    var closer = _delims;
    while (closer != null && closer.prev != bottom) {
      closer = closer.prev;
    }
    while (closer != null) {
      final cl = closer;
      if (!cl.canClose) {
        closer = cl.next;
        continue;
      }
      final idx = _delimIndex(cl);
      var opener = cl.prev;
      var found = false;
      while (opener != null && opener != bottom && opener != openersBottom[idx]) {
        final odd = (cl.canOpen || opener.canClose) && cl.orig % 3 != 0 && (opener.orig + cl.orig) % 3 == 0;
        if (opener.char == cl.char && opener.canOpen && !odd) {
          found = true;
          break;
        }
        opener = opener.prev;
      }
      if (!found) {
        closer = cl.next;
      } else if (cl.char == 0x2A || cl.char == 0x5F) {
        final op = opener!;
        final use = cl.count >= 2 && op.count >= 2 ? 2 : 1;
        final oi = op.node, ci = cl.node;
        op.count -= use;
        cl.count -= use;
        oi.n
          ..literal = oi.n.literal.substring(0, oi.n.literal.length - use)
          ..end -= use;
        ci.n
          ..literal = ci.n.literal.substring(use)
          ..start += use;
        final emph = _Inl(
          MdNode(use == 2 ? MdKind.strong : MdKind.emphasis, oi.n.end, ci.n.start)
            ..mark(oi.n.end, oi.n.end + use)
            ..mark(ci.n.start - use, ci.n.start),
        );
        for (var t = oi.next; t != null && t != ci;) {
          final next = t.next;
          emph.append(t);
          t = next;
        }
        oi.insertAfter(emph);
        if (op.next != cl) {
          op.next = cl;
          cl.prev = op;
        }
        if (op.count == 0) {
          oi.unlink();
          _removeDelim(op);
        }
        if (cl.count == 0) {
          ci.unlink();
          closer = cl.next;
          _removeDelim(cl);
        }
      } else {
        final op = opener!;
        final next = cl.next;
        if (op.count == cl.count) {
          final oi = op.node, ci = cl.node;
          final n = _Inl(
            MdNode(cl.char == 0x3D ? MdKind.highlight : MdKind.strike, oi.n.start, ci.n.end)
              ..mark(oi.n.start, oi.n.end)
              ..mark(ci.n.start, ci.n.end),
          );
          for (var t = oi.next; t != null && t != ci;) {
            final next = t.next;
            n.append(t);
            t = next;
          }
          oi.insertAfter(n);
          oi.unlink();
          ci.unlink();
        }
        for (_Delimiter? d = cl; d != null && d != op;) {
          final prev = d.prev;
          _removeDelim(d);
          d = prev;
        }
        _removeDelim(op);
        closer = next;
      }
      if (!found) {
        openersBottom[idx] = cl.prev;
        if (!cl.canOpen) _removeDelim(cl);
      }
    }
    while (_delims != null && _delims != bottom) {
      _removeDelim(_delims!);
    }
  }

  void _addBracket(_Inl node, int index, {required bool image}) {
    _brackets?.bracketAfter = true;
    _brackets = _Bracket(node, _brackets, _delims, index, image: image);
  }

  bool _openBracket(_Inl p) {
    final start = pos;
    if (_ext(MdSyntax.footnotes) && _footnote(p, start)) return true;
    if (_ext(MdSyntax.wiki) && _wiki(p, start, image: false)) return true;
    pos++;
    _addBracket(_addText(p, start, start + 1), start, image: false);
    return true;
  }

  bool _bang(_Inl p) {
    final start = pos;
    if (start + 1 >= text.length || text.codeUnitAt(start + 1) != 0x5B) {
      pos++;
      _addText(p, start, start + 1);
      return true;
    }
    if (_ext(MdSyntax.wiki) && _wiki(p, start, image: true)) return true;
    pos += 2;
    _addBracket(_addText(p, start, start + 2), start + 1, image: true);
    return true;
  }

  /// Reads `[[dest]]`, `[[dest|text]]` and their `![[…]]` embeds, on one line.
  /// Reads `[^label]`, a reference to a footnote that is defined.
  bool _footnote(_Inl p, int start) {
    if (!text.startsWith('[^', start)) return false;
    final close = text.indexOf(']', start);
    if (close < 0) return false;
    final label = text.substring(start + 2, close);
    if (!noteLabel(label) || _refs.notes[normalizeLabel('[$label]')] == null) return false;
    p.append(_Inl(_node(MdKind.footnoteRef, start, close + 1)..label = label));
    pos = close + 1;
    return true;
  }

  bool _wiki(_Inl p, int start, {required bool image}) {
    final from = start + (image ? 3 : 2);
    if (!text.startsWith('[[', from - 2)) return false;
    final end = _find(']]', from);
    if (end < 0) return false;
    final inner = text.substring(from, end);
    if (inner.contains('[') || inner.contains(']') || inner.contains('\n') || _blank(inner)) return false;
    var target = inner, textFrom = from, textTo = end;
    var marks = [(start: src(start), end: src(from)), (start: src(end), end: src(end + 2))];
    final bar = inner.indexOf('|');
    if (bar >= 0) {
      target = inner.substring(0, bar);
      if (_blank(inner.substring(bar + 1))) {
        textTo = from + bar;
        marks = [marks[0], (start: src(from + bar), end: src(end + 2))];
      } else {
        textFrom = from + bar + 1;
        marks = [(start: src(start), end: src(textFrom)), marks[1]];
      }
    }
    final link = _Inl(
      _node(image ? MdKind.image : MdKind.link, start, end + 2)
        ..form = LinkForm.wiki
        ..marks = marks
        ..dest = target.trim()
        ..url = (start: src(from), end: src(from + target.length)),
    )..append(_Inl(_node(MdKind.text, textFrom, textTo)..literal = text.substring(textFrom, textTo)));
    p.append(link);
    if (!image) _deactivateLinks();
    pos = end + 2;
    return true;
  }

  static bool _blank(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c != 0x20 && c != 0x09) return false;
    }
    return true;
  }

  void _deactivateLinks() {
    for (var b = _brackets; b != null; b = b.prev) {
      if (!b.image) b.active = false;
    }
  }

  bool _closeBracket(_Inl p) {
    final closeAt = pos++;
    final after = pos;
    final opener = _brackets;
    if (opener == null) {
      _addText(p, closeAt, after);
      return true;
    }
    if (!opener.active) {
      _addText(p, closeAt, after);
      _brackets = opener.prev;
      return true;
    }
    final link = MdNode(opener.image ? MdKind.image : MdKind.link, 0);
    var matched = false;
    if (pos < text.length && text.codeUnitAt(pos) == 0x28) {
      pos++;
      _spnl();
      final d = _linkDestination();
      if (d != null) {
        _spnl();
        String? title;
        if (_isWhitespace(text.codeUnitAt(pos - 1))) title = _linkTitle();
        _spnl();
        if (pos < text.length && text.codeUnitAt(pos) == 0x29) {
          pos++;
          matched = true;
          link
            ..dest = d.dest
            ..url = (start: src(d.start), end: src(d.end))
            ..title = title ?? '';
        }
      }
      if (!matched) pos = after;
    }
    if (!matched) {
      final before = pos;
      final n = _linkLabel();
      var ref = '';
      if (n > 2) {
        ref = text.substring(before, before + n);
      } else if (!opener.bracketAfter) {
        ref = text.substring(opener.index, after);
      }
      if (n == 0) pos = after;
      if (ref.isNotEmpty) {
        final def = _refs.links[normalizeLabel(ref)];
        if (def != null) {
          matched = true;
          link
            ..form = LinkForm.reference
            ..label = ref.substring(1, ref.length - 1)
            ..dest = def.dest
            ..title = def.title;
        }
      }
    }
    if (!matched) {
      _brackets = opener.prev;
      pos = after;
      _addText(p, closeAt, after);
      return true;
    }
    link
      ..start = opener.node.n.start
      ..end = src(pos)
      ..marks = [(start: opener.node.n.start, end: opener.node.n.end), ..._marks(closeAt, pos)];
    final l = _Inl(link);
    for (var t = opener.node.next; t != null;) {
      final next = t.next;
      l.append(t);
      t = next;
    }
    p.append(l);
    _processEmphasis(opener.prevDelim);
    _brackets = opener.prev;
    opener.node.unlink();
    if (!opener.image) _deactivateLinks();
    return true;
  }

  static bool _isWhitespace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0B || c == 0x0C || c == 0x0D;

  /// Skips spaces, a newline and spaces.
  void _spnl() {
    while (pos < text.length && text.codeUnitAt(pos) == 0x20) {
      pos++;
    }
    if (pos < text.length && text.codeUnitAt(pos) == 0x0A) {
      pos++;
      while (pos < text.length && text.codeUnitAt(pos) == 0x20) {
        pos++;
      }
    }
  }

  /// Reads a destination: what it says, and where it is written.
  ({String dest, int start, int end})? _linkDestination() {
    final t = text;
    final start = pos;
    if (start < t.length && t.codeUnitAt(start) == 0x3C) {
      for (var i = start + 1; i < t.length; i++) {
        switch (t.codeUnitAt(i)) {
          case 0x5C:
            if (i + 1 < t.length && t.codeUnitAt(i + 1) != 0x0A) {
              i++;
            } else {
              return null;
            }
          case 0x3E:
            pos = i + 1;
            return (dest: unescape(t.substring(start + 1, i)), start: start + 1, end: i);
          case 0x3C || 0x0A:
            return null;
        }
      }
      return null;
    }
    var parens = 0;
    var i = start;
    loop:
    while (i < t.length) {
      final c = t.codeUnitAt(i);
      if (c == 0x5C && i + 1 < t.length && isEscapable(t.codeUnitAt(i + 1))) {
        i += 2;
      } else if (c == 0x28) {
        if (++parens > 32) return null;
        i++;
      } else if (c == 0x29) {
        if (parens < 1) break loop;
        i++;
        parens--;
      } else if (_isWhitespace(c)) {
        break;
      } else {
        i++;
      }
    }
    if ((i == start && (i >= t.length || t.codeUnitAt(i) != 0x29)) || parens != 0) return null;
    pos = i;
    return (dest: unescape(t.substring(start, i)), start: start, end: i);
  }

  String? _linkTitle() {
    final t = text;
    if (pos >= t.length) return null;
    final open = t.codeUnitAt(pos);
    final close = switch (open) {
      0x28 => 0x29,
      0x22 || 0x27 => open,
      _ => -1,
    };
    if (close < 0) return null;
    for (var i = pos + 1; i < t.length; i++) {
      final c = t.codeUnitAt(i);
      if (c == 0x5C && i + 1 < t.length) {
        i++;
      } else if (c == close) {
        final title = t.substring(pos + 1, i);
        pos = i + 1;
        return unescape(title);
      } else if ((c == 0x28 && open == 0x28) || c == 0) {
        return null;
      }
    }
    return null;
  }

  /// Reads `[label]` and answers its length, or 0.
  int _linkLabel() {
    final t = text;
    final start = pos;
    if (start >= t.length || t.codeUnitAt(start) != 0x5B) return 0;
    var n = 0;
    for (var i = start + 1; i < t.length; i++) {
      final c = t.codeUnitAt(i);
      if (c == 0x5C) {
        if (i + 1 < t.length) i += _codePointLength(t, i + 1);
      } else if (c == 0x5B) {
        return 0;
      } else if (c == 0x5D) {
        if (n > 999) return 0;
        pos = i + 1;
        return i + 1 - start;
      } else {
        i += _codePointLength(t, i) - 1;
      }
      n++;
    }
    return 0;
  }

  /// Reads the link reference definition at [pos], which it moves past, or
  /// answers null.
  MdNode? definition() {
    final start = pos;
    final n = _linkLabel();
    if (n == 0 || pos >= text.length || text.codeUnitAt(pos) != 0x3A) {
      pos = start;
      return null;
    }
    final label = text.substring(start, start + n);
    pos++;
    _spnl();
    final d = _linkDestination();
    if (d == null) {
      pos = start;
      return null;
    }
    final beforeTitle = pos;
    _spnl();
    String? title;
    if (pos != beforeTitle) title = _linkTitle();
    if (title == null) pos = beforeTitle;
    if (!_lineEnd()) {
      if (title == null) {
        pos = start;
        return null;
      }
      title = null;
      pos = beforeTitle;
      if (!_lineEnd()) {
        pos = start;
        return null;
      }
    }
    if (normalizeLabel(label).isEmpty) {
      pos = start;
      return null;
    }
    var end = pos;
    if (text.codeUnitAt(end - 1) == 0x0A) end--;
    return _node(MdKind.definition, start, end)
      ..marks = _marks(start, start + n + 1)
      ..label = label.substring(1, label.length - 1)
      ..dest = d.dest
      ..title = title ?? ''
      ..url = (start: src(d.start), end: src(d.end));
  }

  /// Skips spaces up to the end of the line, and past it.
  bool _lineEnd() {
    var i = pos;
    while (i < text.length && text.codeUnitAt(i) == 0x20) {
      i++;
    }
    if (i < text.length && text.codeUnitAt(i) != 0x0A) return false;
    if (i < text.length) i++;
    pos = i;
    return true;
  }

  bool _autolink(_Inl p) {
    var mail = true;
    var m = _emailAutolink.matchAsPrefix(text, pos);
    if (m == null) {
      mail = false;
      m = _uriAutolink.matchAsPrefix(text, pos);
      if (m == null) return false;
    }
    final start = pos, end = m.end;
    final dest = text.substring(start + 1, end - 1);
    final link = _Inl(
      _node(MdKind.link, start, end)
        ..form = LinkForm.angle
        ..mark(src(start), src(start + 1))
        ..mark(src(end - 1), src(end))
        ..dest = mail ? 'mailto:$dest' : dest
        ..url = (start: src(start + 1), end: src(end - 1)),
    )..append(_Inl(_node(MdKind.text, start + 1, end - 1)..literal = dest));
    p.append(link);
    pos = end;
    return true;
  }

  bool _htmlTag(_Inl p) {
    var end = -1;
    void closing(String sub, int from) {
      final i = _find(sub, pos + from);
      if (i >= 0) end = i + sub.length;
    }

    if (text.startsWith('<!-->', pos)) {
      end = pos + 5;
    } else if (text.startsWith('<!--->', pos)) {
      end = pos + 6;
    } else if (text.startsWith('<!--', pos)) {
      closing('-->', 4);
    } else if (text.startsWith('<?', pos)) {
      closing('?>', 2);
    } else if (text.startsWith('<![CDATA[', pos)) {
      closing(']]>', 9);
    } else if (pos + 2 < text.length && text.codeUnitAt(pos + 1) == 0x21 && _isAlpha(text.codeUnitAt(pos + 2))) {
      closing('>', 2);
    } else {
      end = _htmlTagPattern.matchAsPrefix(text, pos)?.end ?? -1;
    }
    if (end < 0) return false;
    _add(p, _node(MdKind.inlineHtml, pos, end)..literal = _literal(text.substring(pos, end)));
    pos = end;
    return true;
  }

  bool _entity(_Inl p) {
    final m = _entityRef.matchAsPrefix(text, pos);
    if (m == null) return false;
    final value = decodeEntity(m[0]!);
    if (value == null) return false;
    _add(p, _node(MdKind.entity, pos, m.end)..literal = value);
    pos = m.end;
    return true;
  }

  /// Reads `$math$`, whose dollars hug it, and `$$math$$`, on one line.
  bool _math(_Inl p) {
    final t = text;
    final start = pos;
    var n = 0;
    while (start + n < t.length && t.codeUnitAt(start + n) == 0x24) {
      n++;
    }
    if (n > 2) {
      _addText(p, start, start + n);
      pos += n;
      return true;
    }
    final from = start + n;
    var lineEnd = t.indexOf('\n', from);
    if (lineEnd < 0) lineEnd = t.length;
    var end = -1;
    if (n == 1) {
      if (from >= lineEnd) return false;
      final first = t.codeUnitAt(from);
      if (first == 0x20 || first == 0x09 || (from >= _noMath && from < _mathTo)) return false;
      for (var j = from + 1; j < lineEnd; j++) {
        final c = t.codeUnitAt(j);
        if (c == 0x5C) {
          j++;
          continue;
        }
        final prev = t.codeUnitAt(j - 1);
        if (c == 0x24 && prev != 0x20 && prev != 0x09 && (j + 1 >= t.length || !_isDigit(t.codeUnitAt(j + 1)))) {
          end = j;
          break;
        }
      }
      if (end < 0) {
        _noMath = from;
        _mathTo = lineEnd;
      }
    } else {
      final i = _find(r'$$', from);
      if (i >= 0 && i < lineEnd && !_blank(t.substring(from, i))) end = i;
    }
    if (end < 0) return false;
    _add(
      p,
      _node(MdKind.math, start, end + n)
        ..display = n == 2
        ..mark(src(start), src(from))
        ..mark(src(end), src(end + n))
        ..literal = _literal(t.substring(from, end)),
    );
    pos = end + n;
    return true;
  }

  // the addresses GitHub links without brackets: www.example.com,
  // https://example.com and someone@example.com, outside of link texts

  bool _bareLink(_Inl p) {
    if (!_ext(MdSyntax.autolinks) || _brackets != null) return false;
    final start = pos;
    int end;
    String dest;
    switch (text.codeUnitAt(start)) {
      case 0x77:
        if ((start > 0 && !_wwwBoundary(text.codeUnitAt(start - 1))) || !text.startsWith('www.', start)) return false;
        final domain = _checkDomain(text, start, allowShort: false);
        if (domain == 0) return false;
        end = _autolinkDelim(text, start, _linkExtent(text, start + domain));
        dest = 'http://${text.substring(start, end)}';
      case 0x68 || 0x48 || 0x66 || 0x46:
        if (start > 0 && _isAlpha(text.codeUnitAt(start - 1))) return false;
        final scheme = _schemeLength(text, start);
        if (scheme == 0 || !_validHostChar(text, start + scheme)) return false;
        final domain = _checkDomain(text, start + scheme, allowShort: true);
        if (domain == 0) return false;
        end = _autolinkDelim(text, start, _linkExtent(text, start + scheme + domain));
        if (end <= start + scheme - 3) return false;
        dest = text.substring(start, end);
      default:
        return false;
    }
    if (end == start) return false;
    final link = _Inl(
      _node(MdKind.link, start, end)
        ..form = LinkForm.bare
        ..dest = dest
        ..url = (start: src(start), end: src(end)),
    )..append(_Inl(_node(MdKind.text, start, end)..literal = text.substring(start, end)));
    p.append(link);
    pos = end;
    return true;
  }

  /// Whether a bare link may start at [i], for runs of text to stop there.
  bool _linkAt(int i) {
    if (!_ext(MdSyntax.autolinks) || _brackets != null) return false;
    return switch (text.codeUnitAt(i)) {
      0x77 => _wwwBoundary(text.codeUnitAt(i - 1)) && text.startsWith('www.', i),
      0x68 || 0x48 || 0x66 || 0x46 => !_isAlpha(text.codeUnitAt(i - 1)) && _schemeLength(text, i) > 0,
      _ => false,
    };
  }
}

bool _wwwBoundary(int c) => c == 0x2A || c == 0x5F || c == 0x7E || c == 0x28 || InlineParser._isWhitespace(c);

bool _isAlpha(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isAlnum(int c) => _isAlpha(c) || _isDigit(c);

bool _isHigh(int c) => c >= 0xD800 && c < 0xDC00;

bool _isLow(int c) => c >= 0xDC00 && c < 0xE000;

int _codePointLength(String s, int i) => _isHigh(s.codeUnitAt(i)) && i + 1 < s.length && _isLow(s.codeUnitAt(i + 1)) ? 2 : 1;

/// The code point at [i] of [s].
int codePointAt(String s, int i) {
  final c = s.codeUnitAt(i);
  if (_isHigh(c) && i + 1 < s.length && _isLow(s.codeUnitAt(i + 1))) {
    return 0x10000 + ((c - 0xD800) << 10) + (s.codeUnitAt(i + 1) - 0xDC00);
  }
  return c;
}

int _schemeLength(String s, int at) {
  for (final scheme in const ['http://', 'https://', 'ftp://']) {
    if (s.length - at > scheme.length && s.substring(at, at + scheme.length).toLowerCase() == scheme) return scheme.length;
  }
  return 0;
}

bool _validHostChar(String s, int i) {
  if (i >= s.length) return false;
  final c = codePointAt(s, i);
  return c != 0xFFFD && c != 0x0B && !isUnicodeSpace(c) && !isPunct(c);
}

/// Goes on from [end] up to a space or a "<".
int _linkExtent(String s, int end) {
  while (end < s.length && !InlineParser._isWhitespace(s.codeUnitAt(end)) && s.codeUnitAt(end) != 0x3C) {
    end++;
  }
  return end;
}

/// The length of the domain at [from] of [s], 0 if it has no period while
/// one is needed, or an underscore in its last two parts.
int _checkDomain(String s, int from, {required bool allowShort}) {
  final size = s.length - from;
  var periods = 0, under1 = 0, under2 = 0;
  var i = 1;
  while (i < size - 1) {
    if (s.codeUnitAt(from + i) == 0x5C && i < size - 2) i++;
    final c = s.codeUnitAt(from + i);
    if (c == 0x5F) {
      under2++;
    } else if (c == 0x2E) {
      under1 = under2;
      under2 = 0;
      periods++;
    } else if (c != 0x2D && !_validHostChar(s, from + i)) {
      break;
    }
    i += _codePointLength(s, from + i);
  }
  if ((under1 > 0 || under2 > 0) && periods <= 10) return 0;
  return allowShort || periods > 0 ? i : 0;
}

/// Where a link from [from] to [end] of [s] ends once the punctuation that
/// ends a sentence, unbalanced closing parentheses and a trailing entity are
/// left out.
int _autolinkDelim(String s, int from, int end) {
  var opening = 0, closing = 0;
  for (var i = from; i < end; i++) {
    switch (s.codeUnitAt(i)) {
      case 0x3C:
        end = i;
      case 0x28:
        opening++;
      case 0x29:
        closing++;
    }
  }
  while (end > from) {
    switch (s.codeUnitAt(end - 1)) {
      case 0x29:
        if (closing <= opening) return end;
        closing--;
        end--;
      case 0x3F || 0x21 || 0x2E || 0x2C || 0x3A || 0x2A || 0x5F || 0x7E || 0x27 || 0x22:
        end--;
      case 0x3B:
        var i = end - 2;
        while (i > from && _isAlpha(s.codeUnitAt(i))) {
          i--;
        }
        if (i >= from && i < end - 2 && s.codeUnitAt(i) == 0x26) {
          end = i;
        } else {
          end--;
        }
      default:
        return end;
    }
  }
  return end;
}

/// Links the mail addresses in the texts outside of links.
List<MdNode> _splitEmails(List<MdNode> nodes) {
  final out = <MdNode>[];
  for (final n in nodes) {
    switch (n.kind) {
      case MdKind.link || MdKind.image:
        out.add(n);
      case MdKind.text:
        out.addAll(_emailsIn(n));
      default:
        n.children = _splitEmails(n.children);
        out.add(n);
    }
  }
  return out;
}

List<MdNode> _emailsIn(MdNode t) {
  final data = t.literal;
  final out = <MdNode>[];
  var start = 0, offset = 0;
  next:
  while (offset < data.length - start) {
    final at = data.indexOf('@', start + offset);
    if (at < 0) break;
    var maxRewind = at - start - offset;
    var atPos = at;
    found:
    while (true) {
      var mailto = true, xmpp = false;
      var rewind = 0;
      for (; rewind < maxRewind; rewind++) {
        final c = data.codeUnitAt(atPos - rewind - 1);
        if (_isAlnum(c) || c == 0x2E || c == 0x2B || c == 0x2D || c == 0x5F) continue;
        if (c == 0x3A && _validProtocol('mailto:', data, atPos, rewind, maxRewind)) {
          mailto = false;
          continue;
        }
        if (c == 0x3A && _validProtocol('xmpp:', data, atPos, rewind, maxRewind)) {
          mailto = false;
          xmpp = true;
          continue;
        }
        break;
      }
      if (rewind == 0) {
        offset += maxRewind + 1;
        continue next;
      }
      var linkEnd = 1, periods = 0;
      for (; atPos + linkEnd < data.length; linkEnd++) {
        final c = data.codeUnitAt(atPos + linkEnd);
        if (_isAlnum(c)) continue;
        if (c == 0x40) {
          offset += maxRewind + 1;
          maxRewind = linkEnd - 1;
          atPos = start + offset + maxRewind;
          continue found;
        }
        if (c == 0x2E && atPos + linkEnd + 1 < data.length && _isAlnum(data.codeUnitAt(atPos + linkEnd + 1))) {
          periods++;
        } else if (c == 0x2F && xmpp) {
        } else if (c != 0x2D && c != 0x5F) {
          break;
        }
      }
      final last = data.codeUnitAt(atPos + linkEnd - 1);
      if (linkEnd < 2 || periods == 0 || (!_isAlpha(last) && last != 0x2E)) {
        offset += maxRewind + linkEnd;
        continue next;
      }
      linkEnd = _autolinkDelim(data, atPos, atPos + linkEnd) - atPos;
      if (linkEnd == 0) {
        offset += maxRewind + 1;
        continue next;
      }
      final from = atPos - rewind, to = atPos + linkEnd;
      if (from > start) {
        out.add(MdNode(MdKind.text, t.start + start, t.start + from)..literal = data.substring(start, from));
      }
      final s = (start: t.start + from, end: t.start + to);
      final address = data.substring(from, to);
      out.add(
        MdNode(MdKind.link, s.start, s.end)
          ..form = LinkForm.bare
          ..dest = mailto ? 'mailto:$address' : address
          ..url = s
          ..add(MdNode(MdKind.text, s.start, s.end)..literal = address),
      );
      start = to;
      offset = 0;
      continue next;
    }
  }
  if (start == 0) return [t];
  if (start < data.length) out.add(MdNode(MdKind.text, t.start + start, t.end)..literal = data.substring(start));
  return out;
}

bool _validProtocol(String protocol, String data, int atPos, int rewind, int maxRewind) {
  final n = protocol.length;
  if (n > maxRewind - rewind) return false;
  final from = atPos - rewind - n;
  if (data.substring(from, atPos - rewind) != protocol) return false;
  return n == maxRewind - rewind || !_isAlnum(data.codeUnitAt(from - 1));
}

bool isEscapable(int c) =>
    (c >= 0x21 && c <= 0x2F) || (c >= 0x3A && c <= 0x40) || (c >= 0x5B && c <= 0x60) || (c >= 0x7B && c <= 0x7E);

final _zs = RegExp(r'\p{Zs}', unicode: true);
final _punct = RegExp(r'[\p{P}\p{S}]', unicode: true);

bool isUnicodeSpace(int c) =>
    c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20 || (c > 0x7F && _zs.hasMatch(String.fromCharCode(c)));

bool isPunct(int c) => c < 0x80 ? isEscapable(c) : _punct.hasMatch(String.fromCharCode(c));

/// How labels are compared: without their brackets, trimmed, their spaces
/// collapsed and their case folded.
String normalizeLabel(String s) {
  final words = s.substring(1, s.length - 1).split(RegExp('[ \t\r\n]+')).where((w) => w.isNotEmpty).join(' ');
  final b = StringBuffer();
  for (final r in words.runes) {
    final lower = String.fromCharCode(r).toLowerCase();
    if (lower == 'ı') {
      b.write(lower);
    } else if (lower == 'ß') {
      b.write('SS');
    } else {
      b.write(lower.toUpperCase());
    }
  }
  return b.toString();
}

final _emailAutolink = RegExp(
  "<([a-zA-Z0-9.!#\$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>",
);
final _uriAutolink = RegExp(r'<[A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\x00-\x20]*>');
final _htmlTagPattern = RegExp(tagPattern);
const _entityPattern = '&(?:#[xX][a-fA-F0-9]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});';
final _entityRef = RegExp(_entityPattern);
final _escapeOrRef = RegExp('\\\\[!"#\$%&\'()*+,./:;<=>?@[\\\\\\]^_`{|}~-]|$_entityPattern');

/// The character an entity stands for: unknown names are no entity, and
/// invalid numbers stand for U+FFFD.
String? decodeEntity(String s) {
  if (s.codeUnitAt(1) == 0x23) {
    final hex = s.codeUnitAt(2) == 0x78 || s.codeUnitAt(2) == 0x58;
    final n = int.tryParse(s.substring(hex ? 3 : 2, s.length - 1), radix: hex ? 16 : 10);
    if (n == null || n == 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF)) return '\uFFFD';
    return String.fromCharCode(n);
  }
  return entities[s.substring(1, s.length - 1)];
}

/// Decodes the backslash escapes and entities of a destination, a title or
/// an info string.
String unescape(String s) {
  if (!s.contains(r'\') && !s.contains('&')) return s;
  return s.replaceAllMapped(_escapeOrRef, (m) {
    final t = m[0]!;
    if (t.codeUnitAt(0) == 0x5C) return t.substring(1);
    return decodeEntity(t) ?? t;
  });
}
