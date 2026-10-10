import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

/// The lengths of the `MATH` table, in the order it holds them.
enum MathConstant {
  mathLeading,
  axisHeight,
  accentBaseHeight,
  flattenedAccentBaseHeight,
  subscriptShiftDown,
  subscriptTopMax,
  subscriptBaselineDropMin,
  superscriptShiftUp,
  superscriptShiftUpCramped,
  superscriptBottomMin,
  superscriptBaselineDropMax,
  subSuperscriptGapMin,
  superscriptBottomMaxWithSubscript,
  spaceAfterScript,
  upperLimitGapMin,
  upperLimitBaselineRiseMin,
  lowerLimitGapMin,
  lowerLimitBaselineDropMin,
  stackTopShiftUp,
  stackTopDisplayStyleShiftUp,
  stackBottomShiftDown,
  stackBottomDisplayStyleShiftDown,
  stackGapMin,
  stackDisplayStyleGapMin,
  stretchStackTopShiftUp,
  stretchStackBottomShiftDown,
  stretchStackGapAboveMin,
  stretchStackGapBelowMin,
  fractionNumeratorShiftUp,
  fractionNumeratorDisplayStyleShiftUp,
  fractionDenominatorShiftDown,
  fractionDenominatorDisplayStyleShiftDown,
  fractionNumeratorGapMin,
  fractionNumDisplayStyleGapMin,
  fractionRuleThickness,
  fractionDenominatorGapMin,
  fractionDenomDisplayStyleGapMin,
  skewedFractionHorizontalGap,
  skewedFractionVerticalGap,
  overbarVerticalGap,
  overbarRuleThickness,
  overbarExtraAscender,
  underbarVerticalGap,
  underbarRuleThickness,
  underbarExtraDescender,
  radicalVerticalGap,
  radicalDisplayStyleVerticalGap,
  radicalRuleThickness,
  radicalExtraAscender,
  radicalKernBeforeDegree,
  radicalKernAfterDegree,
}

/// The outline of a glyph, in the units of the font with y going down as on
/// a canvas, and the box of its ink, y going up from the baseline.
class GlyphShape {
  GlyphShape(this.path, this.left, this.right, this.height, this.depth);

  final Path path;
  final double left, right;
  final double height, depth;
}

/// A piece of a glyph built at any size: [extender]s repeat, and each piece
/// may cover the next by as much as their connectors.
typedef GlyphPart = ({int glyph, int start, int end, int advance, bool extender});

/// The bigger glyphs that stand for one, each with how long it is, and the
/// [parts] to build it longer still.
class GlyphConstruction {
  GlyphConstruction(this.variants, this.parts);

  final List<({int glyph, int advance})> variants;
  final List<GlyphPart> parts;
}

/// An OpenType font with a `MATH` table and CFF outlines, read as far as
/// setting formulas needs: glyphs by character, their advances, outlines,
/// and what the `MATH` table says of them.
class MathFont {
  MathFont._(this._data);

  /// Reads the font in [data]; throws a [FormatException] when it is not one
  /// this reads.
  factory MathFont.parse(ByteData data) {
    final f = MathFont._(data);
    try {
      f._read();
    } on RangeError {
      throw const FormatException('font cut short');
    }
    return f;
  }

  static const _asset = 'packages/bref/fonts/latinmodern-math.otf';

  /// The font of the package, once [load] read it.
  static MathFont? loaded;
  static Future<MathFont>? _loading;

  /// Reads the font of the package, once; never done before it returns,
  /// even when the bundle answers at once.
  static Future<MathFont> load() => _loading ??= _fromBundle();

  static Future<MathFont> _fromBundle() async => loaded = MathFont.parse(await rootBundle.load(_asset));

  final ByteData _data;
  final _tables = <String, int>{};

  late final int unitsPerEm;
  late final int _glyphCount;
  late final int _metrics;
  late final int _hmtx;

