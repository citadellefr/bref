import 'dart:typed_data';

import 'package:flutter/painting.dart';

import 'syntax.dart';

/// What is drawn over a line shown in preview: the box of a task, the bar
/// of a quote, a rule, a picture; [column] is where its syntax starts in the
/// line, [text] what a picture leads to.
typedef Ornament = ({SwapKind kind, int column, String text, Rect rect});

typedef PendingOrnament = ({SwapKind kind, int column, String text});

/// A line laid out, as written or in preview. Its text is in offsets of what
/// is shown, which [column] and [display] map to and from the columns of the
/// line.
abstract class LineView {
  LineView({required this.preview, this.toSource});

  final bool preview;

  /// The column each offset of the text shown stands for, and the line's
  /// end after the last; null when the text shown is the line itself.
  final Int32List? toSource;

  double get height;

  /// The links whose pictures or labels the line asked the host for.
  List<String> get asked => const [];

  /// What to draw over the line, in its coordinates.
  List<Ornament> get ornaments => const [];

  /// The column of the line offset [d] of the text shown stands for.
  int column(int d) => toSource?[d] ?? d;

  /// The offset of the text shown that stands for column [c] of the line.
  int display(int c) {
    final map = toSource;
    if (map == null) return c;
    var lo = 0, hi = map.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (map[mid] < c) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void paint(Canvas canvas, Offset at);

  /// The caret before offset [d] of the text shown.
  Rect caret(int d);

  /// The offset of the text shown nearest to [local].
  int positionAt(Offset local);

  /// The boxes offsets [a] to [b] of the text shown cover.
  List<Rect> boxes(int a, int b);

  /// The visual row around offset [d], from where it starts to where it ends.
  (int, int) boundary(int d);

  void dispose();
}

/// A line of text in a single paragraph.
class TextView extends LineView {
  TextView(this.painter, Int32List? toSource, this._ornaments, {required super.preview, this.asked = const []})
      : super(toSource: toSource);

  final TextPainter painter;
  final List<PendingOrnament> _ornaments;

  @override
  final List<String> asked;

  @override
  double get height => painter.height;

  @override
  List<Ornament> get ornaments {
    if (_ornaments.isEmpty) return const [];
    final boxes = painter.inlinePlaceholderBoxes ?? const [];
    return [
      for (var k = 0; k < _ornaments.length && k < boxes.length; k++)
        (kind: _ornaments[k].kind, column: _ornaments[k].column, text: _ornaments[k].text, rect: boxes[k].toRect()),
    ];
  }

  @override
  void paint(Canvas canvas, Offset at) => painter.paint(canvas, at);

  @override
  Rect caret(int d) {
    final position = TextPosition(offset: d);
    final at = painter.getOffsetForCaret(position, Rect.zero);
    return Rect.fromLTWH(at.dx, at.dy, 2, painter.getFullHeightForCaret(position, Rect.zero));
  }

  @override
  int positionAt(Offset local) => painter.getPositionForOffset(local).offset;

  @override
  List<Rect> boxes(int a, int b) =>
      [for (final box in painter.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b))) box.toRect()];

  @override
  (int, int) boundary(int d) {
    final row = painter.getLineBoundary(TextPosition(offset: d));
    return (row.start, row.end);
  }

  @override
  void dispose() => painter.dispose();
}

/// The grid a table is drawn on, shared by its rows: [widths] are those of
/// the columns, their padding included.
class TableGrid {
  TableGrid(this.widths) : width = widths.fold(0.0, (a, b) => a + b);

  static const padding = 8.0;
  static const rowPadding = 4.0;

  final List<double> widths;
  final double width;

  double left(int column) {
    var x = 0.0;
    for (var k = 0; k < column; k++) {
      x += widths[k];
    }
    return x;
  }
}

/// A row of a table, one paragraph for each cell. The text shown is the
/// text of the cells one after the other, one offset between two cells.
class GridRowView extends LineView {
  GridRowView({
    required this.grid,
    required this.painters,
    required this.starts,
    required this.lengths,
    required Int32List toSource,
    required this.height,
    required this.header,
    required this.border,
    required this.fill,
  }) : super(preview: true, toSource: toSource);

  /// A row that takes no room: the delimiter under the header.
  GridRowView.hidden(this.grid, Int32List toSource)
      : painters = const [],
        starts = const [],
        lengths = const [],
        height = 0,
        header = false,
        border = const Color(0x00000000),
        fill = const Color(0x00000000),
        super(preview: true, toSource: toSource);

  final TableGrid grid;
  final List<TextPainter> painters;

  /// Where the text of each cell starts, in the offsets of the row, and how
  /// long it is.
  final List<int> starts;
  final List<int> lengths;

  @override
  final double height;
  final bool header;
  final Color border;
  final Color fill;

  Offset _origin(int cell) => Offset(grid.left(cell) + TableGrid.padding, TableGrid.rowPadding);

  int _cellAt(int d) {
    var k = 0;
    while (k + 1 < starts.length && starts[k + 1] <= d) {
      k++;
    }
    return k;
  }

  @override
  void paint(Canvas canvas, Offset at) {
    if (painters.isEmpty) return;
    final box = Rect.fromLTWH(at.dx, at.dy, grid.width, height);
    if (header) canvas.drawRect(box, Paint()..color = fill);
    final line = Paint()
      ..color = border
      ..strokeWidth = 1;
    for (var k = 0; k <= painters.length; k++) {
      final x = at.dx + grid.left(k);
      canvas.drawLine(Offset(x, at.dy), Offset(x, at.dy + height), line);
    }
    canvas.drawLine(box.bottomLeft, box.bottomRight, line);
    if (header) canvas.drawLine(box.topLeft, box.topRight, line);
    for (var k = 0; k < painters.length; k++) {
      painters[k].paint(canvas, at + _origin(k));
    }
  }

  @override
  Rect caret(int d) {
    if (painters.isEmpty) return Rect.zero;
    final k = _cellAt(d);
    final position = TextPosition(offset: d - starts[k]);
    final at = painters[k].getOffsetForCaret(position, Rect.zero) + _origin(k);
    return Rect.fromLTWH(at.dx, at.dy, 2, painters[k].getFullHeightForCaret(position, Rect.zero));
  }

  @override
  int positionAt(Offset local) {
    if (painters.isEmpty) return 0;
    var k = 0;
    while (k + 1 < painters.length && grid.left(k + 1) <= local.dx) {
      k++;
    }
    return starts[k] + painters[k].getPositionForOffset(local - _origin(k)).offset;
  }

  @override
  List<Rect> boxes(int a, int b) {
    final out = <Rect>[];
    for (var k = 0; k < painters.length; k++) {
      final lo = a > starts[k] ? a : starts[k];
      final hi = b < starts[k] + lengths[k] ? b : starts[k] + lengths[k];
      if (lo >= hi) continue;
      final selection = TextSelection(baseOffset: lo - starts[k], extentOffset: hi - starts[k]);
      for (final box in painters[k].getBoxesForSelection(selection)) {
        out.add(box.toRect().shift(_origin(k)));
      }
    }
    return out;
  }

  @override
  (int, int) boundary(int d) {
    if (painters.isEmpty) return (d, d);
    final k = _cellAt(d);
    final row = painters[k].getLineBoundary(TextPosition(offset: d - starts[k]));
    return (starts[k] + row.start, starts[k] + row.end);
  }

  @override
  void dispose() {
    for (final p in painters) {
      p.dispose();
    }
  }
}
