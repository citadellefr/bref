import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'host_cache.dart';
import 'line_view.dart';
import 'md/node.dart' as md show Align;
import 'note_syntax.dart';
import 'note_text.dart';
import 'syntax.dart';
import 'theme.dart';

/// What a stretch of a line reads as.
class _Content {
  final children = <InlineSpan>[];

  /// The column each offset of the text stands for, and that of the end.
  final toSource = <int>[];
  final ornaments = <PendingOrnament>[];
  final placeholders = <PlaceholderDimensions>[];
  final asked = <String>[];
  final chips = <(int, int)>[];
}

/// The lines of a note laid out one under the other, in a column of
/// [width]. Only the lines shown are laid out; the others have a height
/// guessed from their length, corrected once they are shown.
///
/// In [preview], lines show their text without its syntax, as it reads,
/// but for those [reveal] asks to show as written: the lines being edited.
class NoteLayout extends ChangeNotifier {
  NoteLayout(this.text, this.syntax, {required this._theme, required this._scaler, this._preview = false}) {
    _measureFont();
    _reset();
  }

  final NoteText text;
  final NoteSyntax syntax;

  BrefTheme _theme;
  TextScaler _scaler;
  bool _preview;
  double _width = 0;
  HostCache? _cache;

  /// The grid of each table, by the line it starts at.
  final _grids = <int, TableGrid>{};

  final _heights = <double>[];
  final _measured = <bool>[];
  final _views = <LineView?>[];

  /// The top of each line and the bottom of the last, valid up to
  /// [_validTops].
  final _tops = <double>[];
  var _validTops = 0;

  final _styles = <int, TextStyle>{};
  TextStyle? _fold;
  var _lineHeight = 24.0;
  var _charWidth = 8.0;
  var _fontSize = 16.0;

  /// The lines shown as written in preview.
  var _first = -1, _last = -1;

  /// The first line shown, which stays in place when lines above it change.
  var anchor = 0;

  BrefTheme get theme => _theme;

  set theme(BrefTheme value) {
    if (value == _theme) return;
    _theme = value;
    _restyle();
  }

  TextScaler get scaler => _scaler;

  set scaler(TextScaler value) {
    if (value == _scaler) return;
    _scaler = value;
    _restyle();
  }

  bool get preview => _preview;

  set preview(bool value) {
    if (value == _preview) return;
    _preview = value;
    notifyListeners();
  }

  /// What the host said of pictures and links, shown in preview.
  HostCache? get cache => _cache;

  set cache(HostCache? value) {
    if (value == _cache) return;
    _cache = value;
    _reset();
    notifyListeners();
  }

  /// Lays out again the lines that asked about [dest], whose answer came.
  void answered(String dest) {
    for (var i = 0; i < _views.length; i++) {
      if (_views[i]?.asked.contains(dest) ?? false) {
        _views[i]!.dispose();
        _views[i] = null;
      }
    }
    notifyListeners();
  }

  double get width => _width;

  set width(double value) {
    if (value == _width) return;
    _width = value;
    _reset();
  }

  void _restyle() {
    _styles.clear();
    _fold = null;
    _measureFont();
    _reset();
    notifyListeners();
  }

  void _measureFont() {
    final probe = TextPainter(
      text: TextSpan(text: 'abcdefghijklmnopqrstuvwxyz', style: _theme.text),
      textDirection: TextDirection.ltr,
      textScaler: _scaler,
    )..layout();
    _lineHeight = probe.height;
    _charWidth = probe.width / 26;
    _fontSize = _scaler.scale(_theme.text.fontSize ?? 16);
    probe.dispose();
  }

  void _reset() {
    _grids.clear();
    for (final v in _views) {
      v?.dispose();
    }
    _views
      ..clear()
      ..length = text.lineCount;
    _measured
      ..clear()
      ..addAll(List.filled(text.lineCount, false));
    _heights
      ..clear()
      ..addAll([for (var i = 0; i < text.lineCount; i++) _estimate(i)]);
    _tops
      ..clear()
      ..addAll(List.filled(text.lineCount + 1, 0.0));
    _validTops = 0;
  }

  /// Starts again from a text read anew.
  void reload() {
    _reset();
    anchor = 0;
    _first = _last = -1;
    notifyListeners();
  }

  /// Shows lines [first] to [last] as written in preview, none when [first]
  /// is -1.
  void reveal(int first, int last) {
    if (first == _first && last == _last) return;
    _first = first;
    _last = last;
    if (_preview) notifyListeners();
  }