  /// The groups of the character map: first and last character, first glyph.
  late final Uint32List _groups;

  late final Int16List _constants;
  late final int scriptPercent;
  late final int scriptScriptPercent;
  late final int displayOperatorMinHeight;
  late final int radicalDegreeRaisePercent;
  late final int minOverlap;
  final _italics = <int, int>{};
  final _accents = <int, int>{};
  final _vertical = <int, int>{};
  final _horizontal = <int, int>{};
  final _constructions = <int, GlyphConstruction>{};

  /// Where the charstrings and the subroutines are: the offsets of each
  /// index, and where its data starts.
  late final _Index _charStrings;
  _Index? _subrs;
  final _shapes = <int, GlyphShape>{};

  int _u8(int at) => _data.getUint8(at);

  int _u16(int at) => _data.getUint16(at);

  int _i16(int at) => _data.getInt16(at);

  int _u32(int at) => _data.getUint32(at);

  int _table(String tag) => _tables[tag] ?? (throw FormatException('no $tag table'));

  void _read() {
    final count = _u16(4);
    for (var k = 0; k < count; k++) {
      final at = 12 + 16 * k;
      _tables[String.fromCharCodes([for (var c = 0; c < 4; c++) _u8(at + c)])] = _u32(at + 8);
    }
    unitsPerEm = _u16(_table('head') + 18);
    _glyphCount = _u16(_table('maxp') + 4);
    _metrics = _u16(_table('hhea') + 34);
    _hmtx = _table('hmtx');
    _readCmap();
    _readMath();
    _readCff();
  }

  void _readCmap() {
    final cmap = _table('cmap');
    for (var k = 0; k < _u16(cmap + 2); k++) {
      final at = cmap + _u32(cmap + 4 + 8 * k + 4);
      if (_u16(at) != 12) continue;
      final n = _u32(at + 12);
      _groups = Uint32List(3 * n);
      for (var g = 0; g < 3 * n; g++) {
        _groups[g] = _u32(at + 16 + 4 * g);
      }
      return;
    }
    throw const FormatException('no character map of format 12');
  }

