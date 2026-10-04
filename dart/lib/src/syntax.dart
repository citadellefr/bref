import 'dart:typed_data';

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

/// Where a line stands among the blocks that span several lines: what the
/// line before it left open.
final class BlockState {
  const BlockState._(this.kind, [this.fence = '', this.indent = 0]);

  const BlockState.code(String fence, int indent) : this._(_code, fence, indent);

  static const text = BlockState._(_text);
  static const math = BlockState._(_math);
  static const frontMatter = BlockState._(_frontMatter);

  static const _text = 0, _code = 1, _math = 2, _frontMatter = 3;

  final int kind;

  /// The fence that opened a code block, which only a fence as long of the
  /// same character closes.
  final String fence;
  final int indent;

  @override
  bool operator ==(Object other) =>
      other is BlockState && other.kind == kind && other.fence == fence && other.indent == indent;

  @override
  int get hashCode => Object.hash(kind, fence, indent);
}

/// A line's pieces: [ends] are where each one ends, [marks] what it is.
final class LineSyntax {
  const LineSyntax(this.ends, this.marks, {this.heading = 0, required this.after});

  final List<int> ends;
  final List<int> marks;

  /// The level of the heading the line is, 0 for none.
  final int heading;

  /// What the line leaves open for the next one.
  final BlockState after;
}

/// Lines longer than this are shown without the marks of their text: they
/// are data pasted rather than prose.
const longLine = 10000;

/// What line [index] of a note leaves open, [state] being what the line
/// before left: cheap enough to be read for every line of a long note.
BlockState nextState(String line, int index, BlockState state) {
  switch (state.kind) {
    case BlockState._code:
      return _closes(line, state.fence) ? BlockState.text : state;
    case BlockState._math:
      return line.trim() == r'$$' ? BlockState.text : state;
    case BlockState._frontMatter:
      final t = line.trimRight();
      return t == '---' || t == '...' ? BlockState.text : state;
  }
  if (index == 0 && line.trimRight() == '---') return BlockState.frontMatter;
  final rest = line.substring(_quotes(line));
  final fence = _opening(rest);
  if (fence != null) return BlockState.code(fence[2]!, fence[1]!.length);
  if (rest.trim() == r'$$') return BlockState.math;
  return BlockState.text;
}

/// Reads the marks of line [index] of a note, [state] being what the line
/// before left open.
LineSyntax readLine(String line, int index, BlockState state) {
  final marks = Uint32List(line.length);
  var heading = 0;
  switch (state.kind) {
    case BlockState._code:
      _set(marks, 0, line.length, _closes(line, state.fence) ? Mark.fence | Mark.markup : Mark.code);
    case BlockState._math:
      _set(marks, 0, line.length, line.trim() == r'$$' ? Mark.math | Mark.markup : Mark.math);
    case BlockState._frontMatter:
      final t = line.trimRight();
      _set(marks, 0, line.length, Mark.frontMatter | (t == '---' || t == '...' ? Mark.markup : 0));
    default:
      heading = _block(line, index, marks);
  }
  return _pieces(marks, heading, nextState(line, index, state));
}

LineSyntax _pieces(Uint32List marks, int heading, BlockState after) {
  final ends = <int>[], kinds = <int>[];
  for (var i = 0; i < marks.length; i++) {
    if (i + 1 == marks.length || marks[i + 1] != marks[i]) {
      ends.add(i + 1);
      kinds.add(marks[i]);
    }
  }
  return LineSyntax(ends, kinds, heading: heading, after: after);
}

void _set(Uint32List marks, int start, int end, int mark) {
  for (var i = start; i < end; i++) {
    marks[i] |= mark;
  }
}

final _fenceOpen = RegExp(r'^( {0,3})(`{3,}|~{3,})(.*)$');
final _headingStart = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]|$)');
final _headingEnd = RegExp(r'[ \t]+#+[ \t]*$');
final _rule = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final _quote = RegExp(r' {0,3}>[ \t]?');
final _listItem = RegExp(r'^[ \t]*(?:[-*+]|\d{1,9}[.)])(?:[ \t]+|$)');
final _taskBox = RegExp(r'^\[[ xX]\](?=[ \t]|$)');
final _definition = RegExp(r'^ {0,3}(\[\^?[^\]]+\]):[ \t]*(\S*)');
final _tableDelimiter = RegExp(r'^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$');

/// Where the quote markers starting a line end.
int _quotes(String line) {
  var at = 0;
  while (true) {
    final quote = _quote.matchAsPrefix(line, at);
    if (quote == null) return at;
    at = quote.end;
  }
}

