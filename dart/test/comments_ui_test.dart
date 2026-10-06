import 'package:bref/bref.dart';
import 'package:bref/src/render.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trame/testing.dart';
import 'package:trame/trame.dart';

void main() {
  late FakeHub hub;
  late DocSession session;
  late BrefComments comments;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(hub.settle);
    await tester.pump();
  }

  Future<void> pump(WidgetTester tester, String text) async {
    hub = FakeHub(text);
    session = DocSession(hub.connect)..start();
    addTearDown(session.dispose);
    await tester.runAsync(hub.settle);
    comments = BrefComments(session);
    addTearDown(comments.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          Expanded(child: BrefEditor(session: session, comments: comments, autofocus: true)),
          SizedBox(width: 320, child: CommentsPane(comments: comments)),
        ]),
      ),
    ));
    await settle(tester);
  }

  NoteMarks marks(WidgetTester tester) => tester.widget<NoteViewport>(find.byType(NoteViewport)).marks;

  Future<void> comment(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('a comment is written about the selection, marks it, and is answered', (tester) async {
    await pump(tester, 'Hello wide world');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await comment(tester);
    expect(comments.draft, const TextRange(start: 0, end: 16));
    expect(marks(tester).passages, hasLength(1));

    await tester.enterText(find.byType(TextField), 'Why?');
    await tester.pump();
    await tester.tap(find.text('Post'));
    await tester.pump();
    expect(comments.draft, isNull);
    expect(comments.threads.single.messages.single.text, 'Why?');
    expect(comments.selected, comments.threads.single.id);
    expect(find.text('Why?'), findsOneWidget);
    expect(marks(tester).passages, hasLength(1));

    await tester.enterText(find.byType(TextField), 'Because');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(comments.threads.single.messages.map((m) => m.text), ['Why?', 'Because']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the passage follows the text typed before it, and resolving clears it', (tester) async {
    await pump(tester, 'Hello wide world');
    final id = session.startThread(6, 10, 'Why?')!;
    await tester.pump();
    expect(marks(tester).passages.single.from, 6);

    session.replaceText('body', 0, 0, 'Oh. ');
    await tester.pump();
    expect(comments.threads.single.ranges.single, const TextRange(start: 10, end: 14));
    expect(marks(tester).passages.single.from, 10);

    session.resolve(id);
    comments.select(null);
    await tester.pump();
    expect(marks(tester).passages, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the note shows who wrote what on demand', (tester) async {
    await pump(tester, 'Hello');
    session.edit(Edit([Change.text('body', Delta()..retain(5)..insert(' there', {'by': 'u1'}))]));
    await tester.pump();
    expect(marks(tester).passages, isEmpty);
    comments.authorship = true;
    await tester.pump();
    expect(marks(tester).passages.single.from, 5);
    expect(marks(tester).passages.single.to, 11);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