  /// The glyph of [rune], 0 when the font has none.
  int glyph(int rune) {
    var lo = 0, hi = _groups.length ~/ 3 - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_groups[3 * mid + 1] < rune) {
        lo = mid + 1;
      } else if (_groups[3 * mid] > rune) {
        hi = mid - 1;
      } else {
        return _groups[3 * mid + 2] + rune - _groups[3 * mid];
      }
    }
    return 0;
  }

  double advance(int glyph) => _u16(_hmtx + 4 * (glyph < _metrics ? glyph : _metrics - 1)).toDouble();

  int operator [](MathConstant c) => _constants[c.index];

  /// How far what follows [glyph] is moved for its slant.
  int italic(int glyph) => _italics[glyph] ?? 0;

  /// Where an accent sits over [glyph], or null for its middle.
  int? accent(int glyph) => _accents[glyph];

  /// The taller, or with [horizontal] the wider, forms of [glyph].
  GlyphConstruction? construction(int glyph, {bool horizontal = false}) {
    final at = (horizontal ? _horizontal : _vertical)[glyph];
    if (at == null) return null;
    return _constructions[at] ??= () {
      final assembly = _u16(at);
      final variants = [
        for (var k = 0; k < _u16(at + 2); k++) (glyph: _u16(at + 4 + 4 * k), advance: _u16(at + 6 + 4 * k)),
      ];
      final parts = <GlyphPart>[];
      if (assembly != 0) {
        final a = at + assembly;
        for (var k = 0; k < _u16(a + 4); k++) {
          final p = a + 6 + 10 * k;
          parts.add((glyph: _u16(p), start: _u16(p + 2), end: _u16(p + 4), advance: _u16(p + 6), extender: _u16(p + 8) & 1 != 0));
        }
      }
      return GlyphConstruction(variants, parts);
    }();
  }

  void _readMath() {
    final math = _table('MATH');
    final c = math + _u16(math + 4);
    scriptPercent = _i16(c);
    scriptScriptPercent = _i16(c + 2);
    displayOperatorMinHeight = _u16(c + 6);
    _constants = Int16List(MathConstant.values.length);
    for (var k = 0; k < _constants.length; k++) {
      _constants[k] = _i16(c + 8 + 4 * k);
    }
    radicalDegreeRaisePercent = _i16(c + 8 + 4 * _constants.length);

    final info = math + _u16(math + 6);
    for (final (offset, into) in [(_u16(info), _italics), (_u16(info + 2), _accents)]) {
      if (offset == 0) continue;
      final at = info + offset;
      final glyphs = _coverage(at + _u16(at));
      for (var k = 0; k < glyphs.length; k++) {
        into[glyphs[k]] = _i16(at + 4 + 4 * k);
      }
    }

    final v = math + _u16(math + 8);
    minOverlap = _u16(v);
    final vertical = _u16(v + 6), horizontal = _u16(v + 8);
    for (final (coverage, first, count, into) in [(_u16(v + 2), 0, vertical, _vertical), (_u16(v + 4), vertical, horizontal, _horizontal)]) {
      if (coverage == 0) continue;
      final glyphs = _coverage(v + coverage);
      for (var k = 0; k < count && k < glyphs.length; k++) {
        into[glyphs[k]] = v + _u16(v + 10 + 2 * (first + k));
      }
    }
  }

  /// The glyphs a coverage table lists, in its order.
  List<int> _coverage(int at) {
    final count = _u16(at + 2);
    if (_u16(at) == 1) return [for (var k = 0; k < count; k++) _u16(at + 4 + 2 * k)];
    return [
      for (var k = 0; k < count; k++)
        for (var g = _u16(at + 4 + 6 * k); g <= _u16(at + 6 + 6 * k); g++) g,
    ];
  }

  void _readCff() {
    final cff = _table('CFF ');
    final names = _Index(_data, cff + _u8(cff + 2));
    final top = _Index(_data, names.end);
    final dict = _dict(top.start(0), top.start(1));
    final strings = dict[17];
    if (strings == null || dict.containsKey(0x0c1e)) throw const FormatException('CFF outlines of a kind this does not read');
    _charStrings = _Index(_data, cff + strings[0].toInt());
    final private = dict[18];
    if (private != null && private.length == 2) {
      final at = cff + private[1].toInt();
      final subrs = _dict(at, at + private[0].toInt())[19];
      if (subrs != null) _subrs = _Index(_data, at + subrs[0].toInt());
    }
  }

  /// The operands of each operator of the dictionary from [at] to [end];
  /// operators of two bytes are 0x0c00 and theirs.
  Map<int, List<num>> _dict(int at, int end) {
    final out = <int, List<num>>{};
    var operands = <num>[];
    while (at < end) {
      final b = _u8(at++);
      if (b <= 21) {
        out[b == 12 ? 0x0c00 | _u8(at++) : b] = operands;
        operands = [];
      } else if (b == 28) {
        operands.add(_i16(at));
        at += 2;
      } else if (b == 29) {
        operands.add(_data.getInt32(at));
        at += 4;
      } else if (b == 30) {
        final text = StringBuffer();
        for (var done = false; !done;) {
          final byte = _u8(at++);
          for (final nibble in [byte >> 4, byte & 15]) {
            if (nibble == 15) {
              done = true;
              break;
            }
            text.write(const ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', 'E', 'E-', '', '-'][nibble]);
          }
        }
        operands.add(double.tryParse(text.toString()) ?? 0);
      } else if (b <= 246) {
        operands.add(b - 139);
      } else if (b <= 250) {
        operands.add((b - 247) * 256 + _u8(at++) + 108);
      } else {
        operands.add(-(b - 251) * 256 - _u8(at++) - 108);
      }
    }
    return out;
  }

  /// The outline of [glyph], read when first asked.
  GlyphShape shape(int glyph) => _shapes[glyph] ??= _Outline(this).read(glyph < _glyphCount ? glyph : 0);
}

