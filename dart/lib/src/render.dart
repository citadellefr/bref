import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'layout.dart';
import 'note_syntax.dart';
import 'syntax.dart';
import 'theme.dart';

/// Someone else's selection, as the note shows it.
typedef PeerMark = ({int sid, String name, int base, int extent});

/// A passage the note colors: a thread of comments, or what one person wrote.
typedef Passage = ({int from, int to, Color color});

/// What is drawn over the text: the selection, the caret and those of the
/// others. Changing it repaints the note without laying it out again.
class NoteMarks extends ChangeNotifier {
  int base = 0;
  int extent = 0;
  bool caret = false;
  TextRange composing = TextRange.empty;
  List<PeerMark> peers = const [];

  /// Drawn under the selection, in order: later ones over the earlier.
  List<Passage> passages = const [];

  int get start => math.min(base, extent);

  int get end => math.max(base, extent);

  void changed() => notifyListeners();
}

/// The note scrolled by [offset]: the lines in view laid out and drawn,
/// with what [marks] holds over them.
class NoteViewport extends LeafRenderObjectWidget {
  const NoteViewport({super.key, required this.offset, required this.layout, required this.marks, required this.padding});

  final ViewportOffset offset;
  final NoteLayout layout;
  final NoteMarks marks;
  final EdgeInsets padding;

  @override
  RenderNote createRenderObject(BuildContext context) =>
      RenderNote(offset: offset, noteLayout: layout, marks: marks, padding: padding);

  @override
  void updateRenderObject(BuildContext context, RenderNote renderObject) {
    renderObject
      ..offset = offset
      ..noteLayout = layout
      ..marks = marks
      ..padding = padding;
  }
}

class RenderNote extends RenderBox {
  RenderNote({
    required this._offset,
    required NoteLayout noteLayout,
    required this._marks,
    required this._padding,
  }) : _layout = noteLayout;

  /// How far beyond the view lines are laid out, so that scrolling a little
  /// shows lines already measured.
  static const _cache = 400.0;

  ViewportOffset _offset;
  NoteLayout _layout;
  NoteMarks _marks;
  EdgeInsets _padding;

  /// The anchor line's top at the last layout: where it moved since is how
  /// far the view must follow.
  double? _anchorTop;
  var _first = 0, _last = -1;
  final _labels = <String, TextPainter>{};

  set offset(ViewportOffset value) {
    if (value == _offset) return;
    if (attached) _offset.removeListener(markNeedsLayout);
    _offset = value;
    if (attached) _offset.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  set noteLayout(NoteLayout value) {
    if (value == _layout) return;
    if (attached) _layout.removeListener(markNeedsLayout);
    _layout = value;
    _anchorTop = null;
    if (attached) _layout.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  set marks(NoteMarks value) {
    if (value == _marks) return;
    if (attached) _marks.removeListener(markNeedsPaint);
    _marks = value;
    if (attached) _marks.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  EdgeInsets get padding => _padding;

  /// The scroll offset of the top of the view, in the coordinates of the
  /// column of lines.
  double get _viewTop => _offset.pixels - _padding.top;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(markNeedsLayout);
    _layout.addListener(markNeedsLayout);
    _marks.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _offset.removeListener(markNeedsLayout);
    _layout.removeListener(markNeedsLayout);
    _marks.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    for (final label in _labels.values) {
      label.dispose();
    }
    super.dispose();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    _layout.width = math.max(0, size.width - _padding.horizontal);
    _offset.applyViewportDimension(size.height);
    for (var round = 0; round < 8; round++) {
      _fill();
      final extent = _layout.height + _padding.vertical;
      if (_offset.applyContentDimensions(0, math.max(0, extent - size.height))) break;
    }
  }

  /// Lays out the lines in view, keeping the anchor line where it was on
  /// screen when lines above it changed height.
  void _fill() {
    final known = _anchorTop;
    if (known != null) {
      final moved = _layout.top(_layout.anchor) - known;
      if (moved != 0) _offset.correctBy(moved);
    }
    final top = _viewTop;
    final anchor = _layout.lineAtY(top);
    final anchorTop = _layout.top(anchor);
    final count = _layout.text.lineCount;
    var last = anchor;
    while (last < count) {
      _layout.painter(last);
      if (_layout.top(last + 1) > top + size.height + _cache) break;
      last++;
    }
    var first = anchor;
    while (first > 0 && _layout.top(first) > top - _cache) {
      _layout.painter(--first);
    }
    final moved = _layout.top(anchor) - anchorTop;
    if (moved != 0) _offset.correctBy(moved);
    _layout.anchor = anchor;
    _anchorTop = _layout.top(anchor);
    _first = first;
    _last = math.min(last, count - 1);
    _layout.forget(_first, _last);
  }

  /// The offset of the text nearest to [local], a point of this box.
  int offsetAt(Offset local) => _layout.offsetAt(local - Offset(_padding.left, -_viewTop));

  /// The offset of the box of a task at [local], a point of this box, or
  /// null.
  int? taskAt(Offset local) => _layout.taskAt(local - Offset(_padding.left, -_viewTop));

  /// The link or picture at [local], a point of this box, or null.
  NoteLink? linkAt(Offset local) => _layout.linkAt(local - Offset(_padding.left, -_viewTop));

  /// The caret before [offset], in the coordinates of this box.
  Rect caretRect(int offset) => _layout.caretRect(offset).shift(Offset(_padding.left, -_viewTop));

  /// The caret before [offset], in the coordinates of the scrolled content.
  Rect contentCaretRect(int offset) => _layout.caretRect(offset).shift(Offset(_padding.left, _padding.top));

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final text = _layout.text;
    final theme = _layout.theme;
    final top = _viewTop;
    final bottom = top + size.height;
    canvas
      ..save()
      ..clipRect(offset & size)
      ..translate(offset.dx + _padding.left, offset.dy - top);
    final width = _layout.width;
    final block = Paint()..color = theme.codeBackground;
    final selection = Paint()..color = theme.selection;
    final s = _marks;
    for (var i = _first; i <= _last; i++) {
      final y = _layout.top(i);
      final h = _layout.lineHeight(i);
      if (y > bottom) break;
      if (y + h < top) continue;
      final view = _layout.view(i);
      final start = text.lineStart(i), end = text.lineEnd(i);
      final callout = _layout.syntax.line(i).callout;
      if (callout != null) {
        canvas.drawRect(Rect.fromLTWH(-8, y, width + 16, h), Paint()..color = theme.callouts[callout.index].withValues(alpha: 0.12));
      } else if (_layout.syntax.inBlock(i)) {
        canvas.drawRect(Rect.fromLTWH(-8, y, width + 16, h), block);
      }
      for (final p in s.passages) {
        _range(canvas, i, y, start, end, p.from, p.to, Paint()..color = p.color);
      }
      for (final peer in s.peers) {
        final from = math.min(peer.base, peer.extent), to = math.max(peer.base, peer.extent);
        _range(canvas, i, y, start, end, from, to, Paint()..color = theme.peer(peer.sid).withValues(alpha: 0.2));
      }
      _range(canvas, i, y, start, end, s.start, s.end, selection);
      view.painter.paint(canvas, Offset(0, y));
      for (final o in view.ornaments) {
        _ornament(canvas, o, o.rect.shift(Offset(0, y)), y, h, theme, callout);
      }
      if (s.composing.isValid && !s.composing.isCollapsed) {
        _underline(canvas, i, y, start, end, s.composing, theme.text.color ?? const Color(0xFF000000));
      }
    }
    for (final peer in s.peers) {
      if (peer.extent < text.lineStart(_first) || peer.extent > text.lineEnd(_last)) continue;
      _peerCaret(canvas, _layout.caretRect(peer.extent), theme.peer(peer.sid), peer.name);
    }
    if (s.caret && s.base == s.extent) {
      canvas.drawRect(_layout.caretRect(s.extent), Paint()..color = theme.caret);
    }
    canvas.restore();
  }

  /// Fills what [from] to [to] covers of line [i]; a selection going on past
  /// the line's end covers a space's width after it, standing for its "\n".
  void _range(Canvas canvas, int i, double y, int start, int end, int from, int to, Paint paint) {
    if (from >= to || to < start || from > end) return;
    for (final box in _layout.boxes(i, math.max(from, start) - start, math.min(to, end) - start)) {
      canvas.drawRect(box.shift(Offset(0, y)), paint);
    }
    if (to > end) {
      final caret = _layout.caretRect(end);
      canvas.drawRect(Rect.fromLTWH(caret.left, caret.top, caret.height / 3, caret.height), paint);
    }
  }

  void _underline(Canvas canvas, int i, double y, int start, int end, TextRange range, Color color) {
    if (range.end < start || range.start > end) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final box in _layout.boxes(i, math.max(range.start, start) - start, math.min(range.end, end) - start)) {
      final r = box.shift(Offset(0, y));
      canvas.drawLine(r.bottomLeft.translate(0, -1), r.bottomRight.translate(0, -1), paint);
    }
  }

