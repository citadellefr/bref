import 'highlight.dart';
import 'md/block.dart';
import 'md/inline.dart';
import 'md/node.dart';
import 'note_text.dart';
import 'syntax.dart';

/// A link or a picture, in the offsets of the text.
typedef NoteLink = ({int start, int end, String dest, bool wiki, bool image});

/// A block of the document itself, with the lines it spans. Its offsets are
/// those of the text when it was read, [base] being where its first line
/// started then: lines inserted above move it without reading it again.
class _Top {
  _Top(this.node, this.line, this.last, this.base, this.leaves, this.callout);

  final MdNode node;
  int line;
  int last;
  final int base;
  final List<Leaf> leaves;

  /// What the block opens, if it is a quote that does.
  final Callout? callout;
  var inlines = false;

  /// The code of the blocks of code, read when a line of it is.
  final code = <MdNode, _Code>{};
}

/// A block of code, its lines and the pieces of each.
class _Code {
  _Code(this.lines, this.runs);

  final List<String> lines;
  final List<List<Run>> runs;
}

/// The syntax of a note, read as Markdown. Blocks are read again from the
/// last line before an edit where nothing was open, up to where what is
/// open matches what was before; inlines are read when a block is first
/// shown, and the marks of a line when the line is.
class NoteSyntax {
  NoteSyntax(this.text) {
    reset();
  }

  final NoteText text;

  final _tops = <_Top>[];

  /// Whether every block was closed before each line, and after the last.
  final _clean = <bool>[];
  final _lines = <LineSyntax?>[];
  var _refs = Refs();

  LineSyntax line(int i) => _lines[i] ??= _read(i);

  /// Whether line [i] belongs to a block of code or math, its fences
  /// included: it is drawn on a background of its own.
  bool inBlock(int i) => line(i).block;

  void reset() {
    _tops.clear();
    _clean
      ..clear()
      ..addAll(List.filled(text.lineCount + 1, true));
    _lines
      ..clear()
      ..length = text.lineCount;
    _parse(0, text.lineCount, 0, const []);
    _refs = definitionMap(_definitions(_tops));
  }

  /// Follows a splice the text made, and answers the lines around it whose
  /// syntax may have changed with it, the new ones aside: from the first to
  /// before the last.
  (int, int) splice(LineSplice s) {
    final delta = s.inserted - s.removed;
    _lines.replaceRange(s.index, s.index + s.removed, List.filled(s.inserted, null));
    var from = s.index;
    while (!_clean[from]) {
      from--;
    }
    if (from > 0 && _maybeFrontMatter(s)) from = 0;
    final old = _clean.toList();
    _clean.replaceRange(s.index + 1, s.index + s.removed + 1, List.filled(s.inserted, false));

    var first = _tops.indexWhere((t) => t.line >= from);
    if (first < 0) first = _tops.length;
    final after = _tops.sublist(first);
    _tops.removeRange(first, _tops.length);
    final to = _parse(from, s.index + s.inserted, delta, old);
    final removed = after.where((t) => t.line < to - delta).toList();
    for (final t in after.skip(removed.length)) {
      _tops.add(t
        ..line += delta
        ..last += delta);
    }
    for (var i = from; i < to; i++) {
      _lines[i] = null;
    }
    final added = _tops.where((t) => t.line >= from && t.line < to);
    if (!_sameDefinitions(_definitions(removed), _definitions(added))) {
      _refs = definitionMap(_definitions(_tops));
      for (final t in _tops) {
        t.inlines = false;
      }
      _lines.fillRange(0, _lines.length, null);
      return (0, text.lineCount);
    }
    return (from, to);
  }

  /// Whether the first line opens front matter the edit may close: then it
  /// is read again from the first line.
  bool _maybeFrontMatter(LineSplice s) {
    if (text.line(0).trimRight() != '---' || (_tops.isNotEmpty && _tops.first.node.kind == MdKind.frontMatter)) return false;
    for (var i = s.index; i < s.index + s.inserted; i++) {
      final t = text.line(i).trimRight();
      if (t == '---' || t == '...') return true;
    }
    return false;
  }

  /// Reads the blocks from line [from], where nothing is open, at least up
  /// to line [edited], then up to a line where nothing is open as nothing
  /// was in [old], which tells it for the lines [delta] before; answers
  /// where it stopped.
  int _parse(int from, int edited, int delta, List<bool> old) {
    final p = BlockParser(MdSyntax.bref);
    var i = from;
    if (from == 0) {
      final matter = readFrontMatter(text.lineCount, text.line, text.lineStart);
      if (matter != null) {
        p.doc.add(matter.node);
        i = matter.lines;
        for (var k = 1; k < i; k++) {
          _clean[k] = false;
        }
        _clean[i] = true;
      }
    }
    while (i < text.lineCount) {
      if (i > from) _clean[i] = p.clean;
      if (i >= edited && i > from && p.clean && i - delta < old.length && old[i - delta]) break;
      p.addLine(text.line(i), text.lineStart(i));
      i++;
    }
    p.finish();
    if (i == text.lineCount) _clean[i] = true;
    final tops = [
      for (final n in p.doc.children)
        _Top(n, text.lineAt(n.start), text.lineAt(n.end), text.lineStart(text.lineAt(n.start)), [], _calloutOf(n)),
    ];
    for (final leaf in p.leaves) {
      _topAt(tops, leaf.node.start).leaves.add(leaf);
    }
    _tops.addAll(tops);
    return i;
  }

