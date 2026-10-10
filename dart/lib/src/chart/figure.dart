import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../line_view.dart' show Figure;
import '../theme.dart';
import 'spec.dart';

typedef _Label = ({TextPainter text, Offset at, bool turned});

/// A chart laid out in a column of a given width: its title, its legend,
/// its axes and the room its data is drawn in.
class ChartFigure extends Figure {
  ChartFigure(this.spec, {required double width, required this.theme, required this._scaler}) {
    _build(math.max(120, math.min(width, _widest)));
  }

  static const _widest = 640.0;

  final ChartSpec spec;
  final BrefTheme theme;
  final TextScaler _scaler;

  final _labels = <_Label>[];
  final _swatches = <({Rect box, Color color})>[];

  /// The values of the grid lines, and where the abscissas go from and to
  /// when they are numbers.
  final _ticks = <double>[];
  var _plot = Rect.zero;
  var _lo = 0.0, _hi = 1.0;
  var _xLo = 0.0, _xHi = 1.0;
  var _numeric = false;

  @override
  Size size = Size.zero;

  bool get _stacked => spec.stacked && (spec.type == ChartType.bar || spec.type == ChartType.area);

  Color _color(int k) {
    final colors = theme.series;
    final color = colors[k % colors.length];
    return k < colors.length ? color : color.withValues(alpha: 0.55);
  }

  TextStyle get _small => theme.text.copyWith(fontSize: (theme.text.fontSize ?? 16) * 0.78, height: 1.2, color: theme.muted);

