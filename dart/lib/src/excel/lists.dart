import '../ot/grid.dart';
import '../ot/tree.dart';
import 'number_format.dart';
import 'workbook.dart';

/// A validation of cells by a list of values, as the Go package reads
/// those of a sheet into its "lists".
class ListRule {
  ListRule._(this.areas, this.src, this._json);

  static List<ListRule> of(Node sheet) {
    final all = sheet.attributes['lists'];
    if (all is! List<Object?>) return const [];
    return [
      for (final l in all)
        if (l is Map<String, Object?> && l['ref'] is String && l['src'] is String)
          ListRule._([for (final a in (l['ref']! as String).split(' ')) ?parseArea(a)], l['src']! as String, l),
    ];
  }

  final List<CellArea> areas;

  /// The list as a formula: values in quotes separated by commas, the
  /// cells or the name that holds them.
  final String src;
  final Map<String, Object?> _json;

  bool get arrow => _json['noArrow'] != true;

  bool get blank => _json['blank'] == true;

  /// How a value out of the list is taken: 'stop', 'warning' or
  /// 'information'; any value is when null.
  String? get error => _json['err'] as String?;

  String get errorTitle => _json['errTitle'] as String? ?? '';

  String get errorText => _json['errText'] as String? ?? '';

  String get promptTitle => _json['promptTitle'] as String? ?? '';

  String get prompt => _json['prompt'] as String? ?? '';

  bool contains(int row, int col) => areas.any((a) => a.contains(row, col));

  /// The values of the list as the cells holding them show them, null
  /// when the list is a formula calculated by the server alone.
  List<String>? items(Workbook book, Node sheet, NumberLocale locale) {
    final s = src.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1).replaceAll('""', '"').split(',');
    }
    final found = _resolve(book, sheet, s) ?? _named(book, sheet, s);
    if (found == null) return null;
    final (on, area) = found;
    final out = <String>[];
    for (final c in (on.grid ?? const Grid.empty()).rows(area.top, area.bottom)) {
      if (c.col < area.left || c.col > area.right || c.fields['v'] == null && c.fields['e'] == null) continue;
      final text = cellText(c.fields, book.style(c.fields['s'] as String?), locale, date1904: book.date1904).text;
      if (text.isNotEmpty) out.add(text);
    }
    return out;
  }

  /// The sheet and area of a reference, the sheet named or [sheet].
  static (Node, CellArea)? _resolve(Workbook book, Node sheet, String ref) {
    var on = sheet;
    var a = ref;
    final bang = ref.lastIndexOf('!');
    if (bang > 0) {
      var name = ref.substring(0, bang);
      if (name.length >= 2 && name.startsWith("'") && name.endsWith("'")) {
        name = name.substring(1, name.length - 1).replaceAll("''", "'");
      }
      final found = book.sheets.where((n) => '${n.attributes['name']}'.toLowerCase() == name.toLowerCase()).firstOrNull;
      if (found == null) return null;
      on = found;
      a = ref.substring(bang + 1);
    }
    final area = parseArea(a);
    return area == null ? null : (on, area);
  }

  /// The sheet and area of a defined name, the name of [sheet] first.
  static (Node, CellArea)? _named(Workbook book, Node sheet, String name) {
    final names = book.tree['book']?.attributes['names'];
    if (names is! List<Object?>) return null;
    Map<String, Object?>? best;
    for (final n in names) {
      if (n is! Map<String, Object?> || '${n['name']}'.toLowerCase() != name.toLowerCase()) continue;
      if (n['sheet'] == sheet.id || n['sheet'] == null && best == null) best = n;
    }
    final ref = best?['ref'];
    return ref is String ? _resolve(book, sheet, ref) : null;
  }

  /// Whether the list takes what was typed: one of its values, whatever
  /// the case, or nothing when blanks are allowed.
  bool takes(String typed, List<String> items) {
    final t = typed.trim().toLowerCase();
    if (t.isEmpty) return blank;
    return items.any((i) => i.trim().toLowerCase() == t);
  }
}
