import 'dart:io';

import 'package:bref/src/layout.dart';
import 'package:bref/src/note_syntax.dart';
import 'package:bref/src/note_text.dart';
import 'package:bref/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trame/testing.dart';
import 'package:trame/trame.dart';

/// What opening a note of 1 MB costs, and a keystroke in it: a measure, not
/// a test, run when $BREF_BENCH is set.
void main() {
  testWidgets('opens a note of 1 MB, then types in it', skip: Platform.environment['BREF_BENCH'] == null, (tester) async {
    const line = 'Un paragraphe de notes avec du **gras**, un [lien](https://x.fr) et du `code`.';
    final text = List.generate((1 << 20) ~/ (line.length + 1), (i) => i % 20 == 0 ? '## Titre $i' : line).join('\n');
    late BrefTheme theme;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      theme = BrefTheme.of(context);
      return const SizedBox();
    })));

    var watch = Stopwatch()..start();
    final note = NoteText('$text\n');
    final syntax = NoteSyntax(note);
    final layout = NoteLayout(note, syntax, theme: theme, scaler: TextScaler.noScaling, preview: true)..width = 700;
    for (var i = 0; i < 40; i++) {
      layout.view(i);
    }
    final open = watch.elapsedMicroseconds;

    final hub = FakeHub(text);
    final session = DocSession(hub.connect)..start();
    await tester.runAsync(hub.settle);
    final middle = note.lineStart(note.lineCount ~/ 2) + 10;
    const keys = 200;
    var inSession = 0, inEditor = 0;
    for (var k = 0; k < keys; k++) {
      final delta = Delta()
        ..retain(middle + k)
        ..insert('a');
      watch = Stopwatch()..start();
      session.edit(Edit([Change.text('body', delta)]));
      inSession += watch.elapsedMicroseconds;
      watch = Stopwatch()..start();
      final splice = note.apply(delta)!;
      layout
        ..splice(splice, syntax.splice(splice))
        ..view(splice.index);
      inEditor += watch.elapsedMicroseconds;
    }
    // ignore: avoid_print
    print('${note.lineCount} lines: opened in ${open ~/ 1000} ms; a keystroke costs the session '
        '${inSession ~/ keys} µs and the editor ${inEditor ~/ keys} µs');
    session.dispose();
  });
}
