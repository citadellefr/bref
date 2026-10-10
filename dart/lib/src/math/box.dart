import 'dart:math' as math;
import 'dart:ui';

import 'font.dart';

/// A piece of a formula laid out: [width] along the baseline, [height] above
/// it and [depth] below.
sealed class MathBox {
  const MathBox();

  double get width;

  double get height;

  double get depth;

  /// Draws the box, the left end of its baseline at ([x], [y]).
  void paint(Canvas canvas, double x, double y);
}

/// Room left empty.
class SpaceBox extends MathBox {
  const SpaceBox(this.width, [this.height = 0, this.depth = 0]);

  @override
  final double width, height, depth;

  @override
  void paint(Canvas canvas, double x, double y) {}
}

/// A glyph of the font at [scale], its outline filled.
class GlyphBox extends MathBox {
  GlyphBox(this.shape, this.scale, this.width, this.ink)
      : height = shape.height * scale,
        depth = shape.depth * scale;

  final GlyphShape shape;
  final double scale;
  final Paint ink;

  @override
  final double width, height, depth;

  @override
  void paint(Canvas canvas, double x, double y) {
    canvas
      ..save()
      ..translate(x, y)
      ..scale(scale)
      ..drawPath(shape.path, ink)
      ..restore();
  }
}

/// A filled rectangle: the bar of a fraction, of a root.
class RuleBox extends MathBox {
  const RuleBox(this.width, this.height, this.depth, this.ink);

  final Paint ink;

  @override
  final double width, height, depth;

  @override
  void paint(Canvas canvas, double x, double y) => canvas.drawRect(Rect.fromLTRB(x, y - height, x + width, y + depth), ink);
}

/// The outline of a rectangle, drawn inside it.
class FrameBox extends MathBox {
  const FrameBox(this.width, this.height, this.depth, this.thickness, this.ink);

  final double thickness;
  final Paint ink;

  @override
  final double width, height, depth;

  @override
  void paint(Canvas canvas, double x, double y) {
    final t = thickness;
    canvas
      ..drawRect(Rect.fromLTRB(x, y - height, x + width, y - height + t), ink)
      ..drawRect(Rect.fromLTRB(x, y + depth - t, x + width, y + depth), ink)
      ..drawRect(Rect.fromLTRB(x, y - height, x + t, y + depth), ink)
      ..drawRect(Rect.fromLTRB(x + width - t, y - height, x + width, y + depth), ink);
  }
}

/// Text the font has no glyphs for, set by the engine.
class TextBox extends MathBox {
  TextBox(this.paragraph)
      : width = paragraph.maxIntrinsicWidth,
        height = paragraph.alphabeticBaseline,
        depth = paragraph.height - paragraph.alphabeticBaseline;

  final Paragraph paragraph;

  @override
  final double width, height, depth;

  @override
  void paint(Canvas canvas, double x, double y) => canvas.drawParagraph(paragraph, Offset(x, y - height));
}

/// A box in a [GroupBox]: [dx] to the right and [up] above its baseline.
typedef Placed = ({MathBox box, double dx, double up});

/// Boxes placed against one baseline.
class GroupBox extends MathBox {
  const GroupBox(this.children, this.width, this.height, this.depth);

  /// [boxes] one after the other on the baseline.
  factory GroupBox.row(List<MathBox> boxes) {
    final children = <Placed>[];
    var x = 0.0, height = 0.0, depth = 0.0;
    for (final b in boxes) {
      children.add((box: b, dx: x, up: 0));
      x += b.width;
      height = math.max(height, b.height);
      depth = math.max(depth, b.depth);
    }
    return GroupBox(children, x, height, depth);
  }

  /// [box] raised by [up].
  GroupBox.raised(MathBox box, double up) : this([(box: box, dx: 0, up: up)], box.width, box.height + up, box.depth - up);

  /// What [children] cover, from the baseline's start to the rightmost end.
  factory GroupBox.around(List<Placed> children) {
    var width = 0.0, height = double.negativeInfinity, depth = double.negativeInfinity;
    for (final c in children) {
      width = math.max(width, c.dx + c.box.width);
      height = math.max(height, c.box.height + c.up);
      depth = math.max(depth, c.box.depth - c.up);
    }
    return children.isEmpty ? const GroupBox([], 0, 0, 0) : GroupBox(children, width, height, depth);
  }

  final List<Placed> children;

  @override
  final double width, height, depth;

  @override
  void paint(Canvas canvas, double x, double y) {
    for (final c in children) {
      c.box.paint(canvas, x + c.dx, y - c.up);
    }
  }
}
