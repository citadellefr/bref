import 'package:bref/bref.dart';
import 'package:bref/src/handles.dart';
import 'package:bref/src/render.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trame/testing.dart';
import 'package:trame/trame.dart';

/// The platform's keyboard: sends deltas over the text input channel, and
/// keeps the value the platform would hold.
class Keyboard {
  Keyboard(this.tester);

  final WidgetTester tester;
  Map<String, dynamic>? _seen;
  var _value = TextEditingValue.empty;

  TextEditingValue get value {
    final sent = tester.testTextInput.editingState;
    if (!identical(sent, _seen)) {
      _seen = sent;
      _value = TextEditingValue.fromJSON(sent!);
    }
    return _value;
  }

  int get _client {
    final call = tester.testTextInput.log.lastWhere((c) => c.method == 'TextInput.setClient');
    return (call.arguments as List<Object?>)[0]! as int;
  }

  Future<void> _send(int start, int end, String text) async {
    final old = value;
    final caret = start + text.length;
    final json = {
      'oldText': old.text,
      'deltaText': text,
      'deltaStart': start,
      'deltaEnd': end,
      'selectionBase': caret,
      'selectionExtent': caret,
      'selectionAffinity': 'TextAffinity.downstream',
      'selectionIsDirectional': false,
      'composingBase': -1,
      'composingEnd': -1,
    };
    _value = TextEditingDelta.fromJSON(json).apply(old);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        MethodCall('TextInputClient.updateEditingStateWithDeltas', [
          _client,
          {
            'deltas': [json],
          },
        ]),
      ),
      (_) {},
    );
  }

  Future<void> type(String text) {
    final s = value.selection;
    return _send(s.start, s.end, text);
  }

  Future<void> backspace() {
    final s = value.selection;
    return _send(s.isCollapsed ? s.start - 1 : s.start, s.end, '');
  }
}

