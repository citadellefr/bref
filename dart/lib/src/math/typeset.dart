import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextStyle;

import 'box.dart';
import 'font.dart';
import 'parse.dart';
import 'symbols.dart';

/// A formula laid out, ready to be drawn.
class Formula {
  Formula(this._box);

  final MathBox _box;

  double get width => _box.width;

  /// How far it rises above its baseline, and how far it goes below.
  double get height => _box.height;

  double get depth => _box.depth;

  /// Draws the formula, its baseline starting at [origin].
  void paint(ui.Canvas canvas, ui.Offset origin) => _box.paint(canvas, origin.dx, origin.dy);
}

/// Lays out [tex] in [font] at [size], as a line of its own when [display],
/// in the color of [text], whose font shows the characters [font] lacks;
/// what cannot be read is shown in [error].
Formula typeset(
  String tex,
  MathFont font, {
  required double size,
  required bool display,
  required TextStyle text,
  required ui.Color error,
}) {
  final setter = _Setter(font, size, text, error);
  return Formula(setter.row(parseMath(tex), _Style(display ? 0 : 1, false)));
}

/// How big and how tight a piece is set: [level] is 0 for a line of its own,
/// 1 for text, 2 for a script and 3 for the script of a script; [cramped]
/// under a bar, where exponents are kept low.
class _Style {
  const _Style(this.level, this.cramped);

  final int level;
  final bool cramped;

  _Style get sup => _Style(level < 2 ? 2 : 3, cramped);

  _Style get sub => _Style(level < 2 ? 2 : 3, true);

  _Style get num => _Style(math.min(level + 1, 3), cramped);

  _Style get den => _Style(math.min(level + 1, 3), true);

  _Style get cramp => _Style(level, true);
}

/// A piece laid out, with what its neighbors and its scripts need to know.
class _Item {
  _Item(this.box, this.cls, {this.italic = 0, this.char = false, this.limits = 0, this.attach, this.space = false});

  final MathBox box;
  final Cls cls;

  /// How far the slant of a single glyph leans over its end.
  final double italic;

  /// Whether the piece is a single glyph.
  final bool char;

  /// Whether scripts go over and under: never (0), on a line of its own (1)
  /// or always (2).
  final int limits;

  /// Where an accent sits over it, when its glyph says.
  final double? attach;

  /// Whether it is room rather than a piece.
  final bool space;
}

/// A glyph, whole or built of parts, with where its ink starts and ends.
typedef _Shape = ({MathBox box, double left, double right, int? glyph});

/// The room between two pieces, by class: none (0), thin (1), and thin (2),
/// medium (3) or thick (4) but in scripts.
const _spacing = ['01340002', '11040002', '33003003', '44004004', '00000000', '01340002', '22022222', '21342022'];

class _Setter {
  _Setter(this.font, this.size, this.text, ui.Color error)
      : ink = ui.Paint()..color = text.color ?? const ui.Color(0xFF000000),
        errorInk = ui.Paint()..color = error;

  final MathFont font;
  final double size;
  final TextStyle text;
  ui.Paint ink;
  final ui.Paint errorInk;

  double _em(_Style s) => size * (s.level < 2 ? 1 : (s.level == 2 ? font.scriptPercent : font.scriptScriptPercent) / 100);

  double _unit(_Style s) => _em(s) / font.unitsPerEm;

  double _k(MathConstant c, _Style s) => font[c] * _unit(s);

  double _axis(_Style s) => _k(MathConstant.axisHeight, s);

  MathBox row(List<Node> nodes, _Style s) => _join([for (final n in nodes) _node(n, s)], s);

  /// The one piece [nodes] are, or their row as an ordinary one.
  _Item _single(List<Node> nodes, _Style s) => nodes.length == 1 ? _node(nodes.single, s) : _Item(row(nodes, s), Cls.ord);

