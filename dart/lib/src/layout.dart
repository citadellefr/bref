import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'note_syntax.dart';
import 'note_text.dart';
import 'theme.dart';

/// The lines of a note laid out one under the other, in a column of
/// [width]. Only the lines shown are laid out; the others have a height
/// guessed from their length, corrected once they are shown.
class NoteLayout extends ChangeNotifier {
  NoteLayout(this.text, this.syntax, {required this._theme, required this._scaler}) {
    _measureFont();
    _reset();
  }

  final NoteText text;
  final NoteSyntax syntax;

  BrefTheme _theme;
  TextScaler _scaler;
  double _width = 0;

  final _heights = <double>[];
  final _measured = <bool>[];
  final _painters = <TextPainter?>[];

  /// The top of each line and the bottom of the last, valid up to
  /// [_validTops].
  final _tops = <double>[];
  var _validTops = 0;

  final _styles = <int, TextStyle>{};
  var _lineHeight = 24.0;
  var _charWidth = 8.0;

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

  double get width => _width;

  set width(double value) {
    if (value == _width) return;
    _width = value;
    _reset();
  }

  void _restyle() {
    _styles.clear();
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
    probe.dispose();
  }

  void _reset() {
    for (final p in _painters) {
      p?.dispose();
    }
    _painters
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
    notifyListeners();
  }

  /// The visual row of the text around [offset]: from where it starts to
  /// where it ends.
  (int, int) rowAt(int offset) {
    final i = text.lineAt(offset);
    final start = text.lineStart(i);
    final row = painter(i).getLineBoundary(TextPosition(offset: offset - start));
    return (start + row.start, start + row.end);
  }

  /// Follows a splice of the text, after which the syntax of [restyled]
  /// more lines changed.
  void splice(LineSplice s, int restyled) {
    for (var i = s.index; i < s.index + s.removed; i++) {
      _painters[i]?.dispose();
    }
    _painters.replaceRange(s.index, s.index + s.removed, List.filled(s.inserted, null));
    _measured.replaceRange(s.index, s.index + s.removed, List.filled(s.inserted, false));
    _heights.replaceRange(s.index, s.index + s.removed, [for (var i = 0; i < s.inserted; i++) _estimate(s.index + i)]);
    _tops.replaceRange(s.index + 1, s.index + s.removed + 1, List.filled(s.inserted, 0.0));
    for (var i = s.index + s.inserted; i < s.index + s.inserted + restyled && i < text.lineCount; i++) {
      _painters[i]?.dispose();
      _painters[i] = null;
      _measured[i] = false;
    }
    if (anchor >= s.index + s.removed) {
      anchor += s.inserted - s.removed;
    } else if (anchor > s.index) {
      anchor = s.index;
    }
    _validTops = math.min(_validTops, s.index);
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
  TextPainter painter(int i) {
    final cached = _painters[i];
    if (cached != null) return cached;
    final painter = TextPainter(text: _span(i), textDirection: TextDirection.ltr, textScaler: _scaler)
      ..layout(maxWidth: math.max(_width, 1));
    _painters[i] = painter;
    if (!_measured[i] || _heights[i] != painter.height) {
      _measured[i] = true;
      _heights[i] = painter.height;
      _validTops = math.min(_validTops, i);
    }
    return painter;
  }

  TextSpan _span(int i) {
    final line = text.line(i);
    final s = syntax.line(i);
    if (line.isEmpty) return TextSpan(text: '', style: _style(0, s.heading));
    var from = 0;
    return TextSpan(
      style: _style(0, s.heading),
      children: [
        for (var k = 0; k < s.ends.length; k++)
          TextSpan(text: line.substring(from, from = s.ends[k]), style: _style(s.marks[k], s.heading)),
      ],
    );
  }

  TextStyle _style(int marks, int heading) => _styles[marks << 3 | heading] ??= _theme.style(marks, heading);

  /// Lets go of the lines laid out far from those shown.
  void forget(int first, int last) {
    const keep = 200;
    for (var i = 0; i < _painters.length; i++) {
      if (i >= first - keep && i <= last + keep) {
        i = last + keep;
        continue;
      }
      _painters[i]?.dispose();
      _painters[i] = null;
    }
  }

  /// The offset of the text nearest to [p], in the coordinates of the
  /// column.
  int offsetAt(Offset p) {
    final i = lineAtY(p.dy);
    final position = painter(i).getPositionForOffset(Offset(p.dx, p.dy - top(i)));
    return text.lineStart(i) + position.offset;
  }

  /// The caret before the unit at [offset], in the coordinates of the
  /// column.
  Rect caretRect(int offset) {
    final i = text.lineAt(offset);
    final p = painter(i);
    final position = TextPosition(offset: offset - text.lineStart(i));
    final at = p.getOffsetForCaret(position, Rect.zero);
    final height = p.getFullHeightForCaret(position, Rect.zero);
    return Rect.fromLTWH(at.dx, top(i) + at.dy, 2, height);
  }

  @override
  void dispose() {
    for (final p in _painters) {
      p?.dispose();
    }
    super.dispose();
  }
}