  /// The box of a task, the bar of a quote, a rule or a picture, over
  /// [rect]; a bar runs the height of the line, from [y] for [h].
  void _ornament(Canvas canvas, Ornament o, Rect rect, double y, double h, BrefTheme theme, CalloutKind? callout) {
    final kind = o.kind;
    switch (kind) {
      case SwapKind.picture:
        final info = _layout.cache?.picture(o.text);
        if (info != null) paintImage(canvas: canvas, rect: rect, image: info.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
      case SwapKind.bar:
        canvas.drawRect(Rect.fromLTWH(rect.left + 1, y, 3, h), Paint()..color = callout == null ? theme.markup : theme.callouts[callout.index]);
      case SwapKind.rule:
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.center.dy - 0.5, rect.width, 1), Paint()..color = theme.markup);
      case SwapKind.box || SwapKind.doneBox:
        final side = math.min(rect.width, rect.height) * 0.8;
        final box = RRect.fromRectAndRadius(Rect.fromCenter(center: rect.center, width: side, height: side), Radius.circular(side / 5));
        if (kind == SwapKind.box) {
          canvas.drawRRect(
            box,
            Paint()
              ..color = theme.markup
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
          break;
        }
        canvas.drawRRect(box, Paint()..color = theme.accent);
        final check = Path()
          ..moveTo(box.left + side * 0.22, box.top + side * 0.52)
          ..lineTo(box.left + side * 0.42, box.top + side * 0.72)
          ..lineTo(box.left + side * 0.78, box.top + side * 0.3);
        canvas.drawPath(
          check,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = side / 8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      default:
    }
  }

  /// Someone's caret, with their name on a tag above it.
  void _peerCaret(Canvas canvas, Rect caret, Color color, String name) {
    canvas.drawRect(caret, Paint()..color = color);
    if (name.isEmpty) return;
    final label = _labels[name] ??= TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(color: const Color(0xFFFFFFFF), fontSize: 11, fontWeight: FontWeight.w600, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 160);
    final tag = Rect.fromLTWH(caret.left, caret.top - label.height - 4, label.width + 8, label.height + 4);
    canvas.drawRRect(
      RRect.fromRectAndCorners(tag, topLeft: const Radius.circular(3), topRight: const Radius.circular(3), bottomRight: const Radius.circular(3)),
      Paint()..color = color,
    );
    label.paint(canvas, tag.topLeft + const Offset(4, 2));
  }
}
