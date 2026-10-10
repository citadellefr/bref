/// How the data of a chart is drawn.
enum ChartType { bar, line, area, pie, scatter }

/// A column of the data: its heading, and a value for each row that has one.
typedef ChartSeries = ({String name, List<double?> values});

/// A chart as a block describes it: lines of `key: value`, then a table
/// whose first column names the rows and each other column is a series.
///
/// ```chart
/// type: bar
/// title: Sales
/// | Month | Paris | Lyon |
/// | --- | --- | --- |
/// | January | 12 | 8 |
/// ```
class ChartSpec {
  const ChartSpec({
    required this.type,
    required this.title,
    required this.xLabel,
    required this.yLabel,
    required this.stacked,
    required this.categories,
    required this.xs,
    required this.series,
    required this.decimal,
  });

  final ChartType type;
  final String title, xLabel, yLabel;

  /// Whether the series of bars and areas go one over the other.
  final bool stacked;

  /// What the first column says of each row.
  final List<String> categories;

  /// The first column as numbers, when every row has one there.
  final List<double>? xs;
  final List<ChartSeries> series;

  /// The mark between units and decimals, as the data writes it.
  final String decimal;

  static final _option = RegExp(r'^([A-Za-z]+)\s*:\s*(.*)$');
  static final _rule = RegExp(r'^:?-+:?$');
  static final _number = RegExp(r'^([+\-−]?)(\d+(?:[.,]\d+)?|[.,]\d+)[%€$£]?$');
  static final _blank = RegExp(r'[\s  ]');

  /// The chart [source] describes, or null when it has no data to draw.
  static ChartSpec? parse(String source) {
    final options = <String, String>{};
    final rows = <List<String>>[];
    for (final raw in source.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (!line.contains('|')) {
        final m = _option.firstMatch(line);
        if (m != null) options[m[1]!.toLowerCase()] = m[2]!.trim();
        continue;
      }
      final cells = _cells(line);
      if (cells.every(_rule.hasMatch)) continue;
      rows.add(cells);
    }
    if (rows.length < 2) return null;
    final data = rows.sublist(1);
    var comma = false;
    double? number(String cell) {
      final m = _number.firstMatch(cell.replaceAll(_blank, ''));
      if (m == null) return null;
      comma = comma || m[2]!.contains(',');
      final value = double.parse(m[2]!.replaceFirst(',', '.'));
      return m[1] == '' || m[1] == '+' ? value : -value;
    }

    final series = <ChartSeries>[];
    for (var k = 1; k < rows.first.length; k++) {
      final values = [for (final row in data) k < row.length ? number(row[k]) : null];
      if (values.any((v) => v != null)) series.add((name: rows.first[k], values: values));
    }
    final type = ChartType.values.asNameMap()[options['type']?.toLowerCase() ?? 'bar'];
    if (series.isEmpty || type == null) return null;
    final xs = [for (final row in data) number(row.first)];
    if (type == ChartType.scatter && xs.contains(null)) return null;
    if (type == ChartType.pie && !series.first.values.any((v) => v != null && v > 0)) return null;
    return ChartSpec(
      type: type,
      title: options['title'] ?? '',
      xLabel: options['x'] ?? '',
      yLabel: options['y'] ?? '',
      stacked: options['stacked']?.toLowerCase() == 'true',
      categories: [for (final row in data) row.first],
      xs: xs.contains(null) ? null : xs.cast<double>(),
      series: series,
      decimal: comma ? ',' : '.',
    );
  }

  /// The cells of a row of a table, its outer bars aside.
  static List<String> _cells(String line) {
    final cells = <String>[];
    final cell = StringBuffer();
    for (var k = 0; k < line.length; k++) {
      final c = line[k];
      if (c == r'\' && k + 1 < line.length && line[k + 1] == '|') {
        cell.write('|');
        k++;
      } else if (c == '|') {
        if (k > 0) cells.add(cell.toString().trim());
        cell.clear();
      } else {
        cell.write(c);
      }
    }
    if (cell.toString().trim().isNotEmpty) cells.add(cell.toString().trim());
    return cells;
  }
}
