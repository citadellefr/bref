import 'dart:math';

import 'package:bref/src/note_syntax.dart';
import 'package:bref/src/note_text.dart';
import 'package:bref/src/syntax.dart' show LineSyntax;
import 'package:flutter_test/flutter_test.dart';
import 'package:trame/trame.dart';

void main() {
  test('reads lines and offsets', () {
    final t = NoteText('# A\n\nb c\n');
    expect([for (var i = 0; i < t.lineCount; i++) t.line(i)], ['# A', '', 'b c']);
    expect(t.length, 8);
    expect([t.lineAt(0), t.lineAt(3), t.lineAt(4), t.lineAt(5), t.lineAt(8)], [0, 0, 1, 2, 2]);
    expect(t.substring(2, 7), 'A\n\nb ');
    expect(NoteText('\n').length, 0);
  });

  test('follows random deltas, and tells which lines they replaced', () {
    final random = Random(7);
    const pieces = ['a', 'bc', '\n', 'é', '\n\n', '😀', '```\n', '- ', '> ', '---\n', r'$$', '*', '[a]: /b\n', '[a]', '|x|\n|-|\n', '===', '    ', '1. '];
    for (var round = 0; round < 300; round++) {
      var text = 'one\ntwo\n\nthree';
      final t = NoteText('$text\n');
      final syntax = NoteSyntax(t);
      for (var k = 0; k < 20; k++) {
        final start = random.nextInt(text.length + 1);
        final end = start + random.nextInt(text.length - start + 1);
        final insert = random.nextBool() ? pieces[random.nextInt(pieces.length)] : '';
        if (start == end && insert.isEmpty) continue;
        final before = t.lineCount;
        final splice = t.apply(Delta()
          ..retain(start)
          ..delete(end - start)
          ..insert(insert))!;
        text = text.substring(0, start) + insert + text.substring(end);
        expect(t.text, text);
        expect(t.lineCount, before - splice.removed + splice.inserted);
        syntax.splice(splice);
        final fresh = NoteSyntax(NoteText('$text\n'));
        for (var i = 0; i < t.lineCount; i++) {
          expect(_marks(syntax.line(i)), _marks(fresh.line(i)), reason: 'line $i of ${text.split('\n')}');
        }
      }
    }
  });

  test('follows a delta of several ops as one splice', () {
    final t = NoteText('a\nb\nc\nd\n');
    final splice = t.apply(Delta()
      ..insert('x\n')
      ..retain(4)
      ..delete(2)
      ..insert('y'))!;
    expect(t.text, 'x\na\nb\nyd');
    expect(splice, (index: 0, removed: 4, inserted: 4));
  });
}

List<Object> _marks(LineSyntax s) => [s.ends, s.marks, s.heading, s.block, s.swaps];