/// The fence opening a code block, if the line is one.
RegExpMatch? _opening(String line) {
  final m = _fenceOpen.firstMatch(line);
  return m == null || (m[2]![0] == '`' && m[3]!.contains('`')) ? null : m;
}

bool _closes(String line, String fence) {
  final m = _fenceOpen.firstMatch(line);
  return m != null && m[2]![0] == fence[0] && m[2]!.length >= fence.length && m[3]!.trim().isEmpty;
}

/// The blocks a line of text starts, then its inlines; answers the level of
/// the heading it is.
int _block(String line, int index, Uint32List marks) {
  if (index == 0 && line.trimRight() == '---') {
    _set(marks, 0, line.length, Mark.frontMatter | Mark.markup);
    return 0;
  }
  var at = _quotes(line);
  if (at > 0) _set(marks, 0, line.length, Mark.quote);
  _set(marks, 0, at, Mark.markup);
  final rest = line.substring(at);

  if (_opening(rest) != null) {
    _set(marks, at, line.length, Mark.fence | Mark.markup);
    return 0;
  }
  if (rest.trim() == r'$$') {
    _set(marks, at, line.length, Mark.math | Mark.markup);
    return 0;
  }
  if (_rule.hasMatch(rest)) {
    _set(marks, at, line.length, Mark.rule | Mark.markup);
    return 0;
  }
  final heading = _headingStart.firstMatch(rest);
  if (heading != null) {
    var end = line.length;
    final closing = _headingEnd.firstMatch(rest);
    if (closing != null && closing.start >= heading.end) {
      end = at + closing.start;
      _set(marks, end, line.length, Mark.markup);
    }
    _set(marks, at, at + heading.end, Mark.markup);
    _set(marks, at, line.length, Mark.heading);
    _inlines(line, at + heading.end, end, marks);
    return heading[1]!.length;
  }
  final definition = _definition.firstMatch(rest);
  if (definition != null) {
    _set(marks, at, at + definition[1]!.length + 1, Mark.markup);
    final url = at + definition.end - definition[2]!.length;
    _set(marks, url, url + definition[2]!.length, Mark.url);
    _inlines(line, at + definition.end, line.length, marks);
    return 0;
  }
  if (rest.contains('|') && _tableDelimiter.hasMatch(rest)) {
    _set(marks, at, line.length, Mark.table | Mark.markup);
    return 0;
  }
  final item = _listItem.firstMatch(rest);
  if (item != null) {
    _set(marks, at, at + item.end, Mark.listMarker | Mark.markup);
    at += item.end;
    final box = _taskBox.firstMatch(line.substring(at));
    if (box != null) {
      _set(marks, at, at + box.end, Mark.task | Mark.markup);
      at += box.end;
    }
  }
  _inlines(line, at, line.length, marks);
  if (rest.trimLeft().startsWith('|')) {
    for (var i = at; i < line.length; i++) {
      if (line.codeUnitAt(i) == _pipe && (i == 0 || line.codeUnitAt(i - 1) != _backslash) && marks[i] & Mark.code == 0) {
        marks[i] |= Mark.table | Mark.markup;
      }
    }
  }
  return 0;
}

const _backslash = 0x5C, _backtick = 0x60, _pipe = 0x7C, _bracketOpen = 0x5B, _bracketClose = 0x5D;
const _parenOpen = 0x28, _parenClose = 0x29, _dollar = 0x24, _bang = 0x21;

bool _punctuation(int c) =>
    (c >= 0x21 && c <= 0x2F) || (c >= 0x3A && c <= 0x40) || (c >= 0x5B && c <= 0x60) || (c >= 0x7B && c <= 0x7E);

bool _space(int c) => c == 0x20 || c == 0x09 || c == 0xA0;

final _urlStart = RegExp(r'(?:https?://|www\.)[^\s<]+', caseSensitive: false);
final _autolink = RegExp(r'<(?:[a-zA-Z][a-zA-Z0-9+.\-]{1,31}:[^\s<>]*|[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+)>');
final _tag = RegExp(r'<(?:/?[a-zA-Z][a-zA-Z0-9\-]*(?:\s[^<>]*)?/?|!--.*?--)>');

