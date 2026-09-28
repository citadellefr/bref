import 'dart:convert';
import 'dart:io';

import 'package:bref/bref.dart';
import 'package:bref/src/word/document.dart';
import 'package:bref/src/word/edits.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeHub hub;
  late DocSession session;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(hub.settle);
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, String fixture, {Size size = const Size(1400, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    hub = FakeHub.tree(Edit.fromJson(jsonDecode(File('../testdata/docx/$fixture.json').readAsStringSync()))!);
    session = DocSession(hub.connect)..start();
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WordEditor(session: session, media: (_) async => Uint8List(0), title: '$fixture.docx')),
    ));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Node body() => flowsOf(hub.doc).first;

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
  }

  /// Clicks the first page near its top-left corner, in the text.
  Future<void> clickText(WidgetTester tester) async {
    final page = find.byType(CustomPaint).evaluate().map((e) => e.renderObject! as RenderBox).firstWhere((b) => b.size.width < 1000 && b.size.height > 1000);
    await tester.tapAt(page.localToGlobal(const Offset(150, 110)));
    await settle(tester);
  }

  testWidgets('shows the ribbon, the pages and the status', (tester) async {
    await open(tester, 'par-known-styles');
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Mise en page'), findsWidgets);
    expect(find.text('Page 1 sur 1'), findsOneWidget);
    expect(find.textContaining('mots'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('fits a phone', (tester) async {
    await open(tester, 'par-known-styles', size: const Size(390, 844));
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Page 1 sur 1'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('types, bolds and splits paragraphs', (tester) async {
    await open(tester, 'par-known-styles');
    await clickText(tester);
    final before = body().text!.text;
    await ctrl(tester, LogicalKeyboardKey.home);
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: 'Bref ${before.substring(0, before.length - 1)}',
      selection: const TextSelection.collapsed(offset: 5),
    ));
    await settle(tester);
    expect(body().text!.text, startsWith('Bref '));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await ctrl(tester, LogicalKeyboardKey.keyG);
    expect(wordEditing(body()).attributesAt(1)?['b'], '1');

    final paragraphs = body().text!.text.split('\n').length;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(body().text!.text.split('\n').length, paragraphs + 1);
    await finish(tester);
  });

  testWidgets('applies a style and centers', (tester) async {
    await open(tester, 'par-known-styles');
    await clickText(tester);
    await ctrl(tester, LogicalKeyboardKey.keyE);
    expect(wordEditing(body()).markAt(0)['jc'], 'center');
    await finish(tester);
  });

  test('inserts a table after the paragraph, the flow cut there', () {
    final tree = Tree.fromEdit(Edit.fromJson(jsonDecode(File('../testdata/docx/par-known-styles.json').readAsStringSync()))!)!;
    final doc = WordDocument(tree);
    final flow = flowsOf(tree).first;
    final text = flow.text!.text;
    final edit = WordEdits(doc).insertTable(flow, 0, 2, 3, 400);
    expect(tree.apply(edit), isNotNull);
    final kids = tree.children('body');
    expect(kids.map((n) => n.type).take(3), ['text', 'tbl', 'text']);
    final table = kids[1];
    expect(tree.children(table.id), hasLength(2));
    expect(tree.children(tree.children(table.id).first.id), hasLength(3));
    expect(table.attributes['grid'], [2666, 2666, 2666]);
    expect('${kids[0].text!.text}${kids[2].text!.text}', text);

    final cell = tree.children(tree.children(table.id).first.id).first;
    expect(tree.apply(WordEdits(WordDocument(tree)).insertColumn(cell, right: true)), isNotNull);
    expect(tree.children(tree.children(table.id).first.id), hasLength(4));
    expect(tree[table.id]!.attributes['grid'], hasLength(4));
    expect(tree.apply(WordEdits(WordDocument(tree)).deleteRow(cell)), isNotNull);
    expect(tree.children(table.id), hasLength(1));
  });
}
