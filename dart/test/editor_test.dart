import 'dart:async';
import 'dart:ui' as ui;

import 'package:bref/bref.dart';
import 'package:bref/src/handles.dart';
import 'package:bref/src/render.dart';
import 'package:bref/src/syntax.dart' show SwapKind;
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

  Future<void> pumpEditor(WidgetTester tester, String text, {BrefHost? host, Key? key}) async {
    hub = FakeHub(text);
    mine = DocSession(hub.connect)..start();
    theirs = DocSession(hub.connect)..start();
    addTearDown(mine.dispose);
    addTearDown(theirs.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrefEditor(key: key, session: mine, host: host, autofocus: true))));
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

  testWidgets('a keyword written after an @ searches what the host mentions under it', (tester) async {
    final host = _Host();
    await pumpEditor(tester, 'See ', host: host);
    final keyboard = Keyboard(tester);
    await key(tester, LogicalKeyboardKey.end);
    await keyboard.type('@');
    await tester.pump();
    expect(find.text('@tasks'), findsOneWidget);
    expect(find.text('@assistant'), findsOneWidget);
    expect(find.text('@Alice'), findsOneWidget);

    await keyboard.type('t');
    await tester.pump();
    expect(find.text('@assistant'), findsNothing);
    await key(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(hub.text, 'See @tasks ');
    expect(find.text('Search in tasks…'), findsOneWidget);
    expect(find.text('@Buy bread'), findsOneWidget);
    expect(find.text('@Call Bob'), findsOneWidget);

    await keyboard.type('zz');
    await tester.pump();
    expect(find.text('No result'), findsOneWidget);
    await keyboard.backspace();
    await keyboard.backspace();
    await keyboard.type('bob');
    await tester.pump();
    expect(find.text('@Buy bread'), findsNothing);
    await key(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(hub.text, 'See [@Call Bob](todo:2) ');
    expect(find.text('@Call Bob'), findsNothing);

    // typed as a keyboard with accents writes it
    await keyboard.type('@');
    await keyboard.type('tâsks ');
    await tester.pump();
    expect(find.text('@Buy bread'), findsOneWidget);
    host.failing = true;
    await keyboard.type('b');
    await tester.pump();
    expect(find.text('The search failed'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a keyword that answers takes the line as its question, and its answer takes its place', (tester) async {
    final host = _Host();
    await pumpEditor(tester, 'Before\n\nAfter', host: host);
    final keyboard = Keyboard(tester);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await keyboard.type('@');
    await keyboard.type('assistant ');
    await tester.pump();
    expect(find.text('Write your question, then Enter'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    await settle(tester);
    expect(hub.text, 'Before\n@assistant \n\nAfter');

    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.end);
    await keyboard.type('s');
    await keyboard.type('um it up');
    await tester.pump();
    expect(find.text('Ask'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(host.asked, [('sum it up', 'Before\n', '\n\nAfter')]);
    expect(find.text('Thinking…'), findsOneWidget);
    expect(tester.state<BrefEditorState>(find.byType(BrefEditor)).answering, isTrue);

    // the note is held meanwhile, but for the others
    await key(tester, LogicalKeyboardKey.backspace);
    await settle(tester);
    expect(hub.text, 'Before\n@assistant sum it up\n\nAfter');
    theirs.edit(Edit([Change.text('body', Delta()..insert('# '))]));
    await settle(tester);
    host.answers.add(const Answer.step('Reads the note'));
    await tester.pump();
    expect(find.text('Reads the note'), findsOneWidget);
    host.answers.add(const Answer.done('It is short.'));
    await tester.pump();
    await settle(tester);
    expect(hub.text, '# Before\nIt is short.\n\nAfter');
    expect(marks(tester).extent, 9 + 12);
    expect(find.text('Reads the note'), findsNothing);

    // giving up leaves the question as written
    await keyboard.type(' @');
    await keyboard.type('assistant why');
    await tester.pump();
    await key(tester, LogicalKeyboardKey.enter);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.escape);
    await tester.pump();
    expect(host.answers.hasListener, isFalse);
    await keyboard.type('?');
    await settle(tester);
    expect(hub.text, '# Before\nIt is short. @assistant why?\n\nAfter');
    await finish(tester);
  });

  testWidgets('lines read as they render show the pictures and labels of the host', (tester) async {
    final host = _Host();
    host.picture = (await tester.runAsync(() => _png(200, 100)))!;
    await pumpEditor(tester, 'first\n![chart](drive:9) [@A](user:1) [@B](user:2)\nlast', host: host);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    final render = note(tester);
    final layout = tester.widget<NoteViewport>(find.byType(NoteViewport)).layout;
    expect(render.caretRect(layout.text.lineStart(2)).top - render.caretRect(layout.text.lineStart(1)).top, greaterThan(100));
    expect(layout.view(1).painter.plainText, endsWith(' \uFFFC${String.fromCharCode(Icons.person.codePoint)}\u2009Alice Martin\uFFFC \uFFFC${String.fromCharCode(Icons.person.codePoint)}\u2009@B\uFFFC'));
    expect(layout.view(1).chips, hasLength(2));
    await finish(tester);
  });

  testWidgets('an address the host describes is a chip with its picture, as written while edited', (tester) async {
    final host = _Host();
    host.picture = (await tester.runAsync(() => _png(16, 16)))!;
    await pumpEditor(tester, 'first\nsee https://x.fr now', host: host);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    final layout = tester.widget<NoteViewport>(find.byType(NoteViewport)).layout;
    final view = layout.view(1);
    expect(view.painter.plainText, 'see \uFFFC\uFFFC\u2009The X site\uFFFC now');
    expect(view.ornaments.where((o) => o.kind == SwapKind.label), hasLength(1));
    expect(layout.view(0).chips, isEmpty);
    await finish(tester);
  });

  testWidgets('a link pointed at shows the card of the host, which leaves with the pointer', (tester) async {
    final host = _Host();
    await pumpEditor(tester, 'first\nask [@A](user:1) today', host: host);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    final render = note(tester);
    final layout = tester.widget<NoteViewport>(find.byType(NoteViewport)).layout;
    final on = render.localToGlobal(render.caretRect(layout.text.lineStart(1) + 5).center + const Offset(12, 0));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(on);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('card of user:1'), findsOneWidget);
    await mouse.moveTo(render.localToGlobal(render.caretRect(1).center));
    await tester.pump();
    expect(find.text('card of user:1'), findsNothing);

    await tester.tapAt(on);
    await tester.pump();
    expect(find.text('card of user:1'), findsOneWidget);
    expect(host.opened, isEmpty);
    await finish(tester);
  });

  testWidgets('a picture uploads to the host, and lands on a line of its own where the caret was', (tester) async {
    final host = _Host();
    final editor = GlobalKey<BrefEditorState>();
    await pumpEditor(tester, 'one two', host: host, key: editor);
    await key(tester, LogicalKeyboardKey.arrowRight, control: true);
    final done = editor.currentState!.insertPicture(Uint8List(4), 'my chart.png', 'image/png');
    theirs.replace(0, 0, '>> ');
    await settle(tester);
    host.uploaded.complete(Uri.parse('drive:9'));
    await tester.pump();
    await done;
    await settle(tester);
    expect(hub.text, '>> one\n![my chart](drive:9)\n two');
    expect(host.uploads, [('my chart.png', 'image/png', 4)]);
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

/// A picture of [width] by [height] pixels, as a PNG.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = Colors.teal);
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class _Host extends BrefHost {
  final opened = <Uri>[];
  Uint8List? picture;
  final uploaded = Completer<Uri>();
  final uploads = <(String, String, int)>[];

  @override
  Set<String> get schemes => const {'user', 'drive'};

  @override
  void open(Uri uri) => opened.add(uri);

  @override
  ImageProvider? image(Uri uri) => uri.toString() == 'drive:9' && picture != null ? MemoryImage(picture!) : null;

  @override
  Future<LinkLabel?> describe(Uri uri) async =>
      switch (uri.toString()) {
        'user:1' => const LinkLabel('Alice Martin', icon: Icons.person),
        'https://x.fr' => LinkLabel('The X site', image: MemoryImage(picture!)),
        'user:2' => const LinkLabel('', icon: Icons.person),
        _ => null,
      };

  @override
  Widget? preview(Uri uri) => uri.scheme == 'user' ? Text('card of $uri') : null;

  @override
  Future<Uri> upload(Uint8List bytes, String name, String type) {
    uploads.add((name, type, bytes.length));
    return uploaded.future;
  }

  var failing = false;
  final asked = <(String, String, String)>[];
  var answers = StreamController<Answer>();

  @override
  List<Command> get commands => [
    Command(
      'tasks',
      icon: Icons.task_alt,
      search: (query) async {
        if (failing) throw StateError('down');
        return [
          for (final (i, title) in ['Buy bread', 'Call Bob'].indexed)
            if (title.toLowerCase().contains(query)) Mention('@$title', Uri.parse('todo:${i + 1}'), detail: 'Today'),
        ];
      },
    ),
    Command(
      'assistant',
      answer: (question, {required before, required after}) {
        asked.add((question, before, after));
        unawaited(answers.close());
        return (answers = StreamController<Answer>()).stream;
      },
    ),
  ];

  @override
  Map<String, MentionSource> get mentions => {
    '@': (query) async => [
      for (final (i, name) in ['Alice', 'Bob'].indexed)
        if (name.toLowerCase().startsWith(query)) Mention('@$name', Uri.parse('user:${i + 1}')),
    ],
    '[[': (query) async => [Mention('Plan', Uri.parse('note:1')), Mention('My [draft]', Uri.parse('note:draft(2)'))],
  };
}