/// The inlines between [start] and [end]: code spans first, which nothing
/// else enters, then escapes, links, autolinks, math and emphasis.
void _inlines(String line, int start, int end, Uint32List marks) {
  if (end - start > longLine) return;
  final taken = Uint8List(line.length);
  _codeSpans(line, start, end, marks, taken);
  for (var i = start; i < end; i++) {
    if (taken[i] == 0 && line.codeUnitAt(i) == _backslash && i + 1 < end && _punctuation(line.codeUnitAt(i + 1))) {
      marks[i] |= Mark.markup;
      taken[i] = taken[i + 1] = 1;
      i++;
    }
  }
  _matches(_autolink, line, start, end, taken, (s, e) {
    _set(marks, s, s + 1, Mark.markup);
    _set(marks, s + 1, e - 1, Mark.url);
    _set(marks, e - 1, e, Mark.markup);
    return e;
  });
  _matches(_tag, line, start, end, taken, (s, e) {
    _set(marks, s, e, Mark.html);
    return e;
  });
  _links(line, start, end, marks, taken);
  _matches(_urlStart, line, start, end, taken, (s, e) {
    while (e > s && '.,:;!?*_~\'")'.contains(line[e - 1])) {
      e--;
    }
    _set(marks, s, e, Mark.url);
    return e;
  });
  _inlineMath(line, start, end, marks, taken);
  _emphasis(line, start, end, marks, taken);
}

/// Calls [found] on each match of [pattern] lying on characters nothing
/// took yet, which it then takes up to where [found] says the match ends.
void _matches(RegExp pattern, String line, int start, int end, Uint8List taken, int Function(int, int) found) {
  for (final m in pattern.allMatches(line.substring(0, end), start)) {
    var free = true;
    for (var i = m.start; i < m.end && free; i++) {
      free = taken[i] == 0;
    }
    if (!free) continue;
    _take(taken, m.start, found(m.start, m.end));
  }
}

void _take(Uint8List taken, int start, int end) {
  for (var i = start; i < end; i++) {
    taken[i] = 1;
  }
}

void _codeSpans(String line, int start, int end, Uint32List marks, Uint8List taken) {
  var i = start;
  while (i < end) {
    if (line.codeUnitAt(i) != _backtick || (i > start && line.codeUnitAt(i - 1) == _backslash)) {
      i++;
      continue;
    }
    var n = i;
    while (n < end && line.codeUnitAt(n) == _backtick) {
      n++;
    }
    final run = n - i;
    var j = n;
    int? close;
    while (j < end) {
      if (line.codeUnitAt(j) != _backtick) {
        j++;
        continue;
      }
      var k = j;
      while (k < end && line.codeUnitAt(k) == _backtick) {
        k++;
      }
      if (k - j == run) {
        close = j;
        break;
      }
      j = k;
    }
    if (close == null) {
      i = n;
      continue;
    }
    _set(marks, i, n, Mark.code | Mark.markup);
    _set(marks, n, close, Mark.code);
    _set(marks, close, close + run, Mark.code | Mark.markup);
    _take(taken, i, close + run);
    i = close + run;
  }
}

/// Links, images and wiki links: `[text](url)`, `![alt](url)`, `[[note]]`,
/// `![[note]]`, and `[text][label]`.
void _links(String line, int start, int end, Uint32List marks, Uint8List taken) {
  for (var i = start; i < end; i++) {
    if (taken[i] != 0 || line.codeUnitAt(i) != _bracketOpen) continue;
    final image = i > start && line.codeUnitAt(i - 1) == _bang && taken[i - 1] == 0;
    final open = image ? i - 1 : i;
    if (i + 1 < end && line.codeUnitAt(i + 1) == _bracketOpen) {
      final close = line.indexOf(']]', i + 2);
      if (close > i + 2 && close + 2 <= end && !line.substring(i + 2, close).contains('[')) {
        _set(marks, open, i + 2, Mark.markup);
        _set(marks, i + 2, close, Mark.link | (image ? Mark.image : 0));
        _set(marks, close, close + 2, Mark.markup);
        _take(taken, open, close + 2);
        i = close + 1;
        continue;
      }
    }
    final close = _matching(line, i, end, taken, _bracketOpen, _bracketClose);
    if (close == null || close + 1 >= end) continue;
    final next = line.codeUnitAt(close + 1);
    int? after;
    if (next == _parenOpen) {
      after = _matching(line, close + 1, end, taken, _parenOpen, _parenClose);
    } else if (next == _bracketOpen) {
      after = _matching(line, close + 1, end, taken, _bracketOpen, _bracketClose);
    }
    if (after == null) continue;
    _set(marks, open, i + 1, Mark.markup);
    _set(marks, i + 1, close, Mark.link | (image ? Mark.image : 0));
    _set(marks, close, after + 1, Mark.markup);
    _set(marks, close + 2, after, Mark.url);
    _take(taken, close, after + 1);
    taken[open] = 1;
    if (image) taken[i] = 1;
    // the text of the link is still read for its emphasis
    i = close;
  }
}