void main() {
  late FakeHub hub;
  late DocSession mine;
  late DocSession theirs;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(hub.settle);
    await tester.pump();
  }

  Future<void> pumpEditor(WidgetTester tester, String text, {BrefHost? host}) async {
    hub = FakeHub(text);
    mine = DocSession(hub.connect)..start();
    theirs = DocSession(hub.connect)..start();
    addTearDown(mine.dispose);
    addTearDown(theirs.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrefEditor(session: mine, host: host, autofocus: true))));
    await settle(tester);
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  NoteMarks marks(WidgetTester tester) => tester.widget<NoteViewport>(find.byType(NoteViewport)).marks;

  RenderNote note(WidgetTester tester) => tester.renderObject<RenderNote>(find.byType(NoteViewport));

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key, {bool control = false, bool shift = false}) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('sends what is typed, and only the lines around the caret to the platform', (tester) async {
    await pumpEditor(tester, 'zero\none\ntwo\nthree');
    final keyboard = Keyboard(tester);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(keyboard.value.text, 'zero\none\ntwo');
    await keyboard.type('Hi ');
    await settle(tester);
    expect(hub.text, 'zero\nHi one\ntwo\nthree');
    expect(theirs.text, hub.text);
    expect(marks(tester).base, 8);
    await keyboard.backspace();
    await settle(tester);
    expect(hub.text, 'zero\nHi one\ntwo\nthree'.replaceFirst('Hi ', 'Hi'));
    await finish(tester);
  });

  testWidgets('signs what it writes', (tester) async {
    await pumpEditor(tester, 'one');
    final keyboard = Keyboard(tester);
    await keyboard.type('Hi\n');
    await settle(tester);
    expect(hub.text, 'Hi\none');
    expect(hub.doc['body']!.text!.ops.first, Op.insert('Hi\n', {'by': mine.id}));
    await finish(tester);
  });

  testWidgets('Enter goes on with a list, and ends it on an empty item', (tester) async {
    await pumpEditor(tester, '- un');
    final keyboard = Keyboard(tester);
    await key(tester, LogicalKeyboardKey.end);
    await keyboard.type('\n');
    await keyboard.type('deux');
    await key(tester, LogicalKeyboardKey.enter);
    await key(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(hub.text, '- un\n- deux\n');
    await finish(tester);
  });

  testWidgets('moves by characters, words and rows, and selects with Shift', (tester) async {
    await pumpEditor(tester, 'Le chat noir\nsuite');
    await key(tester, LogicalKeyboardKey.arrowRight, control: true);
    expect(marks(tester).extent, 2);
    await key(tester, LogicalKeyboardKey.arrowRight, control: true, shift: true);
    expect((marks(tester).base, marks(tester).extent), (2, 7));
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect((marks(tester).base, marks(tester).extent), (7, 7));
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(marks(tester).extent, 18);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(marks(tester).extent, 7);
    await key(tester, LogicalKeyboardKey.end, control: true);
    expect(marks(tester).extent, 18);
    await key(tester, LogicalKeyboardKey.backspace, control: true);
    await settle(tester);
    expect(hub.text, 'Le chat noir\n');
    await key(tester, LogicalKeyboardKey.backspace);
    await settle(tester);
    expect(hub.text, 'Le chat noir');
    await key(tester, LogicalKeyboardKey.keyZ, control: true);
    await settle(tester);
    expect(hub.text, 'Le chat noir\nsuite');
    expect(marks(tester).extent, 18);
    await finish(tester);
  });

  testWidgets('follows the edits of others, and shows where they are', (tester) async {
    await pumpEditor(tester, 'one\ntwo');
    await key(tester, LogicalKeyboardKey.arrowDown);
    theirs
      ..replace(0, 0, '>> ')
      ..select(DocSelection(noteBody, 1, 1));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
    expect(marks(tester).extent, 7);
    expect(marks(tester).peers, [(sid: 2, name: 'Peer 2', base: 1, extent: 1)]);
    await finish(tester);
  });

  testWidgets('a long note: the caret is kept in view, lines inserted above leave the view still', (tester) async {
    await pumpEditor(tester, [for (var i = 0; i < 3000; i++) 'Ligne $i, assez longue pour être lue sans peine.'].join('\n'));
    final viewHeight = note(tester).size.height;
    await key(tester, LogicalKeyboardKey.end, control: true);
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, greaterThan(10000));
    var caret = note(tester).caretRect(marks(tester).extent);
    expect(caret.top, inInclusiveRange(0, viewHeight));

    position.jumpTo(position.pixels / 2);
    await tester.pump();
    final at = note(tester).offsetAt(const Offset(100, 200));
    final before = note(tester).caretRect(at).top;
    theirs.replace(0, 0, 'nouvelle\n' * 50);
    await settle(tester);
    caret = note(tester).caretRect(at + 9 * 50);
    expect(caret.top, moreOrLessEquals(before, epsilon: 0.5));
    await finish(tester);
  });

  testWidgets('a click places the caret, a double click selects a word, a drag extends', (tester) async {
    await pumpEditor(tester, 'Le chat noir');
    final render = note(tester);
    Offset at(int offset) => render.localToGlobal(render.caretRect(offset).center);
    final mouse = await tester.startGesture(at(5), kind: PointerDeviceKind.mouse);
    await mouse.up();
    await tester.pump();
    expect((marks(tester).base, marks(tester).extent), (5, 5));
    await mouse.down(at(5), timeStamp: const Duration(milliseconds: 150));
    await mouse.up(timeStamp: const Duration(milliseconds: 200));
    await tester.pump();
    expect((marks(tester).base, marks(tester).extent), (3, 7));
    await mouse.down(at(1), timeStamp: const Duration(seconds: 2));
    await mouse.moveTo(at(10), timeStamp: const Duration(milliseconds: 2100));
    await mouse.up(timeStamp: const Duration(milliseconds: 2200));
    await tester.pump();
    expect((marks(tester).base, marks(tester).extent), (1, 10));
    await finish(tester);
  });

  testWidgets('copies and pastes through the clipboard', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
    await pumpEditor(tester, 'abc\r');
    await key(tester, LogicalKeyboardKey.keyA, control: true);
    await key(tester, LogicalKeyboardKey.keyC, control: true);
    expect(clipboard, 'abc\r');
    clipboard = 'x\r\ny';
    await key(tester, LogicalKeyboardKey.end, control: true);
    await key(tester, LogicalKeyboardKey.keyV, control: true);
    await tester.pump();
    await settle(tester);
    expect(hub.text, 'abc\rx\ny');
    await finish(tester);
  });

  testWidgets('a long press selects a word, whose ends move with handles', (tester) async {
    await pumpEditor(tester, 'Le chat noir dort');
    final render = note(tester);
    Offset at(int offset) => render.localToGlobal(render.caretRect(offset).center);
    await tester.longPressAt(at(5));
    await tester.pumpAndSettle();
    expect((marks(tester).base, marks(tester).extent), (3, 7));
    final handles = find.descendant(of: find.byType(SelectionHandles), matching: find.byType(Positioned));
    expect(handles, findsNWidgets(2));
    await tester.drag(handles.last, at(15) - at(7));
    await tester.pump();
    expect((marks(tester).start, marks(tester).end), (3, 15));
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byType(SelectionHandles), findsNothing);
    await finish(tester);
  });

  testWidgets('the lines being edited show their syntax, the others read as they render', (tester) async {
    await pumpEditor(tester, '**gras** fin\n**gras** fin');
    double end(int offset) => note(tester).caretRect(offset).left;
    expect(end(12), greaterThan(end(25)));
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(end(12), lessThan(end(25)));
    expect(end(25) - end(12), moreOrLessEquals(4 * 16, epsilon: 4));
    await finish(tester);
  });

  testWidgets('a click in a line read as it renders lands where its text is written', (tester) async {
    await pumpEditor(tester, '**gras** fin\n[un lien](https://x.fr) ici');
    final render = note(tester);
    final row = render.caretRect(13);
    final left = render.caretRect(0).left;
    await tester.tapAt(render.localToGlobal(Offset(left + 8 * 16 + 4, row.center.dy)), kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout);
    expect(marks(tester).extent, 13 + 24);
    await finish(tester);
  });

  testWidgets('a click on the box of a task ticks it, and leaves the caret', (tester) async {
    await pumpEditor(tester, '- [ ] à faire\nsuite');
    await key(tester, LogicalKeyboardKey.arrowDown);
    final render = note(tester);
    final row = render.caretRect(0);
    final box = Offset(render.caretRect(0).left + 2 * 16 + 9, row.center.dy);
    await tester.tapAt(render.localToGlobal(box), kind: PointerDeviceKind.mouse);
    await settle(tester);
    expect(hub.text, '- [x] à faire\nsuite');
    expect(marks(tester).extent, 14);
    await tester.pump(kDoubleTapTimeout);
    await tester.tapAt(render.localToGlobal(box), kind: PointerDeviceKind.mouse);
    await settle(tester);
    expect(hub.text, '- [ ] à faire\nsuite');
    await finish(tester);
  });

  testWidgets('a click opens the links of lines read as they render, to where the host goes', (tester) async {
    const line = '[site](https://a.b) [x](javascript:alert(1)) [[Note#Part]] [@A](user:1) [@B](group:2)';
    final host = _Host();
    await pumpEditor(tester, 'first\n$line', host: host);
    final render = note(tester);
    Future<void> click(String text, {bool control = false}) async {
      final at = render.caretRect(6 + line.indexOf(text));
      if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(render.localToGlobal(at.centerLeft + const Offset(3, 0)), kind: PointerDeviceKind.mouse);
      if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(kDoubleTapTimeout);
    }

    for (final text in ['site', 'Note', '@A']) {
      await click(text);
    }
    expect(host.opened, [Uri.parse('https://a.b'), Uri(path: 'Note', fragment: 'Part'), Uri.parse('user:1')]);
    expect(marks(tester).extent, 0);

    // a link to nowhere the host goes is text: the click places the caret,
    // and the line shows as written
    host.opened.clear();
    await click('@B');
    expect(marks(tester).extent, greaterThan(6));
    await click('x]');
    await click('site');
    expect(host.opened, isEmpty);
    await click('site', control: true);
    expect(host.opened, [Uri.parse('https://a.b')]);
    await finish(tester);
  });

  testWidgets('a trigger typed at the start of a word proposes what the host has', (tester) async {
    await pumpEditor(tester, 'Ask ', host: _Host());
    final keyboard = Keyboard(tester);
    await key(tester, LogicalKeyboardKey.end);
    await keyboard.type('a@');
    await tester.pump();
    expect(find.text('@Alice'), findsNothing);

    await keyboard.backspace();
    await keyboard.backspace();
    await keyboard.type('@');
    await tester.pump();
    expect(find.text('@Alice'), findsOneWidget);
    expect(find.text('@Bob'), findsOneWidget);
    await keyboard.type('b');
    await tester.pump();
    expect(find.text('@Alice'), findsNothing);
    await key(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(hub.text, 'Ask [@Bob](user:2) ');
    expect(find.text('@Bob'), findsNothing);

    await keyboard.type('[[');
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowDown);
    await keyboard.type('\n');
    await settle(tester);
    expect(hub.text, 'Ask [@Bob](user:2) [My \\[draft\\]](<note:draft(2)>) ');

    await keyboard.type('@');
    await tester.pump();
    await key(tester, LogicalKeyboardKey.escape);
    await keyboard.type('\n');
    await settle(tester);
    expect(hub.text, 'Ask [@Bob](user:2) [My \\[draft\\]](<note:draft(2)>) @\n');
    await finish(tester);
  });

  testWidgets('shows the whole note as written when asked to', (tester) async {
    hub = FakeHub('**gras** fin\n**gras** fin');
    mine = DocSession(hub.connect)..start();
    addTearDown(mine.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrefEditor(session: mine, autofocus: true, preview: false))));
    await settle(tester);
    expect(note(tester).caretRect(12).left, note(tester).caretRect(25).left);
    await finish(tester);
  });
}

class _Host extends BrefHost {
  final opened = <Uri>[];

  @override
  Set<String> get schemes => const {'user'};

  @override
  void open(Uri uri) => opened.add(uri);

  @override
  Map<String, MentionSource> get mentions => {
    '@': (query) async => [
      for (final (i, name) in ['Alice', 'Bob'].indexed)
        if (name.toLowerCase().startsWith(query)) Mention('@$name', Uri.parse('user:${i + 1}')),
    ],
    '[[': (query) async => [Mention('Plan', Uri.parse('note:1')), Mention('My [draft]', Uri.parse('note:draft(2)'))],
  };
}