  /// Whether line [i] reads as it renders: those of a table always do, but
  /// the delimiter row, so that a table is edited as a grid.
  bool previewed(int i) {
    if (!_preview) return false;
    if (i < _first || i > _last) return true;
    final table = syntax.line(i).table;
    return table != null && !table.delimiter;
  }

  /// The visual row of the text around [offset]: from where it starts to
  /// where it ends.
  (int, int) rowAt(int offset) {
    final i = text.lineAt(offset);
    final start = text.lineStart(i);
    final v = view(i);
    final (from, to) = v.boundary(v.display(offset - start));
    return (start + v.column(from), start + v.column(to));
  }

  /// Follows a splice of the text, after which the syntax of lines
  /// [restyled] changed, those of the splice aside.
  void splice(LineSplice s, (int, int) restyled) {
    _grids.clear();
    for (var i = s.index; i < s.index + s.removed; i++) {
      _views[i]?.dispose();
    }
    _views.replaceRange(s.index, s.index + s.removed, List.filled(s.inserted, null));
    _measured.replaceRange(s.index, s.index + s.removed, List.filled(s.inserted, false));
    _heights.replaceRange(s.index, s.index + s.removed, [for (var i = 0; i < s.inserted; i++) _estimate(s.index + i)]);
    _tops.replaceRange(s.index + 1, s.index + s.removed + 1, List.filled(s.inserted, 0.0));
    final (from, to) = restyled;
    for (var i = from; i < to && i < text.lineCount; i++) {
      _views[i]?.dispose();
      _views[i] = null;
      _measured[i] = false;
    }
    final delta = s.inserted - s.removed;
    int follow(int k) => k >= s.index + s.removed ? k + delta : math.min(k, s.index);
    if (anchor >= s.index + s.removed) {
      anchor += delta;
    } else if (anchor > s.index) {
      anchor = s.index;
    }
    if (_first >= 0) {
      _first = follow(_first);
      _last = follow(_last);
    }
    _validTops = math.min(_validTops, math.min(s.index, from));
    notifyListeners();
  }

  double _estimate(int i) {
    final chars = text.line(i).length;
    if (_width <= 0 || chars == 0) return _lineHeight;
    return _lineHeight * math.max(1, (chars * _charWidth / _width).ceil());
  }

  double get height => top(text.lineCount);

  /// The top of line [i]; that of [NoteText.lineCount] is the bottom of the
  /// last.
  double top(int i) {
    if (_validTops < i) {
      for (var k = _validTops; k < i; k++) {
        _tops[k + 1] = _tops[k] + _heights[k];
      }
      _validTops = i;
    }
    return _tops[i];
  }

  double lineHeight(int i) => _heights[i];

