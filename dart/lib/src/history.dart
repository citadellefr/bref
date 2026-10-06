import 'package:trame/trame.dart';

import 'note_text.dart';

/// How a line of a version stands against the note as it is.
enum DiffKind { same, added, removed }

typedef DiffLine = ({DiffKind kind, String text});

/// The lines of [before] and [after] side by side: what both have, what only
/// [after] has and what only [before] has. Past a size no one reads a
/// difference at, the lines between the common ends are shown as replaced.
List<DiffLine> lineDiff(List<String> before, List<String> after) {
  var head = 0;
  while (head < before.length && head < after.length && before[head] == after[head]) {
    head++;
  }
  var tail = 0;
  while (tail < before.length - head && tail < after.length - head && before[before.length - 1 - tail] == after[after.length - 1 - tail]) {
    tail++;
  }
  final a = before.sublist(head, before.length - tail);
  final b = after.sublist(head, after.length - tail);
  return [
    for (final l in before.take(head)) (kind: DiffKind.same, text: l),
    ..._middle(a, b),
    for (final l in before.skip(before.length - tail)) (kind: DiffKind.same, text: l),
  ];
}

const _largest = 4000000;

List<DiffLine> _middle(List<String> a, List<String> b) {
  if (a.length * b.length > _largest) {
    return [
      for (final l in a) (kind: DiffKind.removed, text: l),
      for (final l in b) (kind: DiffKind.added, text: l),
    ];
  }
  // longest common subsequence, from the ends
  final width = b.length + 1;
  final lcs = List<int>.filled((a.length + 1) * width, 0);
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i * width + j] = a[i] == b[j]
          ? lcs[(i + 1) * width + j + 1] + 1
          : (lcs[(i + 1) * width + j] >= lcs[i * width + j + 1] ? lcs[(i + 1) * width + j] : lcs[i * width + j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      out.add((kind: DiffKind.same, text: a[i]));
      i++;
      j++;
    } else if (i < a.length && (j == b.length || lcs[(i + 1) * width + j] >= lcs[i * width + j + 1])) {
      out.add((kind: DiffKind.removed, text: a[i++]));
    } else {
      out.add((kind: DiffKind.added, text: b[j++]));
    }
  }
  return out;
}

/// The text of a file as the note's flow holds it: lines ended by "\n", and
/// the final mark every flow ends with.
String flowOf(String file) => '${file.replaceAll('\r\n', '\n')}\n';

/// Restores a version of the note in one edit, which others see and undo
/// takes back: only what differs from the note now is replaced, so what
/// they wrote around it keeps its author and its comments.
extension History on DocSession {
  bool restoreText(String version) {
    final now = document[noteBody]?.text?.text;
    if (now == null) return false;
    final then = flowOf(version);
    var head = 0;
    final most = now.length < then.length ? now.length : then.length;
    while (head < most && now.codeUnitAt(head) == then.codeUnitAt(head)) {
      head++;
    }
    if (head > 0 && _high(now.codeUnitAt(head - 1))) head--;
    var tail = 0;
    while (tail < most - head && now.codeUnitAt(now.length - 1 - tail) == then.codeUnitAt(then.length - 1 - tail)) {
      tail++;
    }
    if (tail > 0 && _low(now.codeUnitAt(now.length - tail))) tail--;
    if (head + tail == now.length && head + tail == then.length) return false;
    final by = id.isEmpty ? null : {'by': id};
    return edit(Edit([
      Change.text(
        noteBody,
        Delta()
          ..retain(head)
          ..delete(now.length - head - tail)
          ..insert(then.substring(head, then.length - tail), by),
      ),
    ]));
  }
}

bool _high(int unit) => unit >= 0xD800 && unit < 0xDC00;

bool _low(int unit) => unit >= 0xDC00 && unit < 0xE000;