  Callout? _calloutOf(MdNode n) {
    if (n.kind != MdKind.quote || n.marks.isEmpty) return null;
    final first = text.lineAt(n.start);
    return calloutOf(text.line(first), n.marks.first.end - text.lineStart(first));
  }

  static _Top _topAt(List<_Top> tops, int offset) {
    var lo = 0, hi = tops.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (tops[mid].node.start <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return tops[lo];
  }

  static List<MdNode> _definitions(Iterable<_Top> tops) {
    final out = <MdNode>[];
    for (final t in tops) {
      t.node.walk((n) {
        if (n.kind == MdKind.definition || n.kind == MdKind.footnoteDef) out.add(n);
        return n.kind == MdKind.document || n.kind == MdKind.quote || n.kind == MdKind.list || n.kind == MdKind.item;
      });
    }
    return out;
  }

  static bool _sameDefinitions(List<MdNode> a, List<MdNode> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label || a[i].dest != b[i].dest || a[i].title != b[i].title) return false;
    }
    return true;
  }

  /// The block holding line [i], if any.
  _Top? _blockAt(int i) {
    var lo = 0, hi = _tops.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_tops[mid].line <= i) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    if (_tops.isEmpty || _tops[lo].line > i || _tops[lo].last < i) return null;
    return _tops[lo];
  }

  LineSyntax _read(int i) {
    final line = text.line(i);
    final t = _blockAt(i);
    if (t == null) return line.isEmpty ? const LineSyntax([], []) : LineSyntax([line.length], const [0]);
    if (!t.inlines) {
      for (final leaf in t.leaves) {
        leaf.node.children = parseInlines(leaf, _refs, MdSyntax.bref);
      }
      t.inlines = true;
    }
    final callout = t.callout;
    final s = readLine(t.node, line, text.lineStart(i) - text.lineStart(t.line) + t.base,
        callout: callout, header: callout != null && i == t.line);
    return s.block ? _colored(s, t, i, line) : s;
  }

  /// The line [s] of a block of code, or of front matter, its pieces colored when the language is known.
  LineSyntax _colored(LineSyntax s, _Top t, int i, String line) {
    final found = _nodeAt(i);
    final n = found?.node;
    if (n == null || n.kind != MdKind.codeBlock && n.kind != MdKind.frontMatter || n.marks.isEmpty) return s;
    final language = n.kind == MdKind.frontMatter ? 'yaml' : languageOf(n.info);
    if (language == null) return s;
    final code = t.code[n] ??= () {
      final lines = n.literal.split('\n');
      return _Code(lines, highlight(language, n.literal));
    }();
    final k = i - text.lineAt(n.start + found!.shift) - 1;
    if (k < 0 || k >= code.lines.length - 1 || !line.endsWith(code.lines[k])) return s;
    return s.coded(line.length, line.length - code.lines[k].length, code.runs[k]);
  }

  /// The innermost link or picture holding the character at [offset].
  NoteLink? linkAt(int offset) {
    final i = text.lineAt(offset);
    final t = _blockAt(i);
    if (t == null) return null;
    line(i);
    final shift = text.lineStart(t.line) - t.base;
    final at = offset - shift;
    MdNode? found;
    t.node.walk((n) {
      if (n.start > at || n.end <= at) return false;
      if (n.kind == MdKind.link || n.kind == MdKind.image) found = n;
      return true;
    });
    final n = found;
    if (n == null) return null;
    return (start: n.start + shift, end: n.end + shift, dest: n.dest, wiki: n.form == LinkForm.wiki, image: n.kind == MdKind.image);
  }

  /// The lines to show as they are written when [first] to [last] are: the
  /// whole of the blocks of code, of math, the headings underlined and the
  /// front matter they touch.
  (int, int) revealed(int first, int last) => (_whole(first).$1, _whole(last).$2);

  (int, int) _whole(int i) {
    final found = _nodeAt(i);
    if (found == null) return (i, i);
    return (text.lineAt(found.node.start + found.shift), text.lineAt(found.node.end + found.shift));
  }

  /// The block of code, of math, the front matter or the heading holding line
  /// [i], with how far its offsets are from those of the text.
  ({MdNode node, int shift})? _nodeAt(int i) {
    final t = _blockAt(i);
    if (t == null) return null;
    final lo = text.lineStart(i) - text.lineStart(t.line) + t.base;
    final hi = lo + text.line(i).length;
    MdNode? found;
    t.node.walk((n) {
      if (n.end < lo || n.start > hi) return false;
      if (n.kind == MdKind.codeBlock || n.kind == MdKind.mathBlock || n.kind == MdKind.frontMatter || n.kind == MdKind.heading) {
        found = n;
      }
      return n.kind != MdKind.paragraph && n.kind != MdKind.heading && n.kind != MdKind.table;
    });
    final n = found;
    return n == null ? null : (node: n, shift: text.lineStart(t.line) - t.base);
  }
}
