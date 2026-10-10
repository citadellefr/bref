import 'package:bref/bref.dart';
import 'package:bref/src/layout.dart';
import 'package:bref/src/line_view.dart';
import 'package:bref/src/math/font.dart';
import 'package:bref/src/render.dart';
import 'package:bref/src/syntax.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<NoteLayout> pumpNote(WidgetTester tester, String text, {bool font = true}) async {
    if (font && MathFont.loaded == null) await tester.runAsync(MathFont.load);
    final session = localNote(text);
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrefEditor(session: session, autofocus: true))));
    await tester.pump();
    return tester.widget<NoteViewport>(find.byType(NoteViewport)).layout;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  int caret(WidgetTester tester) => tester.widget<NoteViewport>(find.byType(NoteViewport)).marks.extent;

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key, {bool control = false}) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('the font of math is read when a note first shows math', (tester) async {
    expect(MathFont.loaded, isNull);
    final layout = await pumpNote(tester, 'fin \$x^2\$\n\n\$\$\nx\n\$\$', font: false);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(MathFont.loaded, isNotNull);
    expect(layout.view(0).ornaments.single.kind, SwapKind.formula);
    expect(layout.view(2), isA<FigureView>());
    await finish(tester);
  });

  testWidgets('a formula in a line stands for its source, on the baseline of the text', (tester) async {
    final layout = await pumpNote(tester, 'a\nsoit \$\\frac{a}{b}\$ ici, et 5 \$ de plus\n\$\$\\sum_{i=1}^n i\$\$');
    final render = tester.renderObject<RenderNote>(find.byType(NoteViewport));
    final formula = layout.view(1).ornaments.single;
    expect(formula.kind, SwapKind.formula);
    expect(formula.column, 5);
    expect(formula.rect.width, moreOrLessEquals(formula.formula!.width, epsilon: 0.01));
    expect(formula.rect.left, moreOrLessEquals(render.caretRect(2 + 5).left - render.caretRect(2).left, epsilon: 1));
    expect(render.caretRect(2 + 18).left, moreOrLessEquals(render.caretRect(2).left + formula.rect.right, epsilon: 1));
    expect(layout.view(2).ornaments.single.kind, SwapKind.display);
    expect(layout.lineHeight(2), greaterThan(layout.lineHeight(0) * 1.5));

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(layout.view(1).ornaments, isEmpty);
    await finish(tester);
  });

  testWidgets('a block of math shows its formula alone, and under its source while the caret is in it', (tester) async {
    const text = 'début\n\n\$\$\n\\frac{a}{b}\n\$\$\n\nfin';
    final layout = await pumpNote(tester, text);
    final row = layout.lineHeight(0);
    final shown = layout.view(2);
    expect(shown, isA<FigureView>());
    expect(shown.height, greaterThan(row));
    expect([layout.lineHeight(3), layout.lineHeight(4)], [0, 0]);
    final whole = layout.height;

    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(caret(tester), text.indexOf(r'$$'));
    expect(layout.view(2), isA<TextView>());
    expect(layout.view(3), isA<TextView>());
    final last = layout.view(4) as TextView;
    expect(last.below!.figure!.size, (shown as FigureView).figure!.size);
    expect(last.height, greaterThan(shown.height + row * 0.9));
    expect(layout.height, greaterThan(whole + 2 * row));

    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(caret(tester), text.lastIndexOf(r'$$'));
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(caret(tester), text.lastIndexOf(r'$$') + 3);
    expect(layout.view(2), isA<FigureView>());
    expect(layout.height, whole);

    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(caret(tester), text.indexOf(r'$$'));
    await finish(tester);
  });

  testWidgets('a click on a formula opens its source', (tester) async {
    const text = 'début\n\n\$\$\nx^2\n\$\$\n\nfin';
    final layout = await pumpNote(tester, text);
    final render = tester.renderObject<RenderNote>(find.byType(NoteViewport));
    final at = Offset(render.size.width / 2 + 40, render.caretRect(7).center.dy);
    await tester.tapAt(render.localToGlobal(at), kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout);
    expect(caret(tester), 9);
    expect(layout.view(2), isA<TextView>());
    await finish(tester);
  });

  testWidgets('math left open, or held in a quote, stays as written', (tester) async {
    final layout = await pumpNote(tester, 'a\n\n> \$\$\n> x\n> \$\$\n\n\$\$\nx');
    expect(layout.view(2), isA<TextView>());
    expect(layout.view(6), isA<TextView>());
    await finish(tester);
  });

  testWidgets('the cells of a table show their formulas', (tester) async {
    final layout = await pumpNote(tester, '| aire | \$\\pi r^2\$ |\n|---|---|\n| b | c |\n\nfin');
    await key(tester, LogicalKeyboardKey.end, control: true);
    final row = layout.view(0);
    expect(row, isA<GridRowView>());
    final formula = row.ornaments.single;
    expect(formula.kind, SwapKind.formula);
    expect(formula.rect.left, greaterThan((row as GridRowView).grid.left(1)));
    expect(formula.rect.right, lessThan(row.grid.width));
    await finish(tester);
  });
}