  TextPainter _text(String text, TextStyle style, double room) => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: _scaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(room, 1));

  void _build(double width) {
    var y = 0.0;
    if (spec.title.isNotEmpty) {
      final title = _text(spec.title, theme.text.copyWith(fontWeight: FontWeight.w600, height: 1.3), width);
      _labels.add((text: title, at: Offset((width - title.width) / 2, y), turned: false));
      y += title.height + 6;
    }
    final height = (width * 0.5).clamp(160.0, 320.0);
    if (spec.type == ChartType.pie) {
      y = _legend(_slices(), width, y);
      _plot = Rect.fromLTWH((width - height) / 2, y, height, height);
      y += height;
    } else {
      if (spec.series.length > 1) y = _legend([for (final s in spec.series) s.name], width, y);
      y = _axes(width, y, height);
    }
    size = Size(width, y);
  }

  /// The rows a pie draws: those of its first series that are more than
  /// nothing, each named with its share.
  List<String> _slices() {
    final values = spec.series.first.values;
    final total = _pieTotal;
    return [
      for (var i = 0; i < values.length; i++)
        if ((values[i] ?? 0) > 0) '${spec.categories[i]} ${(100 * values[i]! / total).round()} %',
    ];
  }

  double get _pieTotal => spec.series.first.values.fold(0.0, (a, v) => a + math.max(0, v ?? 0));

  /// Lays the legend out in centered rows from [top]; answers where it ends.
  double _legend(List<String> names, double width, double top) {
    if (names.isEmpty) return top;
    const swatch = 10.0, gap = 6.0, between = 16.0;
    final style = _small.copyWith(color: theme.text.color);
    final texts = [for (final n in names) _text(n, style, width - swatch - gap)];
    var y = top;
    for (var from = 0; from < texts.length;) {
      var to = from, row = 0.0;
      while (to < texts.length) {
        final item = swatch + gap + texts[to].width + (to > from ? between : 0);
        if (to > from && row + item > width) break;
        row += item;
        to++;
      }
      var x = (width - row) / 2;
      final line = texts[from].height;
      for (var k = from; k < to; k++) {
        _swatches.add((box: Rect.fromLTWH(x, y + (line - swatch) / 2, swatch, swatch), color: _color(k)));
        _labels.add((text: texts[k], at: Offset(x + swatch + gap, y), turned: false));
        x += swatch + gap + texts[k].width + between;
      }
      y += line + 4;
      from = to;
    }
    return y + 4;
  }

  /// Lays out the axes of a chart whose room for data is [height] tall,
  /// from [top]; answers where the chart ends.
  double _axes(double width, double top, double height) {
    var lo = double.infinity, hi = double.negativeInfinity;
    final rows = spec.categories.length;
    for (var i = 0; i < rows; i++) {
      var up = 0.0, down = 0.0;
      for (final s in spec.series) {
        final v = s.values[i];
        if (v == null) continue;
        if (_stacked) {
          v >= 0 ? up += v : down += v;
        } else {
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
      }
      if (_stacked) {
        lo = math.min(lo, down);
        hi = math.max(hi, up);
      }
    }
    if (spec.type == ChartType.bar || spec.type == ChartType.area) {
      lo = math.min(lo, 0);
      hi = math.max(hi, 0);
    }
    final (low, high, step) = _nice(lo, hi);
    _lo = low;
    _hi = high;
    final marks = <TextPainter>[];
    for (var k = 0; k <= ((_hi - _lo) / step).round(); k++) {
      _ticks.add(_lo + k * step);
      marks.add(_text(_format(_ticks.last, step), _small, width / 3));
    }
    final row = marks.first.height;
    final xs = spec.xs;
    _numeric = xs != null && spec.type != ChartType.bar;

    var left = marks.fold(0.0, (a, m) => math.max(a, m.width)) + 8;
    TextPainter? yLabel, xLabel;
    if (spec.yLabel.isNotEmpty) {
      yLabel = _text(spec.yLabel, _small, height);
      left += yLabel.height + 4;
    }
    if (spec.xLabel.isNotEmpty) xLabel = _text(spec.xLabel, _small, width);
    _plot = Rect.fromLTRB(left, top + row / 2, width - (_numeric ? 16 : 4), top + row / 2 + height);
    for (var k = 0; k < marks.length; k++) {
      _labels.add((text: marks[k], at: Offset(_plot.left - 8 - marks[k].width, _y(_ticks[k]) - row / 2), turned: false));
    }
    if (yLabel != null) {
      _labels.add((text: yLabel, at: Offset(0, _plot.center.dy + yLabel.width / 2), turned: true));
    }

    final under = _plot.bottom + 6;
    if (_numeric) {
      final (low, high, xStep) = _nice(xs!.reduce(math.min), xs.reduce(math.max));
      _xLo = low;
      _xHi = high;
      for (var k = 0; k <= ((_xHi - _xLo) / xStep).round(); k++) {
        final v = _xLo + k * xStep;
        final mark = _text(_format(v, xStep), _small, width / 3);
        _labels.add((text: mark, at: Offset(_x(v) - mark.width / 2, under), turned: false));
      }
    } else if (rows > 0) {
      final band = _plot.width / rows;
      final names = [for (final c in spec.categories) _text(c, _small, _plot.width / 3)];
      final widest = names.fold(0.0, (a, n) => math.max(a, n.width));
      final every = math.max(1, ((widest + 10) / band).ceil());
      for (var i = 0; i < rows; i++) {
        if (i % every != 0) {
          names[i].dispose();
          continue;
        }
        _labels.add((text: names[i], at: Offset(_plot.left + band * (i + 0.5) - names[i].width / 2, under), turned: false));
      }
    }
    var bottom = under + row;
    if (xLabel != null) {
      _labels.add((text: xLabel, at: Offset(_plot.center.dx - xLabel.width / 2, bottom + 4), turned: false));
      bottom += 4 + xLabel.height;
    }
    return bottom;
  }

  /// [lo] and [hi] rounded out to multiples of a round step, and the step.
  static (double, double, double) _nice(double lo, double hi) {
    if (!lo.isFinite || !hi.isFinite) (lo, hi) = (0, 1);
    if (hi <= lo) hi = lo + (lo == 0 ? 1 : lo.abs());
    final raw = (hi - lo) / 5;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final norm = raw / magnitude;
    final step = (norm <= 1 ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10))) * magnitude;
    return ((lo / step).floor() * step, (hi / step).ceil() * step, step);
  }

  /// [v] as a mark of an axis whose marks are [step] apart.
  String _format(double v, double step) {
    final decimals = step >= 1 ? 0 : math.min(6, (-math.log(step) / math.ln10 - 1e-9).ceil());
    if (v.abs() < step / 1e6) v = 0;
    final text = v.abs().toStringAsFixed(decimals);
    final dot = text.indexOf('.');
    var whole = dot < 0 ? text : text.substring(0, dot);
    if (whole.length > 4) {
      final groups = <String>[];
      for (var end = whole.length; end > 0; end -= 3) {
        groups.insert(0, whole.substring(math.max(0, end - 3), end));
      }
      whole = groups.join(' ');
    }
    return '${v < 0 ? '−' : ''}$whole${dot < 0 ? '' : spec.decimal + text.substring(dot + 1)}';
  }

  double _y(double v) => _plot.bottom - (v - _lo) / (_hi - _lo) * _plot.height;

  /// Where an abscissa, or the middle of row [i], is.
  double _x(double v) => _plot.left + (v - _xLo) / (_xHi - _xLo) * _plot.width;

  double _at(int i) => _numeric ? _x(spec.xs![i]) : _plot.left + _plot.width / spec.categories.length * (i + 0.5);

  @override
  void paint(Canvas canvas, Offset at) {
    canvas
      ..save()
      ..translate(at.dx, at.dy);
    for (final s in _swatches) {
      canvas.drawRRect(RRect.fromRectAndRadius(s.box, const Radius.circular(2)), Paint()..color = s.color);
    }
    if (spec.type == ChartType.pie) {
      _pie(canvas);
    } else {
      final grid = Paint()
        ..color = theme.markup.withValues(alpha: theme.markup.a * 0.4)
        ..strokeWidth = 1;
      final zero = Paint()
        ..color = theme.markup
        ..strokeWidth = 1;
      for (final v in _ticks) {
        final y = _y(v).roundToDouble() + 0.5;
        canvas.drawLine(Offset(_plot.left, y), Offset(_plot.right, y), v == 0 || v == _ticks.first && _lo > 0 ? zero : grid);
      }
      switch (spec.type) {
        case ChartType.bar:
          _bars(canvas);
        case ChartType.scatter:
          for (var k = 0; k < spec.series.length; k++) {
            final values = spec.series[k].values;
            final paint = Paint()..color = _color(k).withValues(alpha: 0.85);
            for (var i = 0; i < values.length; i++) {
              if (values[i] != null) canvas.drawCircle(Offset(_at(i), _y(values[i]!)), 3.5, paint);
            }
          }
        default:
          _lines(canvas);
      }
    }
    for (final l in _labels) {
      if (!l.turned) {
        l.text.paint(canvas, l.at);
        continue;
      }
      canvas
        ..save()
        ..translate(l.at.dx, l.at.dy)
        ..rotate(-math.pi / 2);
      l.text.paint(canvas, Offset.zero);
      canvas.restore();
    }
    canvas.restore();
  }

  void _bars(Canvas canvas) {
    final rows = spec.categories.length, count = spec.series.length;
    final band = _plot.width / rows;
    final wide = _stacked ? math.min(band * 0.6, 56.0) : math.min(band * 0.72 / count, 56.0);
    final base = _y(0);
    for (var i = 0; i < rows; i++) {
      final middle = _at(i);
      var up = 0.0, down = 0.0;
      for (var k = 0; k < count; k++) {
        final v = spec.series[k].values[i];
        if (v == null) continue;
        final paint = Paint()..color = _color(k);
        if (_stacked) {
          final from = v >= 0 ? up : down;
          v >= 0 ? up += v : down += v;
          canvas.drawRect(Rect.fromLTRB(middle - wide / 2, _y(from + v), middle + wide / 2, _y(from)), paint);
        } else {
          final left = middle - wide * count / 2 + wide * k;
          final gap = wide > 6 ? 1.0 : 0.0;
          canvas.drawRect(Rect.fromLTRB(left + gap, math.min(_y(v), base), left + wide - gap, math.max(_y(v), base)), paint);
        }
      }
    }
  }

  /// Lines, and areas under them down to nothing, or to the series before
  /// when they are stacked. A row without a value cuts the line.
  void _lines(Canvas canvas) {
    final rows = spec.categories.length;
    final area = spec.type == ChartType.area;
    final floor = List.filled(rows, 0.0);
    for (var k = 0; k < spec.series.length; k++) {
      final values = spec.series[k].values;
      final color = _color(k);
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      for (var from = 0; from < rows;) {
        if (values[from] == null && !_stacked) {
          from++;
          continue;
        }
        var to = from;
        final line = Path(), under = <Offset>[];
        for (; to < rows && (values[to] != null || _stacked); to++) {
          final top = floor[to] + (values[to] ?? 0);
          final point = Offset(_at(to), _y(top));
          to == from ? line.moveTo(point.dx, point.dy) : line.lineTo(point.dx, point.dy);
          under.add(Offset(point.dx, _y(floor[to])));
          if (_stacked) floor[to] = top;
        }
        if (area) {
          final fill = Path.from(line);
          for (final p in under.reversed) {
            fill.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(fill..close(), Paint()..color = color.withValues(alpha: 0.22));
        }
        canvas.drawPath(line, stroke);
        if (rows <= 40) {
          for (var i = from; i < to; i++) {
            canvas.drawCircle(Offset(_at(i), _y(_stacked ? floor[i] : values[i]!)), 2.5, Paint()..color = color);
          }
        }
        from = to;
      }
    }
  }

  void _pie(Canvas canvas) {
    final values = spec.series.first.values;
    final total = _pieTotal;
    var angle = -math.pi / 2, k = 0;
    for (final v in values) {
      if (v == null || v <= 0) continue;
      final sweep = 2 * math.pi * v / total;
      canvas.drawArc(_plot.deflate(4), angle, sweep, true, Paint()..color = _color(k++));
      angle += sweep;
    }
  }

  @override
  void dispose() {
    for (final l in _labels) {
      l.text.dispose();
    }
  }
}
