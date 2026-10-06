import 'inline.dart';
import 'node.dart';

/// A line of the content of a leaf block: [from] to [to] of [line], which
/// starts at [base] in the source, after [pad] spaces a partly consumed tab
/// stands for.
class Segment {
  const Segment(this.line, this.base, this.from, this.to, [this.pad = 0]);

  final String line;
  final int base;
  final int from;
  final int to;
  final int pad;

  int get start => base + from;

  int get end => base + to;
}

/// A leaf block whose inlines are read once all definitions are known.
class Leaf {
  const Leaf(this.node, this.lines, {this.table = false});

  final MdNode node;
  final List<Segment> lines;

  /// Whether it is a cell of a table, where `\|` stands for `|` even in
  /// code.
  final bool table;
}

/// Reads a Markdown document, whose lines end with "\n", "\r\n" or "\r".
MdNode parseMarkdown(String src, {int syntax = MdSyntax.bref}) {
  final starts = <int>[], ends = <int>[];
  var start = 0;
  for (var i = 0; i < src.length; i++) {
    final c = src.codeUnitAt(i);
    if (c != 0x0A && c != 0x0D) continue;
    starts.add(start);
    ends.add(i);
    if (c == 0x0D && i + 1 < src.length && src.codeUnitAt(i + 1) == 0x0A) i++;
    start = i + 1;
  }
  if (start < src.length) {
    starts.add(start);
    ends.add(src.length);
  }
  String line(int i) => src.substring(starts[i], ends[i]);

  final p = BlockParser(syntax);
  var i = 0;
  if (syntax & MdSyntax.frontMatter != 0) {
    final matter = readFrontMatter(starts.length, line, (i) => starts[i]);
    if (matter != null) {
      p.doc.add(matter.node);
      i = matter.lines;
    }
  }
  for (; i < starts.length; i++) {
    p.addLine(line(i), starts[i]);
  }
  p.finish();
  final refs = definitionMap(p.definitions);
  for (final leaf in p.leaves) {
    leaf.node.children = parseInlines(leaf, refs, syntax);
  }
  p.doc.end = src.length;
  return p.doc;
}

/// What links and footnote references are resolved against: the definitions
/// and the footnotes by their normalized label, the first of each winning.
class Refs {
  final links = <String, MdNode>{};
  final notes = <String, MdNode>{};
}

/// The [Refs] of [definitions], link definitions and footnotes together.
Refs definitionMap(Iterable<MdNode> definitions) {
  final refs = Refs();
  for (final d in definitions) {
    final map = d.kind == MdKind.footnoteDef ? refs.notes : refs.links;
    map.putIfAbsent(normalizeLabel('[${d.label}]'), () => d);
  }
  return refs;
}

/// The front matter a document of [count] lines starts with: a line of
/// `---`, up to the next line of `---` or `...`; and how many lines it
/// takes.
({MdNode node, int lines})? readFrontMatter(int count, String Function(int) line, int Function(int) start) {
  if (count < 2 || _trimRight(line(0)) != '---') return null;
  for (var k = 1; k < count; k++) {
    final t = _trimRight(line(k));
    if (t != '---' && t != '...') continue;
    final body = StringBuffer();
    for (var i = 1; i < k; i++) {
      body
        ..write(line(i))
        ..write('\n');
    }
    final end = start(k) + line(k).length;
    final node = MdNode(MdKind.frontMatter, 0, end)
      ..mark(0, line(0).length)
      ..mark(start(k), end)
      ..literal = body.toString().replaceAll('\u0000', '\uFFFD');
    return (node: node, lines: k + 1);
  }
  return null;
}