  /// [items] side by side, with the room their classes ask for.
  MathBox _join(List<_Item> items, _Style s) {
    if (items.length == 1) return items.single.box;
    final classes = <Cls?>[for (final item in items) item.space ? null : item.cls];
    var before = -1;
    for (var k = 0; k < classes.length; k++) {
      final c = classes[k];
      if (c == null) continue;
      final prev = before < 0 ? null : classes[before];
      if (c == Cls.bin && (prev == null || prev == Cls.bin || prev == Cls.op || prev == Cls.rel || prev == Cls.open || prev == Cls.punct)) {
        classes[k] = Cls.ord;
      } else if (prev == Cls.bin && (c == Cls.rel || c == Cls.close || c == Cls.punct)) {
        classes[before] = Cls.ord;
      }
      before = k;
    }
    if (before >= 0 && classes[before] == Cls.bin) classes[before] = Cls.ord;

    final boxes = <MathBox>[];
    final mu = _em(s) / 18;
    Cls? prev;
    for (var k = 0; k < items.length; k++) {
      final c = classes[k];
      if (c != null) {
        if (prev != null) {
          final room = _spacing[prev.index].codeUnitAt(c.index) - 0x30;
          if (room == 1 || room > 1 && s.level < 2) boxes.add(SpaceBox(mu * (room == 1 ? 3 : room + 1)));
        }
        prev = c;
      }
      boxes.add(items[k].box);
    }
    return GroupBox.row(boxes);
  }

  _Item _node(Node n, _Style s) {
    switch (n) {
      case Sym():
        return _glyph(font.glyph(n.rune) == 0 ? n.plain ?? n.rune : n.rune, n.cls, s);
      case Group():
        if (n.body.length != 1) return _Item(row(n.body, s), Cls.ord);
        final only = _node(n.body.single, s);
        return _Item(only.box, Cls.ord, italic: only.italic, char: only.char, attach: only.attach);
      case Scripts():
        return _scripts(n, s);
      case Frac():
        return _frac(n, s);
      case Radical():
        return _radical(n, s);
      case Delimited():
        return _delimited(n, s);
      case Big():
        const sizes = [1.2, 1.8, 2.4, 3.0];
        return _Item(_delimiter(n.rune, sizes[n.size - 1] * size - 0.01, s), n.cls);
      case Accent():
        return _accent(n, s);
      case Line():
        return _line(n, s);
      case Stack():
        return _stack(_Item(row(n.base, s), n.cls), n.above, n.below, s);
      case Arrow():
        return _arrow(n, s);
      case OpName():
        final words = n.name.split(' ');
        final boxes = <MathBox>[
          for (var k = 0; k < words.length; k++) ...[
            if (k > 0) SpaceBox(_em(s) / 6),
            _text(words[k], Variant.roman, s, ink),
          ],
        ];
        return _Item(GroupBox.row(boxes), Cls.op, limits: n.limits ? 1 : 0);
      case TextNode():
        return _Item(_text(n.text, n.variant, s, ink), Cls.ord);
      case Space():
        return _Item(SpaceBox(n.mu * _em(s) / 18), Cls.ord, space: true);
      case Styled():
        return _Item(row(n.body, _Style(n.level, s.cramped)), Cls.ord);
      case Classed():
        return _Item(row(n.body, s), n.cls, limits: n.cls == Cls.op ? 1 : 0);
      case Colored():
        final saved = ink;
        ink = ui.Paint()..color = n.color;
        final item = _single(n.body, s);
        ink = saved;
        return item;
      case Phantom():
        final box = row(n.body, s);
        return _Item(SpaceBox(n.width ? box.width : 0, n.height ? box.height : 0, n.height ? box.depth : 0), Cls.ord);
      case Boxed():
        final box = row(n.body, s);
        final pad = 0.34 * _em(s);
        final frame = FrameBox(box.width + 2 * pad, box.height + pad, box.depth + pad, 0.04 * _em(s), ink);
        return _Item(GroupBox([(box: frame, dx: 0, up: 0), (box: box, dx: pad, up: 0)], frame.width, frame.height, frame.depth), Cls.ord);
      case Not():
        final inner = _node(n.body, s);
        final shape = font.shape(font.glyph(0x338));
        final u = _unit(s);
        final slash = GlyphBox(shape, u, 0, ink);
        final dx = inner.box.width / 2 - (shape.left + shape.right) / 2 * u;
        final box = GroupBox.around([(box: inner.box, dx: 0, up: 0), (box: slash, dx: dx, up: 0)]);
        return _Item(GroupBox(box.children, inner.box.width, box.height, box.depth), inner.cls);
      case Table():
        return _table(n, s);
      case Bad():
        return _Item(_text(n.text, Variant.mono, s, errorInk), Cls.ord);
    }
  }

