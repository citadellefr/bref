import 'dart:ui';

import 'package:bref/bref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a local note is edited with no hub behind it, and read back', (tester) async {
    final session = localNote('Bonjour');
    addTearDown(session.dispose);
    final editor = GlobalKey<BrefEditorState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BrefEditor(key: editor, session: session, autofocus: true)),
    ));
    await tester.pump();

    expect(session.loaded, isTrue);
    expect(session.readOnly, isFalse);
    expect(noteText(session), 'Bonjour');

    editor.currentState!.insert('Madame, ');
    await tester.pump();
    expect(noteText(session), 'Madame, Bonjour');
    editor.currentState!.insert('monsieur. ');
    await tester.pump();
    expect(noteText(session), 'Madame, monsieur. Bonjour');
    expect(session.saved, isTrue);

    // typed in one burst, undone in one
    session.undo();
    await tester.pump();
    expect(noteText(session), 'Bonjour');

    // the caret is told to nobody, on the timer it would be told on
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a click in the note takes the focus from a text field', (tester) async {
    final session = localNote('Bonjour');
    addTearDown(session.dispose);
    final field = FocusNode(), note = FocusNode();
    addTearDown(field.dispose);
    addTearDown(note.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TextField(focusNode: field),
          Expanded(child: BrefEditor(session: session, focusNode: note)),
        ]),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(field.hasFocus, isTrue);

    // with a mouse, as on the web and the desktop: there a field gives its
    // focus up when clicked outside of
    await tester.tap(find.byType(BrefEditor), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(note.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  test('the text of a note not loaded yet is empty', () {
    final session = localNote('Bonjour');
    addTearDown(session.dispose);
    expect(noteText(session), '');
  });
}
