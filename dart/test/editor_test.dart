import 'package:bref/bref.dart';
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

  Future<void> pumpEditor(WidgetTester tester, String text) async {
    hub = FakeHub(text);
    mine = DocSession(hub.connect)..start();
    theirs = DocSession(hub.connect)..start();
    addTearDown(mine.dispose);
    addTearDown(theirs.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrefEditor(session: mine, autofocus: true))));
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
}