  _Item _glyph(int rune, Cls cls, _Style s) {
    var g = font.glyph(rune);
    if (g == 0) return _Item(_engine(String.fromCharCode(rune), s, ink), cls);
    final u = _unit(s);
    if (cls == Cls.op) {
      if (s.level == 0) {
        for (final v in font.construction(g)?.variants ?? const <({int glyph, int advance})>[]) {
          g = v.glyph;
          if (v.advance >= font.displayOperatorMinHeight) break;
        }
      }
      final box = GlyphBox(font.shape(g), u, font.advance(g) * u, ink);
      final centered = GroupBox.raised(box, _axis(s) - (box.height - box.depth) / 2);
      return _Item(centered, cls, italic: font.italic(g) * u, limits: besideLimits(rune) ? 0 : 1);
    }
    final italic = font.italic(g) * u;
    final attach = font.accent(g);
    return _Item(
      GlyphBox(font.shape(g), u, font.advance(g) * u + italic, ink),
      cls,
      italic: italic,
      char: true,
      attach: attach == null ? null : attach * u,
    );
  }

  /// [text] in upright letters, or in those of [variant].
  MathBox _text(String text, Variant variant, _Style s, ui.Paint ink) {
    final boxes = <MathBox>[];
    final missing = StringBuffer();
    void flush() {
      if (missing.isEmpty) return;
      boxes.add(_engine(missing.toString(), s, ink));
      missing.clear();
    }

    final u = _unit(s);
    for (final rune in text.runes) {
      var g = variant == Variant.roman ? 0 : font.glyph(styled(rune, variant));
      if (g == 0) g = font.glyph(rune);
      if (g == 0) {
        missing.writeCharCode(rune);
        continue;
      }
      flush();
      boxes.add(GlyphBox(font.shape(g), u, font.advance(g) * u, ink));
    }
    flush();
    return GroupBox.row(boxes);
  }

