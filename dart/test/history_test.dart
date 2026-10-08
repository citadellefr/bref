import 'package:bref/bref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trame/testing.dart';

class _Host extends BrefHost {
  _Host(this.stored);

  final Map<String, String> stored;
  Object? failure;

  @override
  Future<List<NoteVersion>> versions() async {
    if (failure != null) throw failure!;
    return [
      for (final id in stored.keys) NoteVersion(id: id, at: DateTime(2026, 10, 5, 12, int.parse(id)), authors: const ['Alice']),
    ];
  }

  @override
  Future<String> version(String id) async => stored[id]!;
}

void main() {
  test('a difference of lines keeps what both have', () {
    String show(List<DiffLine> d) => d.map((l) => '${switch (l.kind) {
      DiffKind.same => '=',
      DiffKind.added => '+',
      DiffKind.removed => '-',
    }}${l.text}').join(' ');
    expect(show(lineDiff(['a', 'b', 'c', 'd'], ['a', 'x', 'c', 'd', 'e'])), '=a -b +x =c =d +e');
    expect(show(lineDiff(['a'], ['a'])), '=a');
    expect(show(lineDiff([], ['a'])), '+a');
    expect(show(lineDiff(['a', 'b'], ['b', 'a'])), '-a =b +a');
  });

  group('restoring', () {
    late FakeHub hub;
    late DocSession session;

    setUp(() async {
      hub = FakeHub('# Title\n\nOne line\nTwo lines 🎉 end');
      session = DocSession(hub.connect, clientId: 'me')..start();
      await hub.settle();
    });

    tearDown(() => session.dispose());

    test('replaces only what differs, in an edit that undo takes back', () async {
      session.replaceText('body', 9, 9, 'new ');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final before = session.document['body']!.text!.text;
      expect(session.restoreText('# Title\n\nOne line\nTwo lines 🎉 end\r\nlast'), isTrue);
      expect(session.document['body']!.text!.text, '# Title\n\nOne line\nTwo lines 🎉 end\nlast\n');
      session.undo();
      expect(session.document['body']!.text!.text, before);
    });

    test('does nothing when the note is the version', () {
      expect(session.restoreText('# Title\n\nOne line\nTwo lines 🎉 end'), isFalse);
    });

    test('never splits a pair of surrogates', () {
      expect(session.restoreText('# Title\n\nOne line\nTwo lines 🎊 end'), isTrue);
      expect(session.document['body']!.text!.text, '# Title\n\nOne line\nTwo lines 🎊 end\n');
    });
  });

  testWidgets('the pane lists versions, shows what restoring changes and restores', (tester) async {
    final hub = FakeHub('one\ntwo');
    final session = DocSession(hub.connect, clientId: 'me')..start();
    addTearDown(session.dispose);
    await tester.runAsync(hub.settle);
    final host = _Host({'01': 'one\ntwo\nthree', '02': 'one\ntwo'});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HistoryPane(session: session, host: host))));
    await tester.pump();
    expect(find.text('2026-10-05 12:01'), findsOneWidget);
    expect(find.text('Alice'), findsNWidgets(2));

    await tester.tap(find.text('2026-10-05 12:02'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Same as the note now'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    await tester.tap(find.text('2026-10-05 12:01'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('+ three'), findsOneWidget);
    await tester.tap(find.text('Restore this version'));
    await tester.pump();
    expect(session.document['body']!.text!.text, 'one\ntwo\nthree\n');
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets('a host that fails is told, with a way to retry', (tester) async {
    final hub = FakeHub('one');
    final session = DocSession(hub.connect)..start();
    addTearDown(session.dispose);
    final host = _Host({})..failure = 'No network';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HistoryPane(session: session, host: host))));
    await tester.pump();
    expect(find.text('No network'), findsOneWidget);
    host.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('No earlier versions'), findsOneWidget);
  });
}