/// Where the bracket opened at [open] closes, brackets nested and escaped
/// ones left out.
int? _matching(String line, int open, int end, Uint8List taken, int opening, int closing) {
  var depth = 0;
  for (var i = open; i < end; i++) {
    if (taken[i] != 0) continue;
    final c = line.codeUnitAt(i);
    if (c == opening) {
      depth++;
    } else if (c == closing && --depth == 0) {
      return i;
    }
  }
  return null;
}

/// `$x$` and `$$x$$` within a line: the dollar sign must hug the formula,
/// so that prices are left alone.
void _inlineMath(String line, int start, int end, Uint32List marks, Uint8List taken) {
  var i = start;
  while (i < end) {
    if (taken[i] != 0 || line.codeUnitAt(i) != _dollar) {
      i++;
      continue;
    }
    final run = i + 1 < end && line.codeUnitAt(i + 1) == _dollar ? 2 : 1;
    final from = i + run;
    if (from >= end || _space(line.codeUnitAt(from))) {
      i = from;
      continue;
    }
    var j = from;
    int? close;
    while (j < end) {
      if (taken[j] != 0) break;
      if (line.codeUnitAt(j) == _dollar && !_space(line.codeUnitAt(j - 1)) && line.codeUnitAt(j - 1) != _backslash) {
        if (run == 1 || (j + 1 < end && line.codeUnitAt(j + 1) == _dollar)) close = j;
        break;
      }
      j++;
    }
    if (close == null || close == from) {
      i = from;
      continue;
    }
    _set(marks, i, from, Mark.math | Mark.markup);
    _set(marks, from, close, Mark.math);
    _set(marks, close, close + run, Mark.math | Mark.markup);
    _take(taken, i, close + run);
    i = close + run;
  }
}

/// A run of `*`, `_`, `~` or `=` that may open or close emphasis.
class _Run {
  _Run(this.char, this.start, this.length, {required this.opens, required this.closes});

  final int char;
  int start;
  int length;
  final bool opens, closes;
}

/// Emphasis as CommonMark pairs delimiter runs: a run opens when it is
/// left-flanking, closes when right-flanking, `_` only at word boundaries.
/// `~~` strikes through and `==` highlights.
void _emphasis(String line, int start, int end, Uint32List marks, Uint8List taken) {
  final runs = <_Run>[];
  var i = start;
  while (i < end) {
    final c = line.codeUnitAt(i);
    if (taken[i] != 0 || (c != 0x2A && c != 0x5F && c != 0x7E && c != 0x3D)) {
      i++;
      continue;
    }
    var j = i;
    while (j < end && line.codeUnitAt(j) == c && taken[j] == 0) {
      j++;
    }
    final before = i > 0 ? line.codeUnitAt(i - 1) : 0x20;
    final after = j < line.length ? line.codeUnitAt(j) : 0x20;
    final left = !_space(after) && (!_punctuation(after) || _space(before) || _punctuation(before));
    final right = !_space(before) && (!_punctuation(before) || _space(after) || _punctuation(after));
    var opens = left, closes = right;
    if (c == 0x5F) {
      opens = left && (!right || _punctuation(before));
      closes = right && (!left || _punctuation(after));
    }
    final paired = c == 0x2A || c == 0x5F || j - i == 2;
    if (paired && (opens || closes)) runs.add(_Run(c, i, j - i, opens: opens, closes: closes));
    i = j;
  }
  for (var k = 0; k < runs.length; k++) {
    final closer = runs[k];
    if (!closer.closes) continue;
    for (var o = k - 1; o >= 0 && closer.length > 0; o--) {
      final opener = runs[o];
      if (opener.char != closer.char || !opener.opens || opener.length == 0) continue;
      if ((opener.closes || closer.opens) &&
          (opener.length + closer.length) % 3 == 0 &&
          (opener.length % 3 != 0 || closer.length % 3 != 0) &&
          (closer.char == 0x2A || closer.char == 0x5F)) {
        continue;
      }
      final n = switch (closer.char) {
        0x7E || 0x3D => 2,
        _ => opener.length >= 2 && closer.length >= 2 ? 2 : 1,
      };
      final mark = switch (closer.char) {
        0x7E => Mark.strike,
        0x3D => Mark.highlight,
        _ => n == 2 ? Mark.strong : Mark.emphasis,
      };
      final innerStart = opener.start + opener.length;
      _set(marks, innerStart - n, innerStart, Mark.markup);
      _set(marks, innerStart, closer.start, mark);
      _set(marks, closer.start, closer.start + n, Mark.markup);
      opener.length -= n;
      closer
        ..start += n
        ..length -= n;
      for (var between = o + 1; between < k; between++) {
        runs[between].length = 0;
      }
      if (closer.length > 0) o++;
    }
  }
}
