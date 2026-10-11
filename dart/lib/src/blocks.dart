import 'package:flutter/material.dart';

import 'mentions.dart';
import 'strings.dart';

/// Where a block is written when it is chosen: where the caret is, at the
/// start of a line, or on lines of its own with a blank one around.
enum Placement { inline, line, apart }

/// Something a `/` writes: the Markdown [before] and [after] the caret,
/// with [selected] between them ready to be typed over.
@immutable
class Block {
  const Block(
    this.name,
    this.icon,
    this.before, {
    this.selected = '',
    this.after = '',
    this.placement = Placement.apart,
    this.figure = false,
  });

  final String name;
  final IconData icon;
  final String before, selected, after;
  final Placement placement;

  /// Whether the block is drawn, as a formula or a chart are: a host whose
  /// notes are read elsewhere may leave those out.
  final bool figure;
}

/// What a `/` proposes, named by [s].
List<Block> blocks(BrefStrings s, {DateTime? now}) {
  final today = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  Block heading(int level) =>
      Block(s.heading(level), Icons.title, '${'#' * level} ', placement: Placement.line);
  Block callout(String name, IconData icon, String kind) => Block(name, icon, '> [!$kind]\n> ');
  Block chart(String name, IconData icon, String type, String rows) => Block(
    name,
    icon,
    '```chart\ntype: $type\ntitle: ',
    selected: s.chartTitle,
    after: '\n$rows\n```',
    figure: true,
  );
  final series = '| ${s.category} | ${s.series(1)} | ${s.series(2)} |\n| --- | --- | --- |\n| A | 3 | 5 |\n| B | 4 | 2 |\n| C | 6 | 4 |';
  return [
    heading(1),
    heading(2),
    heading(3),
    Block(s.bulletedList, Icons.format_list_bulleted, '- ', placement: Placement.line),
    Block(s.numberedList, Icons.format_list_numbered, '1. ', placement: Placement.line),
    Block(s.todoList, Icons.check_box_outlined, '- [ ] ', placement: Placement.line),
    Block(s.quote, Icons.format_quote, '> ', placement: Placement.line),
    Block(s.divider, Icons.horizontal_rule, '---\n'),
    Block(
      s.table,
      Icons.table_chart_outlined,
      '| ',
      selected: s.column(1),
      after: ' | ${s.column(2)} |\n| --- | --- |\n|  |  |',
    ),
    Block(s.codeBlock, Icons.code, '```\n', after: '\n```'),
    callout(s.calloutNote, Icons.info_outline, 'note'),
    callout(s.calloutTip, Icons.lightbulb_outline, 'tip'),
    callout(s.calloutWarning, Icons.warning_amber, 'warning'),
    callout(s.calloutDanger, Icons.report_outlined, 'danger'),
    Block(s.formula, Icons.functions, r'$$' '\n', after: '\n' r'$$', figure: true),
    Block(s.inlineFormula, Icons.functions, r'$', after: r'$', placement: Placement.inline, figure: true),
    chart(s.barChart, Icons.bar_chart, 'bar', series),
    chart(s.lineChart, Icons.show_chart, 'line', series),
    chart(s.areaChart, Icons.area_chart, 'area', series),
    chart(s.pieChart, Icons.pie_chart_outline, 'pie', '| ${s.category} | ${s.series(1)} |\n| --- | --- |\n| A | 3 |\n| B | 4 |\n| C | 6 |'),
    chart(s.scatterChart, Icons.scatter_plot, 'scatter', '| x | ${s.series(1)} |\n| --- | --- |\n| 1 | 2 |\n| 2 | 3.5 |\n| 3 | 3 |\n| 4 | 6 |'),
    Block(s.link, Icons.link, '[', selected: s.linkText, after: '](https://)', placement: Placement.inline),
    Block(s.today, Icons.today, '${today.year}-${two(today.month)}-${two(today.day)}', placement: Placement.inline),
  ];
}

/// Those of [all] that [typed] names: each of its words starts one of
/// theirs, on any keyboard.
Iterable<Block> blocksNamed(List<Block> all, String typed) {
  final wanted = fold(typed).split(' ').where((w) => w.isNotEmpty);
  return all.where((b) {
    final words = fold(b.name).split(' ');
    return wanted.every((w) => words.any((word) => word.startsWith(w)));
  });
}
