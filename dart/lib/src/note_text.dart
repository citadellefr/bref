import 'package:trame/trame.dart';

/// Lines [removed] from [index] on, replaced by [inserted] others.
typedef LineSplice = ({int index, int removed, int inserted});

/// The text of a note line by line: the flow of its body without its final
/// mark, kept in step with the edits of the flow. Offsets count UTF-16 units,
/// as the flow does.
class NoteText {
  NoteText(String flow) {
    reset(flow);
  }

  final _lines = <String>[];
  final _starts = <int>[];

  int get lineCount => _lines.length;

  String line(int i) => _lines[i];

  int lineStart(int i) => _starts[i];

  /// Where line [i] ends, before its "\n".
  int lineEnd(int i) => _starts[i] + _lines[i].length;

  int get length => lineEnd(_lines.length - 1);

  String get text => _lines.join('\n');

  /// The line holding [offset]; an offset at a line's end is in it.
  int lineAt(int offset) {
    var lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  String substring(int start, int end) {
    final a = lineAt(start), b = lineAt(end);
    if (a == b) return _lines[a].substring(start - _starts[a], end - _starts[a]);
    final out = StringBuffer(_lines[a].substring(start - _starts[a]));
    for (var i = a + 1; i < b; i++) {
      out
        ..write('\n')
        ..write(_lines[i]);
    }
    out
      ..write('\n')
      ..write(_lines[b].substring(0, end - _starts[b]));
    return out.toString();
  }

  /// Starts again from a whole flow, which ends with its mark.
  void reset(String flow) {
    _lines
      ..clear()
      ..addAll(flow.substring(0, flow.length - 1).split('\n'));
    _starts.clear();
    var at = 0;
    for (final line in _lines) {
      _starts.add(at);
      at += line.length + 1;
    }
  }

  /// Applies a delta of the flow, and tells which lines it replaced, null
  /// when it changed nothing. Its ops walk the flow forward, so that the
  /// lines it replaced are those from the first it touched to the last.
  LineSplice? apply(Delta delta) {
    LineSplice? first, last;
    var growth = 0;
    var at = 0;
    for (final op in delta.ops) {
      if (op.isRetain) {
        at += op.retain;
        continue;
      }
      final s = op.isDelete ? _replace(at, at + op.delete, '') : _replace(at, at, op.insert!);
      at += op.insert?.length ?? 0;
      first ??= s;
      last = s;
      growth += s.inserted - s.removed;
    }
    if (first == null || last == null) return null;
    final end = last.index + last.inserted;
    return (index: first.index, removed: end - first.index - growth, inserted: end - first.index);
  }

  LineSplice _replace(int start, int end, String text) {
    final a = lineAt(start), b = lineAt(end);
    final head = _lines[a].substring(0, start - _starts[a]);
    final tail = _lines[b].substring(end - _starts[b]);
    final lines = '$head$text$tail'.split('\n');
    var offset = _starts[a];
    _lines.replaceRange(a, b + 1, lines);
    _starts.replaceRange(a, b + 1, List.filled(lines.length, 0));
    for (var i = a; i < _lines.length; i++) {
      _starts[i] = offset;
      offset += _lines[i].length + 1;
    }
    return (index: a, removed: b - a + 1, inserted: lines.length);
  }
}
