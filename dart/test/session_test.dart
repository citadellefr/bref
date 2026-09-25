import 'dart:async';
import 'dart:math';

import 'package:bref/bref.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeHub hub;
  final sessions = <DocSession>[];

  Future<DocSession> open([String? clientId]) async {
    final session = DocSession(hub.connect, clientId: clientId)..start();
    sessions.add(session);
    await pumpEventQueue();
    await hub.settle();
    return session;
  }

  setUp(() => hub = FakeHub('one\ntwo'));

  tearDown(() {
    for (final s in sessions) {
      s.dispose();
    }
    sessions.clear();
  });

  test('comes online with the document', () async {
    final s = await open();
    expect(s.status, DocStatus.online);
    expect(s.text, 'one\ntwo');
    expect(s.saved, isTrue);
  });

  test('sends one edit at a time and composes the next ones', () async {
    final s = await open();
    final link = hub.links.single;
    s.replaceText(0, 0, 'a');
    s.replaceText(1, 1, 'b');
    s.replaceText(2, 2, 'c');
    expect(s.text, 'abcone\ntwo');
    expect(link.up.map((m) => m['d']), [
      [{'i': 'a'}],
    ]);
    expect(s.saved, isFalse);
    await hub.settle();
    expect(link.sent.where((m) => m['t'] == 'op').map((m) => m['d']), [
      [{'i': 'a'}],
      [{'r': 1}, {'i': 'bc'}],
    ]);
    expect(hub.text, 'abcone\ntwo');
  });

  test('concurrent editors converge', () async {
    final random = Random(3);
    final editors = [for (var i = 0; i < 3; i++) await open()];
    for (var step = 0; step < 400; step++) {
      final s = editors[random.nextInt(editors.length)];
      final length = s.text.length;
      final at = random.nextInt(length + 1);
      switch (random.nextInt(3)) {
        case 0 when at < length:
          s.replaceText(at, min(length, at + 1 + random.nextInt(3)), '');
        default:
          s.replaceText(at, at, ['x', 'yz', '\n', 'é'][random.nextInt(4)]);
      }
      final link = hub.links[random.nextInt(hub.links.length)];
      if (random.nextBool()) {
        link.deliverUp();
      } else {
        link.deliverDown();
      }
      await Future<void>.delayed(Duration.zero);
    }
    await hub.settle();
    for (final s in editors) {
      expect(s.text, hub.text);
      expect(s.saved, isFalse);
    }
  });

  test('edits made offline reach the document on reconnection', () async {
    final a = await open('a');
    final b = await open('b');
    await hub.links.first.drop();
    await pumpEventQueue();
    expect(a.status, DocStatus.offline);

    a.replaceText(3, 3, ' (a)');
    b.replaceText(0, 0, 'B: ');
    await hub.settle();
    a.retry();
    await pumpEventQueue();
    await hub.settle();
    expect(hub.text, 'B: one (a)\ntwo');
    expect(a.text, hub.text);
    expect(b.text, hub.text);
  });

  test('an edit whose acknowledgement was lost is not applied twice', () async {
    final a = await open('a');
    final b = await open('b');
    a.replaceText(0, 0, 'x');
    hub.links.first.deliverUp();
    await hub.links.first.drop();
    await pumpEventQueue();
    b.replaceText(7, 7, '!');
    await hub.settle();
    a.retry();
    await pumpEventQueue();
    await hub.settle();
    expect(hub.text, 'xone\ntwo!');
    expect(a.text, hub.text);
  });

  test('after a server restart, local edits are rebased on the text', () async {
    final a = await open('a');
    final b = await open('b');
    await hub.links.first.drop();
    await pumpEventQueue();
    a.replaceText(7, 7, ' (a)');
    b.replaceText(0, 3, 'ONE');
    await hub.settle();
    await hub.restart();
    await pumpEventQueue();
    a.retry();
    b.retry();
    await pumpEventQueue();
    await hub.settle();
    expect(hub.text, 'ONE\ntwo (a)');
    expect(a.text, hub.text);
    expect(b.text, hub.text);
  });

  test('undo reverts only its own edits', () async {
    final a = await open();
    final b = await open();
    a.replaceText(0, 0, 'A');
    await hub.settle();
    b.replaceText(4, 4, 'B');
    await hub.settle();
    expect(a.text, 'AoneB\ntwo');
    a.undo();
    await hub.settle();
    expect(b.text, 'oneB\ntwo');
    a.redo();
    await hub.settle();
    expect(b.text, 'AoneB\ntwo');
    expect(a.canRedo, isFalse);
  });

  test('typing is undone in one step', () async {
    final s = await open();
    for (final c in 'hello'.split('')) {
      s.replaceText(s.text.length, s.text.length, c);
    }
    s.undo();
    expect(s.text, 'one\ntwo');
  });

  test('a refused edit is rolled back, the later ones kept', () async {
    final s = await open();
    final reasons = <String>[];
    s.rejections.listen(reasons.add);
    hub.refuse = 'read-only access';
    s.replaceText(0, 0, 'x');
    s.replaceText(1, 1, 'y');
    hub.links.single.deliverUp();
    hub.refuse = '';
    await hub.settle();
    expect(reasons, ['read-only access']);
    expect(s.text, 'yone\ntwo');
    expect(hub.text, 'yone\ntwo');
  });

  test('never deletes the last paragraph mark', () async {
    final s = await open();
    expect(s.edit(Delta()..retain(7)..delete(1)), isFalse);
    expect(s.edit(Delta()..retain(8)..insert('x')), isFalse);
    expect(s.replaceText(0, 7, ''), isTrue);
    expect(s.text, '');
  });

  test('shows where others are, following the text', () async {
    final a = await open();
    final b = await open();
    b.select(4, 7);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await hub.settle();
    expect(a.peers.single.selection, (4, 7));
    a.replaceText(0, 0, '>> ');
    expect(a.peers.single.selection, (7, 10));
    unawaited(b.stop());
  });
}
