import 'dart:math';
import 'dart:ui' as ui;

import 'package:bref/bref.dart';
import 'package:bref/src/chart/figure.dart';
import 'package:bref/src/chart/spec.dart';
import 'package:bref/src/line_view.dart';
import 'package:bref/src/render.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _sales = 'type: bar\ntitle: Ventes\ny: k€\n| Mois | Paris | Lyon |\n| --- | --- | --- |\n| Janvier | 12 | 8 |\n| Février | 1 500,5 | -3 |';

void main() {
  test('a chart is its keys, then a table whose first column names the rows', () {
    final spec = ChartSpec.parse(_sales)!;
    expect(spec.type, ChartType.bar);
    expect([spec.title, spec.yLabel, spec.xLabel], ['Ventes', 'k€', '']);
    expect(spec.categories, ['Janvier', 'Février']);
    expect(spec.xs, isNull);
    expect([for (final s in spec.series) s.name], ['Paris', 'Lyon']);
    expect(spec.series[0].values, [12, 1500.5]);
    expect(spec.series[1].values, [8, -3]);
    expect(spec.decimal, ',');
    expect(spec.stacked, isFalse);
  });

  test('numbers are read as they are written, and what is not one is a hole', () {
    final spec = ChartSpec.parse('type: line\nstacked: true\nx | a | b\n1 | 12 % | n/a\n2.5 | −4 | texte\n3 | | 7€')!;
    expect(spec.type, ChartType.line);
    expect(spec.stacked, isTrue);
    expect(spec.xs, [1, 2.5, 3]);
    expect(spec.series[0].values, [12, -4, null]);
    expect(spec.series[1].values, [null, null, 7]);
    expect(spec.decimal, '.');
    expect(ChartSpec.parse(r'| a \| b | n |' '\n| c | 1 |')!.series.single.name, 'n');
  });

  test('a block that describes no chart is none', () {
    expect(ChartSpec.parse(''), isNull);
    expect(ChartSpec.parse('type: bar\ntitle: rien'), isNull);
    expect(ChartSpec.parse('| a | b |\n|---|---|'), isNull);
    expect(ChartSpec.parse('| a | b |\n| x | texte |'), isNull);
    expect(ChartSpec.parse('type: inconnu\n| a | b |\n| x | 1 |'), isNull);
    expect(ChartSpec.parse('type: scatter\n| a | b |\n| x | 1 |'), isNull);
    expect(ChartSpec.parse('type: pie\n| a | b |\n| x | -1 |'), isNull);
    expect(ChartSpec.parse('| a | b |\n| x | 1 |')!.type, ChartType.bar);
  });

  testWidgets('every kind of chart is laid out in the width it is given, and drawn', (tester) async {
    late BrefTheme theme;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      theme = BrefTheme.of(context);
      return const SizedBox();
    })));
    final random = Random(3);
    for (final type in ChartType.values) {
      for (final width in [0.0, 200.0, 480.0, 2000.0]) {
        for (var round = 0; round < 8; round++) {
          final rows = random.nextInt(30) + 1, columns = random.nextInt(4) + 1;
          final source = StringBuffer('type: ${type.name}\ntitle: T\nx: x\ny: y\nstacked: ${round.isEven}\n| x |${' s |' * columns}\n');
          for (var r = 0; r < rows; r++) {
            source.write('| ${r * 1.5} |');
            for (var c = 0; c < columns; c++) {
              source.write(random.nextInt(6) == 0 ? ' |' : ' ${(random.nextDouble() - (round < 4 ? 0 : 0.5)) * pow(10, round - 2)} |');
            }
            source.write('\n');
          }
          final spec = ChartSpec.parse(source.toString());
          if (spec == null) continue;
          final figure = ChartFigure(spec, width: width, theme: theme, scaler: TextScaler.noScaling);
          expect(figure.size.width, inInclusiveRange(120, 640), reason: source.toString());
          expect(figure.size.height.isFinite && figure.size.height > 160, isTrue, reason: source.toString());
          final recorder = ui.PictureRecorder();
          figure.paint(Canvas(recorder), Offset.zero);
          recorder.endRecording().dispose();
          figure.dispose();
        }
      }
    }
  });

  testWidgets('a block of chart shows its chart, its source over it while the caret is in it', (tester) async {
    final session = localNote('début\n\n```chart\n$_sales\n```\n\n```chart\nrien\n```');
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrefEditor(session: session, autofocus: true))));
    await tester.pump();
    final layout = tester.widget<NoteViewport>(find.byType(NoteViewport)).layout;
    final shown = layout.view(2);
    expect(shown, isA<FigureView>());
    expect(shown.height, greaterThan(200));
    expect(layout.lineHeight(5), 0);
    expect(layout.view(12), isA<TextView>());

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(layout.view(2), isA<TextView>());
    expect((layout.view(10) as TextView).below, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