  /// The line at height [y], the first or the last beyond them.
  int lineAtY(double y) {
    if (y <= 0) return 0;
    var lo = 0, hi = text.lineCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (top(mid) <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Line [i] laid out, its height known from then on.
  LineView view(int i) {
    final preview = previewed(i);
    final cached = _views[i];
    if (cached != null && cached.preview == preview) return cached;
    cached?.dispose();
    final v = preview ? _previewView(i) : _writtenView(i);
    _views[i] = v;
    final height = v.height;
    if (!_measured[i] || _heights[i] != height) {
      _measured[i] = true;
      _heights[i] = height;
      _validTops = math.min(_validTops, i);
    }
    return v;
  }

  TextPainter _painter(InlineSpan span, [List<PlaceholderDimensions> placeholders = const []]) {
    final p = TextPainter(text: span, textDirection: TextDirection.ltr, textScaler: _scaler);
    if (placeholders.isNotEmpty) p.setPlaceholderDimensions(placeholders);
    return p..layout(maxWidth: math.max(_width, 1));
  }

  LineView _writtenView(int i, {bool preview = false}) {
    final line = text.line(i);
    final s = syntax.line(i);
    if (line.isEmpty) return TextView(_painter(TextSpan(text: '', style: _style(0, s.heading))), null, const [], preview: preview);
    var from = 0;
    final span = TextSpan(
      style: _style(0, s.heading),
      children: [
        for (var k = 0; k < s.ends.length; k++)
          TextSpan(text: line.substring(from, from = s.ends[k]), style: _style(s.marks[k], s.heading)),
      ],
    );
    return TextView(_painter(span), null, const [], preview: preview);
  }

  /// The line as it reads: its syntax hidden, its bullets, boxes, bars and
  /// rules drawn.
  LineView _previewView(int i) {
    final line = text.line(i);
    final s = syntax.line(i);
    final base = _style(0, s.heading);
    final table = s.table;
    if (table != null) return _tableRow(i, s, table, line);
    for (final swap in s.swaps) {
      if (swap.kind == SwapKind.rule) {
        return TextView(
          _painter(TextSpan(style: base, children: const [WidgetSpan(child: SizedBox.shrink())]), [
            PlaceholderDimensions(size: Size(math.max(_width - 1, 1), _lineHeight), alignment: PlaceholderAlignment.middle),
          ]),
          Int32List.fromList([0, line.length]),
          [(kind: SwapKind.rule, column: swap.start, text: '')],
          preview: true,
        );
      }
      if (swap.kind == SwapKind.fold) {
        final label = swap.text;
        return TextView(
          _painter(TextSpan(text: label, style: _foldStyle)),
          Int32List(label.length + 1)..fillRange(0, label.length + 1, line.length),
          const [],
          preview: true,
        );
      }
    }
    if (s.swaps.isEmpty) return _writtenView(i, preview: true);
    final c = _content(line, s, 0, line.length, pictures: true);
    return TextView(
      _painter(TextSpan(style: base, children: c.children), c.placeholders),
      Int32List.fromList(c.toSource),
      c.ornaments,
      preview: true,
      asked: c.asked,
      chips: c.chips,
    );
  }

  /// What columns [from] to [to] of [line] read as: pieces of text, those
  /// of the syntax hidden or swapped, and what stands for each offset.
  /// [extra] are marks added to all of it.
  _Content _content(String line, LineSyntax s, int from, int to, {required bool pictures, int extra = 0}) {
    final c = _Content();
    var piece = 0;
    int marksAt(int col) {
      while (piece < s.ends.length && s.ends[piece] <= col) {
        piece++;
      }
      return (piece < s.marks.length ? s.marks[piece] : 0) | extra;
    }

    void written(int a, int b) {
      while (a < b) {
        final marks = marksAt(a);
        final end = math.min(b, s.ends[piece]);
        c.children.add(TextSpan(text: line.substring(a, end), style: _style(marks, s.heading)));
        for (var k = a; k < end; k++) {
          c.toSource.add(k);
        }
        a = end;
      }
    }

    var col = from;
    for (final swap in s.swaps) {
      if (swap.start < col || swap.end > to) continue;
      if (swap.kind == SwapKind.picture || swap.kind == SwapKind.label) {
        final cache = _cache;
        if (cache == null || swap.kind == SwapKind.picture && !pictures) continue;
        c.asked.add(swap.text);
        if (swap.kind == SwapKind.picture) {
          final size = _pictureSize(cache.picture(swap.text));
          if (size == null) continue;
          written(col, swap.start);
          c.children.add(const WidgetSpan(child: SizedBox.shrink(), alignment: PlaceholderAlignment.bottom));
          c.placeholders.add(PlaceholderDimensions(size: size, alignment: PlaceholderAlignment.bottom));
          c.ornaments.add((kind: SwapKind.picture, column: swap.start, text: swap.text));
          c.toSource.add(swap.start);
        } else {
          final label = cache.label(swap.text);
          if (label == null) continue;
          written(col, swap.start);
          final from = c.toSource.length;
          void room(Size size, SwapKind kind) {
            c.children.add(const WidgetSpan(child: SizedBox.shrink(), alignment: PlaceholderAlignment.middle));
            c.placeholders.add(PlaceholderDimensions(size: size, alignment: PlaceholderAlignment.middle));
            c.ornaments.add((kind: kind, column: swap.start, text: swap.text));
            c.toSource.add(swap.start);
          }

          final edge = Size(_fontSize * 0.3, 1);
          room(edge, SwapKind.hide);
          // a chip reads as a link, whatever the address it stands for is drawn as
          final style = _style(marksAt(swap.start) & ~Mark.url | Mark.link, s.heading);
          final icon = label.icon;
          var lead = '';
          if (label.image != null) {
            room(Size.square(_fontSize * 1.1), SwapKind.label);
            lead = ' ';
            c.children.add(TextSpan(text: lead, style: style));
          } else if (icon != null) {
            lead = '${String.fromCharCode(icon.codePoint)} ';
            final family = icon.fontPackage == null ? icon.fontFamily : 'packages/${icon.fontPackage}/${icon.fontFamily}';
            c.children.add(TextSpan(text: lead, style: style.copyWith(fontFamily: family)));
          }
          final text = label.text.isEmpty ? line.substring(swap.start, swap.end) : label.text;
          c.children.add(TextSpan(text: text, style: style));
          c.toSource.addAll(List.filled(lead.length + text.length, swap.start));
          room(edge, SwapKind.hide);
          c.chips.add((from, c.toSource.length));
        }
        col = swap.end;
        continue;
      }
      written(col, swap.start);
      switch (swap.kind) {
        case SwapKind.text:
          c.children.add(TextSpan(text: swap.text, style: _style(marksAt(swap.start), s.heading)));
          for (var k = 0; k < swap.text.length; k++) {
            c.toSource.add(swap.start);
          }
        case SwapKind.box || SwapKind.doneBox || SwapKind.bar:
          final size = swap.kind == SwapKind.bar ? Size(_fontSize * 0.9, _fontSize) : Size(_fontSize * 1.2, _fontSize);
          c.children.add(const WidgetSpan(child: SizedBox.shrink(), alignment: PlaceholderAlignment.middle));
          c.placeholders.add(PlaceholderDimensions(size: size, alignment: PlaceholderAlignment.middle));
          c.ornaments.add((kind: swap.kind, column: swap.start, text: ''));
          c.toSource.add(swap.start);
        default:
      }
      col = swap.end;
    }
    written(col, to);
    c.toSource.add(to);
    return c;
  }

  /// The row of a table [t] that line [i] is, on the grid of its table.
  LineView _tableRow(int i, LineSyntax s, TableLine t, String line) {
    final grid = _gridOf(t);
    if (t.delimiter) return GridRowView.hidden(grid, Int32List.fromList([0, line.length]));
    final extra = t.header ? Mark.strong : 0;
    final painters = <TextPainter>[], starts = <int>[], lengths = <int>[], toSource = <int>[];
    final chips = <(int, int)>[];
    var height = _lineHeight;
    for (var k = 0; k < grid.widths.length; k++) {
      final cell = k < t.cells.length ? t.cells[k] : (start: line.length, end: line.length);
      final c = _content(line, s, cell.start, cell.end, pictures: false, extra: extra);
      final painter = _cellPainter(c, _style(extra, 0), grid.widths[k] - 2 * TableGrid.padding, _textAlign(t.align, k));
      painters.add(painter);
      chips.addAll([for (final chip in c.chips) (toSource.length + chip.$1, toSource.length + chip.$2)]);
      starts.add(toSource.length);
      lengths.add(c.toSource.length - 1);
      toSource.addAll(c.toSource);
      height = math.max(height, painter.height);
    }
    return GridRowView(
      grid: grid,
      painters: painters,
      starts: starts,
      lengths: lengths,
      toSource: Int32List.fromList(toSource),
      height: height + 2 * TableGrid.rowPadding,
      header: t.header,
      border: _theme.markup,
      fill: _theme.codeBackground,
      chips: chips,
    );
  }

  TextPainter _cellPainter(_Content c, TextStyle style, double width, TextAlign align) {
    final p = TextPainter(
      text: TextSpan(style: style, children: c.children),
      textDirection: TextDirection.ltr,
      textAlign: align,
      textScaler: _scaler,
    );
    return p..layout(minWidth: math.max(width, 1), maxWidth: math.max(width, 1));
  }

  static TextAlign _textAlign(List<md.Align> align, int column) => switch (column < align.length ? align[column] : md.Align.none) {
        md.Align.center => TextAlign.center,
        md.Align.right => TextAlign.right,
        _ => TextAlign.left,
      };

  /// The most rows of a table measured to find the widths of its columns.
  static const _sampled = 100;

  /// The widths of the columns of the table [t] is a row of: what its widest
  /// cells need, narrowed to the column of the note when they need more.
  TableGrid _gridOf(TableLine t) => _grids[t.first] ??= () {
    final columns = t.align.length;
    final wanted = List.filled(columns, 0.0);
    for (var r = t.first; r <= math.min(t.last, t.first + _sampled); r++) {
      final s = syntax.line(r);
      final cells = s.table?.cells;
      if (cells == null) continue;
      final line = text.line(r);
      final extra = s.table!.header ? Mark.strong : 0;
      for (var k = 0; k < columns && k < cells.length; k++) {
        if (cells[k].start == cells[k].end) continue;
        final c = _content(line, s, cells[k].start, cells[k].end, pictures: false, extra: extra);
        final p = TextPainter(text: TextSpan(style: _style(extra, 0), children: c.children), textDirection: TextDirection.ltr, textScaler: _scaler)
          ..layout();
        wanted[k] = math.max(wanted[k], p.width);
        p.dispose();
      }
    }
    final pad = 2 * TableGrid.padding;
    final widths = [for (final w in wanted) math.max(w, _charWidth * 3) + pad + 1];
    return TableGrid(_fitted(widths, math.max(_width - 1, 1)));
  }();

  /// [widths] reduced to sum to at most [room]: the widest columns give
  /// way, to an equal width, while the narrow ones keep theirs.
  static List<double> _fitted(List<double> widths, double room) {
    if (widths.fold(0.0, (a, b) => a + b) <= room) return widths;
    final sorted = [...widths]..sort();
    var left = room, share = room / widths.length;
    for (var k = 0; k < sorted.length; k++) {
      share = left / (sorted.length - k);
      if (sorted[k] > share) break;
      left -= sorted[k];
    }
    return [for (final w in widths) math.min(w, math.max(share, _minimum))];
  }

  static const _minimum = 3 * TableGrid.padding;

  /// The size a picture is shown at: its own, narrowed to the column.
  Size? _pictureSize(ImageInfo? info) {
    if (info == null) return null;
    final width = info.image.width / info.scale, height = info.image.height / info.scale;
    if (width <= 0 || height <= 0) return null;
    final shown = math.min(width, math.max(_width - 1, 1.0));
    return Size(shown, height * shown / width);
  }

  /// The style of what a folded line still shows.
  TextStyle get _foldStyle =>
      _fold ??= _theme.style(Mark.fence | Mark.markup, 0).copyWith(fontSize: (_theme.text.fontSize ?? 16) * 0.7, height: 1.2);

  TextStyle _style(int marks, int heading) => _styles[marks << 3 | heading] ??= _theme.style(marks, heading);

  /// Lets go of the lines laid out far from those shown.
  void forget(int first, int last) {
    const keep = 200;
    for (var i = 0; i < _views.length; i++) {
      if (i >= first - keep && i <= last + keep) {
        i = last + keep;
        continue;
      }
      _views[i]?.dispose();
      _views[i] = null;
    }
  }

  /// The offset of the text nearest to [p], in the coordinates of the
  /// column.
  int offsetAt(Offset p) {
    final i = lineAtY(p.dy);
    final v = view(i);
    return text.lineStart(i) + v.column(v.positionAt(Offset(p.dx, p.dy - top(i))));
  }

  /// The caret before the unit at [offset], in the coordinates of the
  /// column.
  Rect caretRect(int offset) {
    final i = text.lineAt(offset);
    final v = view(i);
    return v.caret(v.display(offset - text.lineStart(i))).shift(Offset(0, top(i)));
  }

  /// The boxes columns [a] to [b] of line [i] cover, in the coordinates of
  /// the line.
  List<Rect> boxes(int i, int a, int b) {
    final v = view(i);
    return v.boxes(v.display(a), v.display(b));
  }

  /// The offset of the box of a task at [p], in the coordinates of the
  /// column, or null.
  int? taskAt(Offset p) {
    final i = lineAtY(p.dy);
    final v = view(i);
    for (final o in v.ornaments) {
      if ((o.kind == SwapKind.box || o.kind == SwapKind.doneBox) && o.rect.inflate(4).contains(Offset(p.dx, p.dy - top(i)))) {
        return text.lineStart(i) + o.column;
      }
    }
    return null;
  }

  /// The link or picture under [p], in the coordinates of the column, or
  /// null.
  NoteLink? linkAt(Offset p) {
    final i = lineAtY(p.dy);
    final v = view(i);
    final local = Offset(p.dx, p.dy - top(i));
    final start = text.lineStart(i), end = text.lineEnd(i);
    final at = start + v.column(v.positionAt(local));
    for (final o in [at, at - 1]) {
      if (o < start || o >= end) continue;
      final link = syntax.linkAt(o);
      if (link == null) continue;
      final a = math.max(link.start, start) - start, b = math.min(link.end, end) - start;
      if (boxes(i, a, b).any((r) => r.contains(local))) return link;
    }
    return null;
  }

  @override
  void dispose() {
    for (final v in _views) {
      v?.dispose();
    }
    super.dispose();
  }
}