  /// [text] set by the engine, in the font of the note.
  MathBox _engine(String text, _Style s, ui.Paint ink) {
    final style = this.text.copyWith(fontSize: _em(s), color: ink.color, height: 1);
    final builder = ui.ParagraphBuilder(style.getParagraphStyle())
      ..pushStyle(style.getTextStyle())
      ..addText(text);
    return TextBox(builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity)));
  }

  _Item _scripts(Scripts n, _Style s) {
    final base = n.base == null ? _Item(const SpaceBox(0), Cls.ord) : _node(n.base!, s);
    final over = n.limits ?? (base.limits == 2 || base.limits == 1 && s.level == 0);
    if (over && n.primes == 0) return _stack(base, n.sup, n.sub, s);

    final nucleus = base.box;
    final sup = n.sup == null ? null : row(n.sup!, s.sup);
    final sub = n.sub == null ? null : row(n.sub!, s.sub);
    var up = 0.0, down = 0.0;
    if (!base.char) {
      up = nucleus.height - _k(MathConstant.superscriptBaselineDropMax, s.sup);
      down = nucleus.depth + _k(MathConstant.subscriptBaselineDropMin, s.sub);
    }
    final children = <Placed>[(box: nucleus, dx: 0, up: 0)];
    var x = nucleus.width;
    if (n.primes > 0) {
      final primes = _primes(n.primes, s);
      children.add((box: primes, dx: x, up: math.max(0, nucleus.height - primes.height)));
      x += primes.width;
    }
    var width = x;
    final after = _k(MathConstant.spaceAfterScript, s);
    if (sup != null) {
      final shift = s.cramped ? MathConstant.superscriptShiftUpCramped : MathConstant.superscriptShiftUp;
      up = math.max(up, math.max(_k(shift, s), sup.depth + _k(MathConstant.superscriptBottomMin, s)));
    }
    if (sub != null) {
      down = math.max(down, _k(MathConstant.subscriptShiftDown, s));
      if (sup == null) {
        down = math.max(down, sub.height - _k(MathConstant.subscriptTopMax, s));
      } else {
        final gap = up - sup.depth - (sub.height - down);
        final least = _k(MathConstant.subSuperscriptGapMin, s);
        if (gap < least) {
          down += least - gap;
          final lift = _k(MathConstant.superscriptBottomMaxWithSubscript, s) - (up - sup.depth);
          if (lift > 0) {
            up += lift;
            down -= lift;
          }
        }
      }
    }
    if (sup != null) {
      children.add((box: sup, dx: x, up: up));
      width = math.max(width, x + sup.width + after);
    }
    if (sub != null) {
      final dx = nucleus.width - base.italic;
      children.add((box: sub, dx: dx, up: -down));
      width = math.max(width, dx + sub.width + after);
    }
    final box = GroupBox.around(children);
    return _Item(GroupBox(children, width, box.height, box.depth), base.cls);
  }

  MathBox _primes(int count, _Style s) {
    const runes = [0x2032, 0x2033, 0x2034, 0x2057];
    final whole = count <= runes.length ? font.glyph(runes[count - 1]) : 0;
    final u = _unit(s);
    if (whole != 0) return GlyphBox(font.shape(whole), u, font.advance(whole) * u, ink);
    final one = font.glyph(runes.first);
    return GroupBox.row(List.filled(count, GlyphBox(font.shape(one), u, font.advance(one) * u, ink)));
  }

  /// [base] with [above] and [below] centered over and under it.
  _Item _stack(_Item base, List<Node>? above, List<Node>? below, _Style s) {
    final nucleus = base.box;
    final sup = above == null ? null : row(above, s.sup);
    final sub = below == null ? null : row(below, s.sub);
    final width = math.max(nucleus.width, math.max(sup?.width ?? 0, sub?.width ?? 0));
    final lean = base.cls == Cls.op ? base.italic / 2 : 0.0;
    final children = <Placed>[(box: nucleus, dx: (width - nucleus.width) / 2, up: 0)];
    if (sup != null) {
      final gap = math.max(_k(MathConstant.upperLimitGapMin, s), _k(MathConstant.upperLimitBaselineRiseMin, s) - sup.depth);
      children.add((box: sup, dx: (width - sup.width) / 2 + lean, up: nucleus.height + gap + sup.depth));
    }
    if (sub != null) {
      final gap = math.max(_k(MathConstant.lowerLimitGapMin, s), _k(MathConstant.lowerLimitBaselineDropMin, s) - sub.height);
      children.add((box: sub, dx: (width - sub.width) / 2 - lean, up: -(nucleus.depth + gap + sub.height)));
    }
    final box = GroupBox.around(children);
    return _Item(GroupBox(children, width, box.height, box.depth), base.cls);
  }

  _Item _frac(Frac n, _Style outer) {
    final s = n.level == null ? outer : _Style(n.level!, outer.cramped);
    final display = s.level == 0;
    final num = row(n.num, s.num), den = row(n.den, s.den);
    final pad = 0.12 * _em(s);
    final width = math.max(num.width, den.width);
    final axis = _axis(s);
    double up, down;
    final children = <Placed>[];
    if (n.rule) {
      final t = _k(MathConstant.fractionRuleThickness, s);
      up = _k(display ? MathConstant.fractionNumeratorDisplayStyleShiftUp : MathConstant.fractionNumeratorShiftUp, s);
      down = _k(display ? MathConstant.fractionDenominatorDisplayStyleShiftDown : MathConstant.fractionDenominatorShiftDown, s);
      final above = _k(display ? MathConstant.fractionNumDisplayStyleGapMin : MathConstant.fractionNumeratorGapMin, s);
      final below = _k(display ? MathConstant.fractionDenomDisplayStyleGapMin : MathConstant.fractionDenominatorGapMin, s);
      up = math.max(up, axis + t / 2 + above + num.depth);
      down = math.max(down, den.height + below + t / 2 - axis);
      children.add((box: RuleBox(width, axis + t / 2, t / 2 - axis, ink), dx: pad, up: 0));
    } else {
      up = _k(display ? MathConstant.stackTopDisplayStyleShiftUp : MathConstant.stackTopShiftUp, s);
      down = _k(display ? MathConstant.stackBottomDisplayStyleShiftDown : MathConstant.stackBottomShiftDown, s);
      final gap = up - num.depth - (den.height - down);
      final least = _k(display ? MathConstant.stackDisplayStyleGapMin : MathConstant.stackGapMin, s);
      if (gap < least) {
        up += (least - gap) / 2;
        down += (least - gap) / 2;
      }
    }
    children
      ..add((box: num, dx: pad + (width - num.width) / 2, up: up))
      ..add((box: den, dx: pad + (width - den.width) / 2, up: -down));
    final box = GroupBox.around(children);
    return _Item(GroupBox(children, width + 2 * pad, box.height, box.depth), Cls.ord);
  }

  _Item _radical(Radical n, _Style s) {
    final body = row(n.body, s.cramp);
    final u = _unit(s);
    final t = _k(MathConstant.radicalRuleThickness, s);
    var gap = _k(s.level == 0 ? MathConstant.radicalDisplayStyleVerticalGap : MathConstant.radicalVerticalGap, s);
    final wanted = body.height + body.depth + gap + t;
    final surd = _stretch(font.glyph(0x221A), wanted, u, horizontal: false).box;
    final total = surd.height + surd.depth;
    if (total > wanted) gap += (total - wanted) / 2;
    final top = body.height + gap + t;
    final surdUp = top - surd.height;

    var x = 0.0;
    final children = <Placed>[];
    final index = n.index;
    if (index != null) {
      final degree = row(index, const _Style(3, false));
      final after = _k(MathConstant.radicalKernAfterDegree, s);
      x = math.max(0, _k(MathConstant.radicalKernBeforeDegree, s) + degree.width + after);
      final bottom = surdUp - surd.depth + font.radicalDegreeRaisePercent / 100 * total;
      children.add((box: degree, dx: x - after - degree.width, up: bottom + degree.depth));
    }
    children
      ..add((box: surd, dx: x, up: surdUp))
      ..add((box: RuleBox(body.width, top, t - top, ink), dx: x + surd.width, up: 0))
      ..add((box: body, dx: x + surd.width, up: 0));
    final box = GroupBox.around(children);
    final height = math.max(box.height, top + _k(MathConstant.radicalExtraAscender, s));
    return _Item(GroupBox(children, box.width, height, box.depth), Cls.ord);
  }

  /// The glyph as it is, with where its ink starts and ends.
  _Shape _whole(int glyph, double u) {
    final shape = font.shape(glyph);
    return (box: GlyphBox(shape, u, font.advance(glyph) * u, ink), left: shape.left * u, right: shape.right * u, glyph: glyph);
  }

  /// The form of [glyph] at least [target] tall, or wide when [horizontal]:
  /// the smallest of those the font has, or one built of parts.
  _Shape _stretch(int glyph, double target, double u, {required bool horizontal}) {
    final c = font.construction(glyph, horizontal: horizontal);
    final shape = font.shape(glyph);
    final own = horizontal ? shape.right - shape.left : shape.height + shape.depth;
    if (c == null || own * u >= target) return _whole(glyph, u);
    var best = glyph;
    for (final v in c.variants) {
      best = v.glyph;
      if (v.advance * u >= target) return _whole(best, u);
    }
    if (c.parts.isEmpty) return _whole(best, u);

    final overlap = font.minOverlap.toDouble();
    var parts = c.parts;
    var length = 0.0;
    for (var repeat = 0; repeat < 400; repeat++) {
      parts = [
        for (final p in c.parts)
          if (p.extender) ...List.filled(repeat, p) else p,
      ];
      length = -overlap * (parts.length - 1);
      for (final p in parts) {
        length += p.advance;
      }
      if (length * u >= target || !c.parts.any((p) => p.extender)) break;
    }
    final rooms = [
      for (var k = 0; k + 1 < parts.length; k++) math.max(0.0, math.min(parts[k].end, parts[k + 1].start) - overlap),
    ];
    final room = rooms.fold(0.0, (a, b) => a + b);
    final excess = length - target / u;
    final squeeze = room <= 0 || excess <= 0 ? 0.0 : math.min(1.0, excess / room);

    final children = <Placed>[];
    var at = 0.0, across = 0.0, height = 0.0, depth = 0.0;
    var left = double.infinity, right = double.negativeInfinity;
    for (var k = 0; k < parts.length; k++) {
      final g = parts[k].glyph;
      final piece = font.shape(g);
      final box = GlyphBox(piece, u, font.advance(g) * u, ink);
      children.add(horizontal ? (box: box, dx: at * u, up: 0) : (box: box, dx: 0, up: at * u));
      if (horizontal) {
        left = math.min(left, (at + piece.left) * u);
        right = math.max(right, (at + piece.right) * u);
        height = math.max(height, box.height);
        depth = math.max(depth, box.depth);
      } else {
        left = math.min(left, piece.left * u);
        right = math.max(right, piece.right * u);
        across = math.max(across, box.width);
      }
      at += parts[k].advance;
      if (k < rooms.length) at -= overlap + rooms[k] * squeeze;
    }
    final box = horizontal ? GroupBox(children, at * u, height, depth) : GroupBox(children, across, at * u, 0);
    return (box: box, left: left, right: right, glyph: null);
  }

  /// The delimiter [rune] at least [target] tall, centered on the axis.
  MathBox _delimiter(int rune, double target, _Style s) {
    if (rune == 0) return SpaceBox(0.12 * _em(s));
    final g = font.glyph(rune);
    if (g == 0) return _engine(String.fromCharCode(rune), s, ink);
    final box = _stretch(g, target, _unit(s), horizontal: false).box;
    return GroupBox.raised(box, _axis(s) - (box.height - box.depth) / 2);
  }

  _Item _delimited(Delimited n, _Style s) {
    final parts = [
      for (final p in n.parts) [for (final node in p) _node(node, s)],
    ];
    var height = 0.0, depth = 0.0;
    for (final item in parts.expand((p) => p)) {
      height = math.max(height, item.box.height);
      depth = math.max(depth, item.box.depth);
    }
    final axis = _axis(s);
    final reach = math.max(height - axis, depth + axis);
    final target = math.max(reach * 2 * 0.901, reach * 2 - 0.5 * _em(s));
    final items = [_Item(_delimiter(n.left, target, s), Cls.open)];
    for (var k = 0; k < parts.length; k++) {
      items.addAll(parts[k]);
      if (k < n.middles.length) items.add(_Item(_delimiter(n.middles[k], target, s), Cls.ord));
    }
    items.add(_Item(_delimiter(n.right, target, s), Cls.close));
    return _Item(_join(items, s), Cls.inner);
  }

  _Item _accent(Accent n, _Style s) {
    final inner = _single(n.body, s.cramp);
    final body = inner.box;
    final g = font.glyph(n.rune);
    if (g == 0) return _Item(body, Cls.ord);
    final u = _unit(s);
    final shape = n.stretch ? _stretch(g, body.width, u, horizontal: true) : _whole(g, u);
    final middle = (shape.left + shape.right) / 2;
    final limits = n.limits ? 2 : 0;
    if (n.under) {
      final up = -(body.depth + 0.1 * _em(s)) - shape.box.height;
      final children = <Placed>[(box: body, dx: 0, up: 0), (box: shape.box, dx: body.width / 2 - middle, up: up)];
      return _Item(GroupBox(children, body.width, body.height, shape.box.depth - up), Cls.ord, limits: limits);
    }
    var dx = body.width / 2 - middle;
    final glyph = shape.glyph;
    if (!n.stretch && glyph != null) {
      final over = inner.attach ?? (body.width - inner.italic) / 2;
      final under = font.accent(glyph);
      dx = over - (under == null ? middle : under * u);
    }
    final up = body.height - math.min(body.height, _k(MathConstant.accentBaseHeight, s));
    final children = <Placed>[(box: body, dx: 0, up: 0), (box: shape.box, dx: dx, up: up)];
    return _Item(GroupBox(children, body.width, math.max(body.height, shape.box.height + up), body.depth), Cls.ord, limits: limits);
  }

  _Item _line(Line n, _Style s) {
    final body = row(n.body, n.over ? s.cramp : s);
    if (n.over) {
      final t = _k(MathConstant.overbarRuleThickness, s);
      final bottom = body.height + _k(MathConstant.overbarVerticalGap, s);
      final children = <Placed>[(box: body, dx: 0, up: 0), (box: RuleBox(body.width, bottom + t, -bottom, ink), dx: 0, up: 0)];
      return _Item(GroupBox(children, body.width, bottom + t + _k(MathConstant.overbarExtraAscender, s), body.depth), Cls.ord);
    }
    final t = _k(MathConstant.underbarRuleThickness, s);
    final top = body.depth + _k(MathConstant.underbarVerticalGap, s);
    final children = <Placed>[(box: body, dx: 0, up: 0), (box: RuleBox(body.width, -top, top + t, ink), dx: 0, up: 0)];
    return _Item(GroupBox(children, body.width, body.height, top + t + _k(MathConstant.underbarExtraDescender, s)), Cls.ord);
  }

  _Item _arrow(Arrow n, _Style s) {
    final above = row(n.above, s.sup);
    final below = n.below == null ? null : row(n.below!, s.sub);
    final em = _em(s);
    final g = font.glyph(n.rune);
    final wanted = math.max(above.width, below?.width ?? 0) + 0.8 * em;
    final arrow = _stretch(g, math.max(wanted, 1.6 * em), _unit(s), horizontal: true).box;
    final gap = 0.12 * em;
    final children = <Placed>[
      (box: arrow, dx: 0, up: 0),
      (box: above, dx: (arrow.width - above.width) / 2, up: arrow.height + gap + above.depth),
      if (below != null) (box: below, dx: (arrow.width - below.width) / 2, up: -arrow.depth - gap - below.height),
    ];
    final box = GroupBox.around(children);
    return _Item(GroupBox(children, arrow.width, box.height, box.depth), Cls.rel);
  }

  _Item _table(Table n, _Style s) {
    final cell = n.display ? _Style(0, s.cramped) : (s.level == 0 ? _Style(1, s.cramped) : s);
    final em = _em(s);
    final rows = [
      for (final r in n.rows)
        [
          for (var c = 0; c < r.length; c++) row(n.pairs && c.isOdd ? [const Group([]), ...r[c]] : r[c], cell),
        ],
    ];
    final columns = rows.fold(0, (a, r) => math.max(a, r.length));
    final widths = List.filled(columns, 0.0);
    final heights = <double>[], depths = <double>[];
    for (final r in rows) {
      var height = 0.84 * em, depth = 0.36 * em;
      for (var c = 0; c < r.length; c++) {
        widths[c] = math.max(widths[c], r[c].width);
        height = math.max(height, r[c].height);
        depth = math.max(depth, r[c].depth);
      }
      heights.add(height);
      depths.add(depth);
    }
    final lefts = <double>[];
    var x = 0.0;
    for (var c = 0; c < columns; c++) {
      if (c > 0) x += (n.pairs ? (c.isEven ? 1.0 : 0.0) : n.sep) * em;
      lefts.add(x);
      x += widths[c];
    }
    var total = n.jot * em * (rows.length - 1);
    for (var r = 0; r < rows.length; r++) {
      total += heights[r] + depths[r];
    }
    final top = _axis(s) + total / 2;
    final children = <Placed>[];
    var y = top;
    for (var r = 0; r < rows.length; r++) {
      y -= heights[r];
      for (var c = 0; c < rows[r].length; c++) {
        final box = rows[r][c];
        final align = n.pairs ? (c.isEven ? 'r' : 'l') : (c < n.aligns.length ? n.aligns[c] : 'c');
        final slack = widths[c] - box.width;
        children.add((box: box, dx: lefts[c] + (align == 'l' ? 0 : (align == 'r' ? slack : slack / 2)), up: y));
      }
      y -= depths[r] + n.jot * em;
    }
    return _Item(GroupBox(children, x, top, total - top), Cls.ord);
  }
}
