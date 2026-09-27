import 'package:bref/src/excel/input.dart';
import 'package:bref/src/excel/number_format.dart';
import 'package:bref/src/excel/workbook.dart';
import 'package:bref/src/ot/grid.dart';
import 'package:bref/src/ot/tree.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Tree book(List<Cell> cells, {Map<String, Object?> attributes = const {}}) => Tree.fromEdit(Edit([
  Change.create(const Node(id: 'book', type: 'book', key: 'V', attributes: {
    'theme': {'colors': ['FFFFFF', '000000', 'E7E6E6', '44546A', '4472C4', 'ED7D31', 'A5A5A5', 'FFC000', '5B9BD5', '70AD47', '0563C1', '954F72']},
  })),
  Change.create(Node(id: 'S1', type: 'sheet', parent: 'book', key: 'V', attributes: {'name': 'Feuil1', ...attributes}, grid: Grid(cells))),
  Change.create(const Node(id: 'x1', type: 'xf', key: 'V', attributes: {
    'style': {
      'fmt': '#,##0.00 "€"',
      'font': {'name': 'Calibri', 'sz': 12, 'b': true, 'color': {'theme': 4, 'tint': 0.4}},
      'fill': {'pattern': 'solid', 'fg': {'rgb': 'FFFF00'}},
      'border': {'b': {'style': 'double', 'color': {'rgb': 'FF0000'}}},
      'align': {'h': 'center', 'wrap': true},
    },
  })),
]))!;

void main() {
  test('styles resolve colors, fonts and formats', () {
    final w = Workbook(book(const []));
    final s = w.style('x1');
    expect(s.font.bold, isTrue);
    expect(s.font.size, 12);
    expect(s.fill, const Color(0xFFFFFF00));
    expect(s.bottom!.style, 'double');
    expect(s.horizontal, 'center');
    expect(s.font.color!.toARGB32(), tinted(const Color(0xFF4472C4), 0.4).toARGB32());
    final t = cellText({'v': 1234.5, 's': 'x1'}, s, NumberLocale.fr);
    expect(t.text, '1 234,50 €');
    expect(t.align, 'center');
    expect(cellText({'e': '#VALUE!'}, w.style(null), NumberLocale.fr).text, '#VALEUR!');
    expect(cellText({'v': true}, w.style(null), NumberLocale.fr).text, 'VRAI');
    expect(cellText({'v': 12}, w.style(null), NumberLocale.fr).align, 'right');
  });

  test('palette colors become theme tints', () {
    expect(cellColor({'scheme': 'accent1', 'mods': [['lumMod', 20000], ['lumOff', 80000]]}), {'theme': 4, 'tint': 0.8});
    expect(cellColor({'scheme': 'lt1', 'mods': [['lumMod', 85000]]}), {'theme': 0, 'tint': -0.15});
    expect(cellColor({'rgb': 'FF0000'}), {'rgb': 'FF0000'});
  });

  test('layout of rows and columns', () {
    final tree = book([
      const Cell(0, 2, {'w': 20}),
      const Cell(0, 4, {'hide': true}),
      const Cell(3, 0, {'h': 30}),
      const Cell(5, 0, {'hide': true}),
      const Cell(2, 2, {'m': [2, 3], 'v': 'fusion'}),
    ], attributes: {'frozen': {'r': 1, 'c': 1}});
    final l = SheetLayout(tree['S1']!);
    expect(l.width(1), 64);
    expect(l.width(2), 140);
    expect(l.width(4), 0);
    expect(l.x(3), 204);
    expect(l.y(3), 40);
    expect(l.y(4), 80);
    expect(l.y(6), 100);
    expect(l.rowAt(79), 3);
    expect(l.rowAt(81), 4);
    expect(l.colAt(203), 2);
    expect(l.mergeAt(3, 4), const CellArea(2, 2, 3, 4));
    expect(l.frozenRows, 1);
    expect(l.used, 5);
  });

  test('typing into cells', () {
    final now = DateTime(2024, 6, 1);
    expect(parseInput('1 234,5', now: now).fields['v'], 1234.5);
    expect(parseInput('1 234,5', now: now).format, '#,##0');
    expect(parseInput('12,5 %', now: now).fields['v'], closeTo(0.125, 1e-12));
    expect(parseInput('12,5 %', now: now).format, '0.0%');
    expect(parseInput('12,50 €', now: now).fields['v'], 12.5);
    expect(parseInput('25/12/2024', now: now).fields['v'], 45651);
    expect(parseInput('25/12/2024', now: now).format, 'dd/mm/yyyy');
    expect(parseInput('12:30', now: now).fields['v'], closeTo(0.5208333, 1e-6));
    expect(parseInput('=SOMME(A1;A2)', now: now).fields['f'], 'SUM(A1,A2)');
    expect(parseInput("'123", now: now).fields['v'], '123');
    expect(parseInput('vrai', now: now).fields['v'], true);
    expect(parseInput('#N/A', now: now).fields['e'], '#N/A');
    expect(parseInput('1.5', now: now).fields['v'], '1.5');
    expect(parseInput('Bonjour', now: now).fields['v'], 'Bonjour');
    expect(parseInput('', now: now).fields, {'v': null, 'f': null, 'e': null, 'rich': null});
  });

  test('text a cell is edited from', () {
    expect(editText({'f': 'SUM(A1,A2)', 'v': 3}), '=SOMME(A1;A2)');
    expect(editText({'v': 0.1 + 0.2}), '0,3');
    expect(editText({'v': 45651}, format: NumberFormat('dd/mm/yyyy')), '25/12/2024');
    expect(editText({'v': 0.25}, format: NumberFormat('0%')), '25%');
  });

  test('names of cells', () {
    expect(columnName(28), 'AB');
    expect(cellName(3, 16384), 'XFD3');
    expect(parseCell(r'$B$7'), (7, 2));
    expect(const CellArea(3, 2, 1, 1).name, 'A1:B3');
    expect(const CellArea(1, 2, maxRows, 3).name, 'B:C');
  });
}