String _trimRight(String s) {
  var end = s.length;
  while (end > 0 && _spaceOrTab(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(0, end);
}

const _codeIndent = 4;
const _tab = 0x09, _space = 0x20;

bool _spaceOrTab(int c) => c == _space || c == _tab;

class _Block {
  _Block(this.node);

  final MdNode node;
  List<Segment> lines = [];

  int markerOffset = 0;
  int padding = 0;

  int fenceChar = 0;
  int fenceLength = 0;
  int fenceOffset = 0;
  int html = 0;

  int columns = 0;
  bool tableTried = false;
}

/// Reads the blocks of a document line by line, as CommonMark does.
class BlockParser {
  BlockParser(this.syntax);

  final int syntax;
  final doc = MdNode(MdKind.document, 0);
  late final _open = [_Block(doc)];

  /// The leaf blocks whose inlines are still to read.
  final leaves = <Leaf>[];

  /// The definitions and the footnotes, in the order of the document.
  final definitions = <MdNode>[];

  String _line = '';
  int _start = 0;
  int _end = 0;
  int _prevEnd = 0;
  int _offset = 0;
  int _column = 0;
  int _nextNonspace = 0;
  int _nextNonspaceColumn = 0;
  int _indent = 0;
  bool _indented = false;
  bool _blank = false;
  bool _partialTab = false;
  int _spaceEnd = -1;
  int _spaceTab = -1;
  bool _allClosed = true;
  int _lastMatched = 0;

  /// Whether every block is closed, or is a heading or a rule the next line
  /// closes: what follows is read alike whatever came before.
  bool get clean =>
      _open.length == 1 ||
      (_open.length == 2 && (_top.node.kind == MdKind.heading || _top.node.kind == MdKind.thematicBreak));

  _Block get _top => _open.last;

  int _peek(int i) => i < _line.length ? _line.codeUnitAt(i) : -1;

  void _findNextNonspace() {
    var i = _offset, cols = _column;
    if (_offset <= _spaceEnd && _offset > _spaceTab) {
      // the spaces up to _spaceEnd were read already, and hold no tab
      cols += _spaceEnd - _offset;
      i = _spaceEnd;
    } else {
      _spaceTab = -1;
      while (i < _line.length) {
        final c = _line.codeUnitAt(i);
        if (c == _space) {
          i++;
          cols++;
        } else if (c == _tab) {
          _spaceTab = i;
          i++;
          cols += 4 - cols % 4;
        } else {
          break;
        }
      }
      _spaceEnd = i;
    }
    _blank = i == _line.length;
    _nextNonspace = i;
    _nextNonspaceColumn = cols;
    _indent = cols - _column;
    _indented = _indent >= _codeIndent;
  }

  void _advanceNextNonspace() {
    _offset = _nextNonspace;
    _column = _nextNonspaceColumn;
    _partialTab = false;
  }

  /// Moves [count] characters, or [count] columns when [columns] is set, a
  /// tab then being partly consumed.
  void _advanceOffset(int count, {required bool columns}) {
    while (count > 0 && _offset < _line.length) {
      if (_line.codeUnitAt(_offset) == _tab) {
        final toTab = 4 - _column % 4;
        if (columns) {
          _partialTab = toTab > count;
          final n = toTab < count ? toTab : count;
          _column += n;
          if (!_partialTab) _offset++;
          count -= n;
        } else {
          _partialTab = false;
          _column += toTab;
          _offset++;
          count--;
        }
      } else {
        _partialTab = false;
        _offset++;
        _column++;
        count--;
      }
    }
  }

  /// Reads [line], which starts at [base] in the source.
  void addLine(String line, int base) {
    _line = line;
    _start = base;
    _end = base + line.length;
    _offset = _column = 0;
    _blank = _partialTab = false;
    _spaceEnd = _spaceTab = -1;
    _lineStarts.add(base);
    final oldTip = _open.length - 1;

    var container = 0;
    while (container + 1 < _open.length) {
      _findNextNonspace();
      final r = _continues(_open[container + 1]);
      if (r == 2) {
        _prevEnd = _end;
        return;
      }
      if (r == 1) break;
      container++;
    }
    _allClosed = container == oldTip;
    _lastMatched = container;

    final kind = _open[container].node.kind;
    var matchedLeaf = kind != MdKind.paragraph && _acceptsLines(kind);
    while (!matchedLeaf) {
      _findNextNonspace();
      if (!_indented && !_maybeSpecial(_peek(_nextNonspace))) {
        _advanceNextNonspace();
        break;
      }
      final r = _blockStart(container);
      if (r == 0) {
        _advanceNextNonspace();
        break;
      }
      container = _open.length - 1;
      matchedLeaf = r == 2;
    }

    if (!_allClosed && !_blank && _top.node.kind == MdKind.paragraph) {
      _addContent(_top);
    } else {
      _closeUnmatched();
      final c = _top;
      if (_acceptsLines(c.node.kind)) {
        _addContent(c);
        if (c.node.kind == MdKind.htmlBlock && c.html >= 1 && c.html <= 5 && _htmlClose[c.html].hasMatch(_line.substring(_offset))) {
          _close(here: true);
        }
      } else if (c.node.kind == MdKind.table) {
        if (_offset < _line.length) _addRow(c);
      } else if (_offset < _line.length && !_blank) {
        _addChild(MdKind.paragraph, _nextNonspace);
        _advanceNextNonspace();
        _addContent(_top);
      }
    }
    _prevEnd = _end;
  }

  static bool _maybeSpecial(int c) => switch (c) {
        0x23 || 0x60 || 0x7E || 0x2A || 0x2B || 0x5F || 0x3D || 0x3C || 0x3E || 0x2D || 0x7C || 0x3A || 0x24 || 0x5B => true,
        _ => c >= 0x30 && c <= 0x39,
      };

  static bool _acceptsLines(MdKind k) =>
      k == MdKind.paragraph || k == MdKind.codeBlock || k == MdKind.htmlBlock || k == MdKind.mathBlock;

  static bool _canContain(MdKind parent, MdKind child) => switch (parent) {
        MdKind.document => child != MdKind.item,
        MdKind.quote || MdKind.item || MdKind.footnoteDef => child != MdKind.item && child != MdKind.footnoteDef,
        MdKind.list => child == MdKind.item,
        _ => false,
      };

  /// Whether an open block goes on on the current line: 0 if it does, 1 if
  /// not, 2 if the line closed it and is done.
  int _continues(_Block b) {
    switch (b.node.kind) {
      case MdKind.quote:
        if (_indented || _peek(_nextNonspace) != 0x3E) return 1;
        final at = _nextNonspace;
        _advanceNextNonspace();
        _advanceOffset(1, columns: false);
        if (_spaceOrTab(_peek(_offset))) _advanceOffset(1, columns: true);
        b.node.mark(_start + at, _start + _offset);
      case MdKind.item:
        if (_indent >= b.markerOffset + b.padding) {
          _advanceOffset(b.markerOffset + b.padding, columns: true);
        } else if (_blank && b.node.children.isNotEmpty) {
          _advanceNextNonspace();
        } else {
          return 1;
        }
      case MdKind.footnoteDef:
        if (_indent >= _codeIndent) {
          _advanceOffset(_codeIndent, columns: true);
        } else if (_blank && b.node.children.isNotEmpty) {
          _advanceNextNonspace();
        } else {
          return 1;
        }
      case MdKind.heading || MdKind.thematicBreak:
        return 1;
      case MdKind.codeBlock:
        if (b.fenceLength == 0) {
          if (_indent >= _codeIndent) {
            _advanceOffset(_codeIndent, columns: true);
          } else if (_blank) {
            _advanceNextNonspace();
          } else {
            return 1;
          }
          return 0;
        }
        if (_indent <= 3 && _peek(_nextNonspace) == b.fenceChar && _closingFence(_line, _nextNonspace, b.fenceChar) >= b.fenceLength) {
          b.node.mark(_start + _nextNonspace, _end);
          _close(here: true);
          return 2;
        }
        _skipFenceOffset(b);
      case MdKind.mathBlock:
        if (_indent <= 3 && _line.startsWith(r'$$', _nextNonspace) && _isBlank(_line, _nextNonspace + 2)) {
          b.node.mark(_start + _nextNonspace, _end);
          _close(here: true);
          return 2;
        }
        _skipFenceOffset(b);
      case MdKind.htmlBlock:
        if (_blank && (b.html == 6 || b.html == 7)) return 1;
      case MdKind.paragraph:
        if (_blank) return 1;
      case MdKind.table:
        if (_blank || splitRow(_line, _nextNonspace).cells.isEmpty) return 1;
      default:
    }
    return 0;
  }

  void _skipFenceOffset(_Block b) {
    for (var i = b.fenceOffset; i > 0 && _spaceOrTab(_peek(_offset)); i--) {
      _advanceOffset(1, columns: true);
    }
  }

  /// Opens the blocks the current line starts: 0 if none, 1 for a
  /// container, 2 for a leaf, after which no other block starts.
  int _blockStart(int container) {
    final c = _open[container];
    final at = _nextNonspace;
    if (!_indented) {
      final first = _line.codeUnitAt(at);
      if (first == 0x3E) {
        _advanceNextNonspace();
        _advanceOffset(1, columns: false);
        if (_spaceOrTab(_peek(_offset))) _advanceOffset(1, columns: true);
        _closeUnmatched();
        _addChild(MdKind.quote, at).node.mark(_start + at, _start + _offset);
        return 1;
      }
      if (first == 0x5B && syntax & MdSyntax.footnotes != 0 && (c.node.kind == MdKind.document || c.node.kind == MdKind.list && container == 1)) {
        final n = _noteMarker(_line, at);
        if (n > 0) {
          _advanceNextNonspace();
          _advanceOffset(n, columns: false);
          _closeUnmatched();
          final b = _addChild(MdKind.footnoteDef, at);
          b.node
            ..label = _line.substring(at + 2, at + n - 2)
            ..mark(_start + at, _start + _offset);
          if (_spaceOrTab(_peek(_offset))) _advanceOffset(1, columns: true);
          definitions.add(b.node);
          return 1;
        }
      }
      if (first == 0x23) {
        final (n, level) = _atxMarker(_line, at);
        if (n > 0) {
          _advanceNextNonspace();
          _advanceOffset(n, columns: false);
          _closeUnmatched();
          final b = _addChild(MdKind.heading, at);
          b.node
            ..level = level
            ..mark(_start + at, _start + _offset);
          var end = _line.length;
          final closing = _atxClosing(_line, _offset);
          if (closing >= 0) {
            b.node.mark(_start + closing, _end);
            end = closing;
          }
          b.lines = [Segment(_line, _start, _offset, end)];
          _advanceOffset(_line.length - _offset, columns: false);
          return 2;
        }
      }
      final fence = _openingFence(_line, at);
      if (fence > 0) {
        _closeUnmatched();
        final b = _addChild(MdKind.codeBlock, at)
          ..fenceChar = first
          ..fenceLength = fence
          ..fenceOffset = _indent;
        b.node.mark(_start + at, _end);
        _advanceNextNonspace();
        _advanceOffset(fence, columns: false);
        return 2;
      }
      if (syntax & MdSyntax.math != 0 && _line.startsWith(r'$$', at) && _isBlank(_line, at + 2)) {
        _closeUnmatched();
        final b = _addChild(MdKind.mathBlock, at)..fenceOffset = _indent;
        b.node.mark(_start + at, _end);
        _advanceOffset(_line.length - _offset, columns: false);
        return 2;
      }
      if (first == 0x3C) {
        final rest = _line.substring(at);
        final lazy = !_allClosed && !_blank && _top.node.kind == MdKind.paragraph;
        for (var kind = 1; kind <= 7; kind++) {
          if (_htmlOpen[kind].hasMatch(rest) && (kind < 7 || (c.node.kind != MdKind.paragraph && !lazy))) {
            _closeUnmatched();
            _addChild(MdKind.htmlBlock, _offset).html = kind;
            return 2;
          }
        }
      }
      if (c.node.kind == MdKind.paragraph) {
        final level = _setextLevel(_line, at);
        if (level > 0) {
          _closeUnmatched();
          _takeDefinitions(c, _open[_open.length - 2].node);
          if (c.lines.isNotEmpty) {
            c.node
              ..kind = MdKind.heading
              ..level = level
              ..start = c.lines.first.start
              ..mark(_start + at, _end);
            _advanceOffset(_line.length - _offset, columns: false);
            return 2;
          }
        }
      }
      if (_thematicBreak(_line, at)) {
        _closeUnmatched();
        _addChild(MdKind.thematicBreak, at).node.mark(_start + at, _end);
        _advanceOffset(_line.length - _offset, columns: false);
        return 2;
      }
    }
    if (!_indented || c.node.kind == MdKind.list) {
      final d = _listMarker(c);
      if (d != null) {
        _closeUnmatched();
        final t = _top.node;
        if (t.kind != MdKind.list || t.ordered != d.ordered || t.marker != d.marker) {
          _addChild(MdKind.list, at).node
            ..ordered = d.ordered
            ..number = d.number
            ..marker = d.marker
            ..tight = true;
        }
        final b = _addChild(MdKind.item, at)
          ..markerOffset = d.markerOffset
          ..padding = d.padding;
        b.node.mark(_start + at, _start + at + d.length);
        if (syntax & MdSyntax.tasks != 0) {
          final task = _taskBox(_line, _offset);
          if (task != Task.none) {
            b.node
              ..task = task
              ..mark(_start + _offset, _start + _offset + 3);
            _advanceOffset(3, columns: false);
          }
        }
        return 1;
      }
    }
    if (_indented && _top.node.kind != MdKind.paragraph && !_blank) {
      _advanceOffset(_codeIndent, columns: true);
      _closeUnmatched();
      _addChild(MdKind.codeBlock, _offset);
      return 2;
    }
    if (syntax & MdSyntax.tables != 0 && !_indented && c.node.kind == MdKind.paragraph && !c.tableTried && _openTable(c)) {
      return 2;
    }
    return 0;
  }

  void _closeUnmatched() {
    if (_allClosed) return;
    while (_open.length - 1 > _lastMatched) {
      _close(here: false);
    }
    _allClosed = true;
  }

  _Block _addChild(MdKind kind, int offset) {
    while (!_canContain(_top.node.kind, kind)) {
      _close(here: false);
    }
    final n = MdNode(kind, _start + offset);
    _top.node.add(n);
    final b = _Block(n);
    _open.add(b);
    return b;
  }

  void _addContent(_Block b) {
    if (_partialTab) {
      _offset++;
      b.lines.add(Segment(_line, _start, _offset, _line.length, 4 - _column % 4));
      return;
    }
    b.lines.add(Segment(_line, _start, _offset, _line.length));
  }

  /// Closes the innermost open block, which ends on the current line when
  /// [here] is set, else on the line before.
  void _close({required bool here}) {
    final b = _open.removeLast();
    final n = b.node..end = here ? _end : _prevEnd;
    switch (n.kind) {
      case MdKind.paragraph:
        _closeParagraph(b, _top.node);
      case MdKind.heading:
        leaves.add(Leaf(n, b.lines));
      case MdKind.codeBlock:
        if (b.fenceLength > 0) {
          n
            ..info = unescape(_trimSpaces(_lineText(b.lines.first)))
            ..literal = _text(b.lines.skip(1));
          break;
        }
        var lines = b.lines;
        while (lines.isNotEmpty && _isBlank(lines.last.line, lines.last.from)) {
          lines = lines.sublist(0, lines.length - 1);
        }
        n
          ..literal = _text(lines)
          ..end = lines.last.end;
      case MdKind.mathBlock:
        n.literal = _text(b.lines.skip(1));
      case MdKind.htmlBlock:
        final text = _text(b.lines);
        n.literal = text.substring(0, text.length - 1);
      case MdKind.list:
        n
          ..tight = _tight(n)
          ..end = n.children.last.end;
      case MdKind.item || MdKind.footnoteDef:
        n.end = n.children.isNotEmpty ? n.children.last.end : n.marks.last.end;
      case MdKind.table:
        n.end = n.children.last.end > n.marks.first.end ? n.children.last.end : n.marks.first.end;
      default:
    }
  }

  /// The content of [lines], each ended by "\n".
  static String _text(Iterable<Segment> lines) {
    final b = StringBuffer();
    for (final l in lines) {
      b
        ..write(_lineText(l))
        ..write('\n');
    }
    return b.toString().replaceAll('\u0000', '\uFFFD');
  }

  static String _lineText(Segment l) => ' ' * l.pad + l.line.substring(l.from, l.to);

  static String _trimSpaces(String s) {
    var a = 0, b = s.length;
    while (a < b && _spaceOrTab(s.codeUnitAt(a))) {
      a++;
    }
    while (b > a && _spaceOrTab(s.codeUnitAt(b - 1))) {
      b--;
    }
    return s.substring(a, b);
  }

  /// Whether no item of a list, nor any of their children, are separated by
  /// a blank line.
  bool _tight(MdNode list) {
    final items = list.children;
    for (var i = 0; i < items.length; i++) {
      if (i + 1 < items.length && _blankBetween(items[i], items[i + 1])) return false;
      final c = items[i].children;
      for (var j = 0; j + 1 < c.length; j++) {
        if (_blankBetween(c[j], c[j + 1])) return false;
      }
    }
    return true;
  }

  /// Whether a line lies between where [a] ends and [b] starts. Only the
  /// lines of blocks still open are at hand: the number of lines between is
  /// told by where each line was read.
  bool _blankBetween(MdNode a, MdNode b) => _lineOf(b.start) - _lineOf(a.end) > 1;

  final _lineStarts = <int>[];

  int _lineOf(int offset) {
    var lo = 0, hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  void _closeParagraph(_Block b, MdNode parent) {
    _takeDefinitions(b, parent);
    if (b.lines.isEmpty) {
      parent.children.remove(b.node);
      return;
    }
    b.node.start = b.lines.first.start;
    leaves.add(Leaf(b.node, b.lines));
  }

  /// Moves the link reference definitions a paragraph starts with out of
  /// it, before it in its parent.
  void _takeDefinitions(_Block b, MdNode parent) {
    if (b.lines.isEmpty) return;
    final first = b.lines.first;
    if (first.from >= first.line.length || first.line.codeUnitAt(first.from) != 0x5B) return;
    final ip = InlineParser(b.lines, Refs(), syntax);
    final defs = <MdNode>[];
    while (ip.pos < ip.text.length && ip.text.codeUnitAt(ip.pos) == 0x5B) {
      final def = ip.definition();
      if (def == null) break;
      defs.add(def);
    }
    if (defs.isEmpty) return;
    b.lines = ip.pos == ip.text.length ? [] : b.lines.sublist(ip.lineOf(ip.pos));
    definitions.addAll(defs);
    final children = parent.children.toList()..insertAll(parent.children.indexOf(b.node), defs);
    parent.children = children;
  }

  /// Closes the blocks still open.
  void finish() {
    while (_open.length > 1) {
      _close(here: false);
    }
  }

  ({bool ordered, String marker, int number, int length, int markerOffset, int padding})? _listMarker(_Block container) {
    if (_indent >= 4) return null;
    final at = _nextNonspace;
    final first = _line.codeUnitAt(at);
    var ordered = false, number = 0, length = 0;
    var marker = '';
    if (first == 0x2A || first == 0x2B || first == 0x2D) {
      marker = _line[at];
      length = 1;
    } else {
      var n = 0;
      while (at + n < _line.length && n < 9) {
        final c = _line.codeUnitAt(at + n);
        if (c < 0x30 || c > 0x39) break;
        number = number * 10 + c - 0x30;
        n++;
      }
      if (n == 0 || at + n >= _line.length) return null;
      final d = _line.codeUnitAt(at + n);
      if (d != 0x2E && d != 0x29) return null;
      if (container.node.kind == MdKind.paragraph && number != 1) return null;
      ordered = true;
      marker = _line[at + n];
      length = n + 1;
    }
    final next = _peek(at + length);
    if (next != -1 && !_spaceOrTab(next)) return null;
    if (container.node.kind == MdKind.paragraph && _isBlank(_line, at + length)) return null;
    final markerOffset = _indent;
    _advanceNextNonspace();
    _advanceOffset(length, columns: true);
    final startColumn = _column, startOffset = _offset, startTab = _partialTab;
    while (true) {
      _advanceOffset(1, columns: true);
      if (_column - startColumn >= 5 || !_spaceOrTab(_peek(_offset))) break;
    }
    final spaces = _column - startColumn;
    int padding;
    if (spaces >= 5 || spaces < 1 || _peek(_offset) == -1) {
      padding = length + 1;
      _column = startColumn;
      _offset = startOffset;
      _partialTab = startTab;
      if (_spaceOrTab(_peek(_offset))) _advanceOffset(1, columns: true);
    } else {
      padding = length + spaces;
    }
    return (ordered: ordered, marker: marker, number: number, length: length, markerOffset: markerOffset, padding: padding);
  }

  // tables

  /// Turns a paragraph into a table when its last line is a row and the
  /// current line the delimiter row under it, with as many cells.
  bool _openTable(_Block c) {
    final at = _nextNonspace;
    if (c.lines.isEmpty || !_delimiterRow(_line, at)) return false;
    final delims = splitRow(_line, at).cells;
    final head = c.lines.last;
    final (:cells, :pipes) = splitRow(head.line.substring(0, head.to), head.from);
    if (cells.length != delims.length) {
      c.tableTried = true;
      return false;
    }
    _closeUnmatched();
    final parent = _open[_open.length - 2].node;
    if (c.lines.length > 1) {
      final before = _Block(MdNode(MdKind.paragraph, c.lines.first.start, c.lines[c.lines.length - 2].end))
        ..lines = c.lines.sublist(0, c.lines.length - 1);
      parent.children = parent.children.toList()..insert(parent.children.indexOf(c.node), before.node);
      _closeParagraph(before, parent);
    }
    final n = c.node
      ..kind = MdKind.table
      ..start = head.start;
    n.align = [
      for (final d in delims)
        switch ((_line.codeUnitAt(d.start) == 0x3A, _line.codeUnitAt(d.end - 1) == 0x3A)) {
          (true, true) => Align.center,
          (true, false) => Align.left,
          (false, true) => Align.right,
          _ => Align.none,
        },
    ];
    c
      ..columns = cells.length
      ..lines = [];
    n
      ..add(_row(head.line, head.base, head.from, head.end, cells, pipes, header: true, columns: c.columns))
      ..mark(_start + at, _end);
    _advanceOffset(_line.length - _offset, columns: false);
    return true;
  }

  void _addRow(_Block c) {
    final (:cells, :pipes) = splitRow(_line, _offset);
    c.node.add(_row(_line, _start, _offset, _end, cells, pipes, header: false, columns: c.columns));
  }

  /// A row of [columns] cells, those missing left empty and those beyond
  /// dropped. [cells] and [pipes] are offsets in [line].
  MdNode _row(String line, int base, int from, int end, List<Span> cells, List<Span> pipes,
      {required bool header, required int columns}) {
    final r = MdNode(MdKind.row, base + from, end)..header = header;
    for (final s in pipes) {
      r.mark(base + s.start, base + s.end);
    }
    for (var i = 0; i < columns; i++) {
      final cell = MdNode(MdKind.cell, end);
      if (i < cells.length) {
        cell
          ..start = base + cells[i].start
          ..end = base + cells[i].end;
        if (cell.start < cell.end) {
          leaves.add(Leaf(cell, [Segment(line, base, cells[i].start, cells[i].end)], table: true));
        }
      }
      r.add(cell);
    }
    return r;
  }

}

/// The cells of the row [s] holds from [from] on, trimmed, and its pipes. A
/// pipe after a backslash belongs to its cell.
({List<Span> cells, List<Span> pipes}) splitRow(String s, int from) {
  final cells = <Span>[], pipes = <Span>[];
  var i = from;
  if (i < s.length && s.codeUnitAt(i) == 0x7C) {
    pipes.add((start: i, end: i + 1));
    i = _skipTableSpaces(s, i + 1);
  }
  while (i < s.length) {
    var j = i;
    while (j < s.length && s.codeUnitAt(j) != 0x7C) {
      if (s.codeUnitAt(j) == 0x5C && j + 1 < s.length && s.codeUnitAt(j + 1) == 0x7C) j++;
      j++;
    }
    var a = i, b = j;
    while (a < b && _tableTrim(s.codeUnitAt(a))) {
      a++;
    }
    while (b > a && _tableTrim(s.codeUnitAt(b - 1))) {
      b--;
    }
    cells.add((start: a, end: b));
    if (j == s.length) break;
    pipes.add((start: j, end: j + 1));
    i = _skipTableSpaces(s, j + 1);
  }
  return (cells: cells, pipes: pipes);
}

/// Whether [s] from [from] on is the row under a table's header: cells of
/// hyphens, a colon at either end telling the alignment.
bool _delimiterRow(String s, int from) {
  var i = from;
  if (s.codeUnitAt(i) == 0x7C) i++;
  while (true) {
    i = _skipTableSpaces(s, i);
    if (i < s.length && s.codeUnitAt(i) == 0x3A) i++;
    var n = 0;
    while (i < s.length && s.codeUnitAt(i) == 0x2D) {
      i++;
      n++;
    }
    if (n == 0) return false;
    if (i < s.length && s.codeUnitAt(i) == 0x3A) i++;
    i = _skipTableSpaces(s, i);
    if (i == s.length) return true;
    if (s.codeUnitAt(i) != 0x7C) return false;
    i = _skipTableSpaces(s, i + 1);
    if (i == s.length) return true;
  }
}

int _skipTableSpaces(String s, int i) {
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c != _space && c != _tab && c != 0x0B && c != 0x0C) break;
    i++;
  }
  return i;
}

bool _tableTrim(int c) => c == _space || c == _tab || c == 0x0A || c == 0x0B || c == 0x0C || c == 0x0D;

/// The length of the `[^label]:` a footnote starts with at [i], or 0.
int _noteMarker(String s, int i) {
  if (!s.startsWith('[^', i)) return 0;
  final end = s.indexOf(']', i);
  if (end < 0 || end + 1 >= s.length || s.codeUnitAt(end + 1) != 0x3A || !noteLabel(s.substring(i + 2, end))) return 0;
  return end + 2 - i;
}

/// Whether [s] may name a footnote: no spaces, no brackets.
bool noteLabel(String s) => s.isNotEmpty && !RegExp(r'[ \t\n\r\[\]^]').hasMatch(s);

Task _taskBox(String s, int i) {
  if (i + 3 > s.length || s.codeUnitAt(i) != 0x5B || s.codeUnitAt(i + 2) != 0x5D) return Task.none;
  if (i + 3 < s.length && !_spaceOrTab(s.codeUnitAt(i + 3))) return Task.none;
  return switch (s.codeUnitAt(i + 1)) {
    _space => Task.open,
    0x78 || 0x58 => Task.done,
    _ => Task.none,
  };
}

bool _isBlank(String s, int from) {
  for (var i = from; i < s.length; i++) {
    if (!_spaceOrTab(s.codeUnitAt(i))) return false;
  }
  return true;
}

/// The length of the opening of an ATX heading at [at], its spaces
/// included, and its level.
(int, int) _atxMarker(String s, int at) {
  var n = 0;
  while (at + n < s.length && s.codeUnitAt(at + n) == 0x23) {
    n++;
  }
  if (n == 0 || n > 6 || (at + n < s.length && !_spaceOrTab(s.codeUnitAt(at + n)))) return (0, 0);
  final level = n;
  while (at + n < s.length && _spaceOrTab(s.codeUnitAt(at + n))) {
    n++;
  }
  return (n, level);
}

/// Where the closing sequence of an ATX heading whose content starts at
/// [from] starts, or -1.
int _atxClosing(String s, int from) {
  var end = s.length;
  while (end > from && _spaceOrTab(s.codeUnitAt(end - 1))) {
    end--;
  }
  var i = end;
  while (i > from && s.codeUnitAt(i - 1) == 0x23) {
    i--;
  }
  if (i == end) return -1;
  if (i == from) return from;
  if (!_spaceOrTab(s.codeUnitAt(i - 1))) return -1;
  while (i > from && _spaceOrTab(s.codeUnitAt(i - 1))) {
    i--;
  }
  return i;
}

int _openingFence(String s, int at) {
  final c = s.codeUnitAt(at);
  if (c != 0x60 && c != 0x7E) return 0;
  var n = 0;
  while (at + n < s.length && s.codeUnitAt(at + n) == c) {
    n++;
  }
  if (n < 3 || (c == 0x60 && s.indexOf('`', at + n) >= 0)) return 0;
  return n;
}

int _closingFence(String s, int at, int c) {
  var n = 0;
  while (at + n < s.length && s.codeUnitAt(at + n) == c) {
    n++;
  }
  return n < 3 || !_isBlank(s, at + n) ? 0 : n;
}

int _setextLevel(String s, int at) {
  final c = s.codeUnitAt(at);
  if (c != 0x3D && c != 0x2D) return 0;
  var n = 0;
  while (at + n < s.length && s.codeUnitAt(at + n) == c) {
    n++;
  }
  if (!_isBlank(s, at + n)) return 0;
  return c == 0x3D ? 1 : 2;
}

bool _thematicBreak(String s, int at) {
  final c = s.codeUnitAt(at);
  if (c != 0x2A && c != 0x2D && c != 0x5F) return false;
  var n = 0;
  for (var i = at; i < s.length; i++) {
    final d = s.codeUnitAt(i);
    if (d == c) {
      n++;
    } else if (!_spaceOrTab(d)) {
      return false;
    }
  }
  return n >= 3;
}

const _tagName = '[A-Za-z][A-Za-z0-9-]*';
/// The spaces of `\\s` in Go's regular expressions, narrower than Dart's.
const _s = r'[ \t\n\f\r]';
const _attribute = '(?:$_s+[a-zA-Z_:][a-zA-Z0-9:._-]*(?:$_s*=$_s*(?:[^"\'=<>`\\x00-\\x20]+|\'[^\']*\'|"[^"]*"))?)';

/// An opening or a closing tag.
const tagPattern = '<$_tagName$_attribute*$_s*/?>|</$_tagName$_s*[>]';

final _htmlOpen = [
  RegExp(''),
  RegExp('^<(?:script|pre|textarea|style)(?:$_s|>|\$)', caseSensitive: false),
  RegExp('^<!--'),
  RegExp(r'^<[?]'),
  RegExp('^<![A-Za-z]'),
  RegExp(r'^<!\[CDATA\['),
  RegExp(
    '^<[/]?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[123456]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|search|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:$_s|[/]?[>]|\$)',
    caseSensitive: false,
  ),
  RegExp('^(?:$tagPattern)$_s*\$', caseSensitive: false),
];

final _htmlClose = [
  RegExp(''),
  RegExp('</(?:script|pre|textarea|style)>', caseSensitive: false),
  RegExp('-->'),
  RegExp(r'\?>'),
  RegExp('>'),
  RegExp(r'\]\]>'),
];
