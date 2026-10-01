import 'dart:math' as math;

/// The scale of a value axis: its bounds and the step between its ticks.
class Scale {
  const Scale(this.min, this.max, this.step, {this.log = 0});

  /// Chooses bounds and step for values from [lo] to [hi] as Excel does:
  /// from zero when the values are not too far from it, a little room
  /// above the highest, a round step giving at most [ticks] intervals.
  /// Bounds and step the file fixes are kept.
  factory Scale.auto(double lo, double hi, {double? min, double? max, double major = 0, double log = 0, int ticks = 10}) {
    if (log > 1) return Scale._log(lo, hi, log, min, max);
    if (lo > hi) (lo, hi) = (0, 1);
    if (min != null) lo = math.min(lo, min);
    if (max != null) hi = math.max(hi, max);
    var low = min ?? (lo >= 0 && hi > 0 && hi - lo > hi / 6 ? 0.0 : lo);
    var high = max ?? (hi <= 0 && lo < 0 && hi - lo > -lo / 6 ? 0.0 : hi);
    if (min != null && max == null && high <= low) high = low + 1;
    if (max != null && min == null && low >= high) low = high - 1;
    if (high == low) {
      if (high == 0) {
        high = 1;
      } else if (high > 0) {
        low = math.min(low, 0);
        if (high == low) high = low + 1;
      } else {
        high = 0;
      }
    }
    final room = (high - low) * 0.05;
    final top = max ?? (high > 0 ? high + room : high);
    final bottom = min ?? (low != 0 ? low - room : low);
    final step = major > 0 ? major : niceStep((top - bottom) / math.max(ticks, 1));
    final first = min ?? _clean((bottom / step).floorToDouble() * step);
    var last = max ?? _clean((top / step).ceilToDouble() * step);
    if (last <= first) last = first + step;
    return Scale(first, last, step);
  }

  factory Scale._log(double lo, double hi, double base, double? min, double? max) {
    double floorPow(double v) => math.pow(base, (math.log(v) / math.log(base)).floorToDouble()).toDouble();
    double ceilPow(double v) => math.pow(base, (math.log(v) / math.log(base)).ceilToDouble()).toDouble();
    final low = min != null && min > 0 ? min : (lo > 0 ? floorPow(lo) : 1.0);
    var high = max != null && max > low ? max : (hi > 0 ? ceilPow(hi) : low * base);
    if (high <= low) high = low * base;
    return Scale(low, high, base, log: base);
  }

  final double min;
  final double max;

  /// The step between ticks; the base for a logarithmic scale.
  final double step;
  final double log;

  /// Where a value sits, from 0 at [min] to 1 at [max].
  double fraction(double v) {
    if (log > 1) {
      if (v <= 0) return 0;
      return (math.log(v / min)) / math.log(max / min);
    }
    return (v - min) / (max - min);
  }

  /// The values ticks are drawn at.
  List<double> get ticks {
    final out = <double>[];
    if (log > 1) {
      for (var v = min; v <= max * (1 + 1e-9) && out.length < 1000; v *= step) {
        out.add(v);
      }
      return out;
    }
    final n = ((max - min) / step + 1e-9).floor();
    for (var i = 0; i <= n && i <= 1000; i++) {
      out.add(_clean(min + i * step));
    }
    return out;
  }

  /// The value [v] clamped into the scale.
  double clamp(double v) => v.clamp(math.min(min, max), math.max(min, max)).toDouble();
}

/// The smallest of 1, 2 and 5 times a power of ten at least [raw].
double niceStep(double raw) {
  if (!(raw > 0) || raw.isInfinite) return 1;
  final p = math.pow(10, (math.log(raw) / math.ln10).floorToDouble()).toDouble();
  for (final m in const [1, 2, 5, 10]) {
    if (m * p >= raw * (1 - 1e-9)) return _clean(m * p);
  }
  return 10 * p;
}

/// Drops the noise binary arithmetic leaves after a step is added up.
double _clean(double v) => double.parse(v.toStringAsPrecision(12));