/// An INDEX of CFF: a list of pieces of data, one after the other.
class _Index {
  _Index(this._data, int at)
      : count = _data.getUint16(at),
        _offsets = at + 3 {
    _size = count == 0 ? 0 : _data.getUint8(at + 2);
    _base = _offsets + (count + 1) * _size - 1;
    end = count == 0 ? at + 2 : start(count);
  }

  final ByteData _data;
  final int count;
  final int _offsets;
  late final int _size;
  late final int _base;

  /// Where what follows the index starts.
  late final int end;

  /// Where piece [k] starts; piece [count] is where the last one ends.
  int start(int k) {
    var offset = 0;
    for (var b = 0; b < _size; b++) {
      offset = offset << 8 | _data.getUint8(_offsets + k * _size + b);
    }
    return _base + offset;
  }
}

/// Runs the Type 2 charstring of a glyph into a path.
class _Outline {
  _Outline(this.font);

  final MathFont font;
  final path = Path();
  final stack = <double>[];
  var x = 0.0, y = 0.0;
  var stems = 0;
  var open = false;
  var done = false;
  var left = double.infinity, right = double.negativeInfinity, bottom = double.infinity, top = double.negativeInfinity;

  GlyphShape read(int glyph) {
    final strings = font._charStrings;
    if (glyph < strings.count) _run(strings.start(glyph), strings.start(glyph + 1), 0);
    if (open) path.close();
    if (left > right) return GlyphShape(path, 0, 0, 0, 0);
    return GlyphShape(path, left, right, top, -bottom);
  }

  void _seen(double px, double py) {
    if (px < left) left = px;
    if (px > right) right = px;
    if (py < bottom) bottom = py;
    if (py > top) top = py;
  }

  void _move(double dx, double dy) {
    if (open) path.close();
    open = true;
    x += dx;
    y += dy;
    path.moveTo(x, -y);
    _seen(x, y);
  }

  void _line(double dx, double dy) {
    x += dx;
    y += dy;
    path.lineTo(x, -y);
    _seen(x, y);
  }

  void _curve(double a, double b, double c, double d, double e, double f) {
    final x1 = x + a, y1 = y + b, x2 = x1 + c, y2 = y1 + d;
    x = x2 + e;
    y = y2 + f;
    path.cubicTo(x1, -y1, x2, -y2, x, -y);
    _seen(x1, y1);
    _seen(x2, y2);
    _seen(x, y);
  }

