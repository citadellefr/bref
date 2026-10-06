import 'dart:ui' show TextRange;

import 'package:bref/src/comments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trame/testing.dart';
import 'package:trame/trame.dart';

void main() {
  late FakeHub hub;
  late DocSession session;

  Future<void> open(String text) async {
    hub = FakeHub(text);
    session = DocSession(hub.connect)..start();
    await hub.settle();
  }

  tearDown(() => session.dispose());

  List<CommentThread> threads() => readThreads(session.document);

  test('a thread is about a passage, and answered', () async {
    await open('Hello wide world');
    final id = session.startThread(6, 10, 'Why?')!;
    expect(threads(), hasLength(1));
    expect(threads().single.id, id);
    expect(threads().single.ranges, [const TextRange(start: 6, end: 10)]);
    expect(threads().single.messages.single.text, 'Why?');
    expect(threads().single.messages.single.by, session.id);

    expect(session.reply(id, 'Because'), isTrue);
    expect(threads().single.messages.map((m) => m.text), ['Why?', 'Because']);

    expect(session.resolve(id), isTrue);
    expect(threads().single.done, isTrue);
    expect(session.resolve(id, done: false), isTrue);
    expect(threads().single.done, isFalse);
  });

  test('text typed inside a passage splits it', () async {
    await open('Hello wide world');
    session.startThread(6, 10, 'Why?');
    session.edit(Edit([
      Change.text('body', Delta()..retain(8)..insert('+')),
    ]));
    expect(threads().single.ranges, [const TextRange(start: 6, end: 8), const TextRange(start: 9, end: 11)]);
    expect(threads().single.span, const TextRange(start: 6, end: 11));
  });

  test('a thread whose passage was deleted stays', () async {
    await open('Hello wide world');
    session.startThread(6, 10, 'Why?');
    session.replaceText('body', 5, 11, '');
    expect(threads().single.orphan, isTrue);
  });

  test('deleting a thread takes its mark off the text, and undoing brings both back', () async {
    await open('Hello wide world');
    final id = session.startThread(6, 10, 'Why?')!;
    session.reply(id, 'Because');
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(session.deleteThread(id), isTrue);
    expect(threads(), isEmpty);
    expect(session.document['body']!.text!.ops.every((op) => op.attributes == null), isTrue);

    session.undo();
    expect(threads(), hasLength(1));
    expect(threads().single.ranges, [const TextRange(start: 6, end: 10)]);
    expect(threads().single.messages.map((m) => m.text), ['Why?', 'Because']);
    expect(threads().single.id, isNot(id));
  });

  test('deleting the only message deletes the thread', () async {
    await open('Hello wide world');
    final id = session.startThread(6, 10, 'Why?')!;
    final second = session.reply(id, 'Because');
    expect(second, isTrue);
    final first = threads().single.messages.first.id;
    expect(session.deleteMessage(first), isTrue);
    expect(threads().single.messages, hasLength(1));
    expect(session.deleteMessage(threads().single.messages.single.id), isTrue);
    expect(threads(), isEmpty);
  });
}