  void _run(int at, int end, int depth) {
    final data = font._data;
    final s = stack;
    while (at < end && !done) {
      final b = data.getUint8(at++);
      if (b >= 32 || b == 28) {
        if (b == 28) {
          s.add(data.getInt16(at).toDouble());
          at += 2;
        } else if (b <= 246) {
          s.add(b - 139.0);
        } else if (b <= 250) {
          s.add((b - 247) * 256 + data.getUint8(at++) + 108.0);
        } else if (b <= 254) {
          s.add(-(b - 251) * 256 - data.getUint8(at++) - 108.0);
        } else {
          s.add(data.getInt32(at) / 65536);
          at += 4;
        }
        continue;
      }
      switch (b) {
        case 1 || 3 || 18 || 23:
          stems += s.length >> 1;
        case 19 || 20:
          stems += s.length >> 1;
          at += (stems + 7) >> 3;
        case 21:
          if (s.length >= 2) _move(s[s.length - 2], s.last);
        case 22:
          if (s.isNotEmpty) _move(s.last, 0);
        case 4:
          if (s.isNotEmpty) _move(0, s.last);
        case 5:
          for (var k = 0; k + 1 < s.length; k += 2) {
            _line(s[k], s[k + 1]);
          }
        case 6 || 7:
          var horizontal = b == 6;
          for (final d in s) {
            horizontal ? _line(d, 0) : _line(0, d);
            horizontal = !horizontal;
          }
        case 8:
          for (var k = 0; k + 5 < s.length; k += 6) {
            _curve(s[k], s[k + 1], s[k + 2], s[k + 3], s[k + 4], s[k + 5]);
          }
        case 24:
          var k = 0;
          for (; k + 7 < s.length; k += 6) {
            _curve(s[k], s[k + 1], s[k + 2], s[k + 3], s[k + 4], s[k + 5]);
          }
          if (k + 1 < s.length) _line(s[k], s[k + 1]);
        case 25:
          var k = 0;
          for (; k + 7 < s.length; k += 2) {
            _line(s[k], s[k + 1]);
          }
          if (k + 5 < s.length) _curve(s[k], s[k + 1], s[k + 2], s[k + 3], s[k + 4], s[k + 5]);
        case 26:
          var k = s.length.isOdd ? 1 : 0;
          var dx = k == 1 ? s[0] : 0.0;
          for (; k + 3 < s.length; k += 4) {
            _curve(dx, s[k], s[k + 1], s[k + 2], 0, s[k + 3]);
            dx = 0;
          }
        case 27:
          var k = s.length.isOdd ? 1 : 0;
          var dy = k == 1 ? s[0] : 0.0;
          for (; k + 3 < s.length; k += 4) {
            _curve(s[k], dy, s[k + 1], s[k + 2], s[k + 3], 0);
            dy = 0;
          }
        case 30 || 31:
          var horizontal = b == 31;
          for (var k = 0; k + 3 < s.length; k += 4) {
            final last = s.length - k == 5 ? s[k + 4] : 0.0;
            if (horizontal) {
              _curve(s[k], 0, s[k + 1], s[k + 2], last, s[k + 3]);
            } else {
              _curve(0, s[k], s[k + 1], s[k + 2], s[k + 3], last);
            }
            horizontal = !horizontal;
          }
        case 10:
          final subrs = font._subrs;
          if (subrs != null && s.isNotEmpty && depth < 10) {
            final k = s.removeLast().toInt() + (subrs.count < 1240 ? 107 : (subrs.count < 33900 ? 1131 : 32768));
            if (k >= 0 && k < subrs.count) _run(subrs.start(k), subrs.start(k + 1), depth + 1);
          }
          continue;
        case 11:
          return;
        case 14:
          done = true;
        case 12:
          _flex(data.getUint8(at++));
      }
      s.clear();
    }
  }

  void _flex(int op) {
    final s = stack;
    switch (op) {
      case 35 when s.length >= 12:
        _curve(s[0], s[1], s[2], s[3], s[4], s[5]);
        _curve(s[6], s[7], s[8], s[9], s[10], s[11]);
      case 34 when s.length >= 7:
        _curve(s[0], 0, s[1], s[2], s[3], 0);
        _curve(s[4], 0, s[5], -s[2], s[6], 0);
      case 36 when s.length >= 9:
        _curve(s[0], s[1], s[2], s[3], s[4], 0);
        _curve(s[5], 0, s[6], s[7], s[8], -(s[1] + s[3] + s[7]));
      case 37 when s.length >= 11:
        final dx = s[0] + s[2] + s[4] + s[6] + s[8], dy = s[1] + s[3] + s[5] + s[7] + s[9];
        _curve(s[0], s[1], s[2], s[3], s[4], s[5]);
        if (dx.abs() > dy.abs()) {
          _curve(s[6], s[7], s[8], s[9], s[10], -dy);
        } else {
          _curve(s[6], s[7], s[8], s[9], -dx, s[10]);
        }
    }
  }
}
