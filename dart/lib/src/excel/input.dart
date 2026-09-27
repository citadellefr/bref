import 'formula_text.dart';
import 'number_format.dart';

/// What typing into a cell sets: its fields, and a number format when
/// what was typed says one, a percentage or a date.
class CellInput {
  const CellInput(this.fields, [this.format]);

  final Map<String, Object?> fields;
  final String? format;
}

const _cleared = {'v': null, 'f': null, 'e': null, 'rich': null};

const _errorCodes = ['#NULL!', '#DIV/0!', '#VALUE!', '#REF!', '#NAME?', '#NUM!', '#N/A'];

/// Reads what was typed into a cell, as the French version of Excel does.
CellInput parseInput(String text, {NumberLocale locale = NumberLocale.fr, DateTime? now, bool date1904 = false}) {
  if (text.isEmpty) return const CellInput(_cleared);
  if (text.startsWith("'")) return CellInput({..._cleared, 'v': text.substring(1)});
  if (text.length > 1 && text.startsWith('=')) {
    return CellInput({..._cleared, 'f': locale.french ? formulaFromFrench(text.substring(1)) : text.substring(1)});
  }
  final t = text.trim();
  final upper = t.toUpperCase();
  if (upper == 'VRAI' || upper == 'TRUE') return CellInput({..._cleared, 'v': true});
  if (upper == 'FAUX' || upper == 'FALSE') return CellInput({..._cleared, 'v': false});
  for (final code in _errorCodes) {
    if (upper == code || upper == errorText(code)) return CellInput({..._cleared, 'e': code});
  }
  final percent = _number(t.endsWith('%') ? t.substring(0, t.length - 1).trim() : '', locale);
  if (percent != null) {
    final decimals = _decimals(t, locale);
    return CellInput({..._cleared, 'v': percent / 100}, decimals > 0 ? '0.${'0' * decimals}%' : '0%');
  }
  final euros = t.endsWith('€') || t.startsWith('€') ? _number(t.replaceAll('€', '').trim(), locale) : null;
  if (euros != null) return CellInput({..._cleared, 'v': euros}, '#,##0.00 "€"');
  final n = _number(t, locale);
  if (n != null) return CellInput({..._cleared, 'v': n}, _grouped(t) ? '#,##0' : null);
  final date = _date(t, now ?? DateTime.now(), date1904);
  if (date != null) return CellInput({..._cleared, 'v': date.$1}, date.$2);
  return CellInput({..._cleared, 'v': text});
}

/// Whether a number was typed with its thousands grouped.
bool _grouped(String t) => RegExp('[0-9][ \u00a0\u202f][0-9]{3}').hasMatch(t);

int _decimals(String t, NumberLocale l) {
  final i = t.indexOf(l.decimal);
  if (i < 0) return 0;
  return RegExp('^[0-9]*').firstMatch(t.substring(i + 1))![0]!.length;
}

double? _number(String t, NumberLocale l) {
  if (t.isEmpty) return null;
  var s = t.replaceAll(RegExp('[ \u00a0\u202f]'), '');
  if (l.french) {
    if (s.contains('.')) return null;
    s = s.replaceAll(',', '.');
  } else {
    s = s.replaceAll(',', '');
  }
  if (!RegExp(r'^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$').hasMatch(s)) return null;
  final n = double.tryParse(s);
  return n != null && n.isFinite ? n : null;
}

/// A date, a time or both, and the format that shows them as typed.
(double, String)? _date(String t, DateTime now, bool date1904) {
  final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$').firstMatch(t);
  if (m != null) {
    final d = int.parse(m[1]!), mo = int.parse(m[2]!);
    var y = m[3] == null ? now.year : int.parse(m[3]!);
    if (m[3] != null && m[3]!.length == 2) y += y < 30 ? 2000 : 1900;
    if (mo < 1 || mo > 12 || d < 1 || d > DateTime.utc(y, mo + 1, 0).day) return null;
    var serial = serialOf(y, mo, d, date1904: date1904);
    var format = m[3] == null ? 'd-mmm' : 'dd/mm/yyyy';
    if (m[4] != null) {
      final time = _time(int.parse(m[4]!), int.parse(m[5]!), m[6] == null ? 0 : int.parse(m[6]!));
      if (time == null) return null;
      serial += time;
      format = 'dd/mm/yyyy hh:mm';
    }
    return (serial, format);
  }
  final tm = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(t);
  if (tm != null) {
    final time = _time(int.parse(tm[1]!), int.parse(tm[2]!), tm[3] == null ? 0 : int.parse(tm[3]!));
    if (time == null) return null;
    return (time, tm[3] == null ? 'hh:mm' : 'hh:mm:ss');
  }
  return null;
}

double? _time(int h, int m, int s) {
  if (h > 23 || m > 59 || s > 59) return null;
  return (h * 3600 + m * 60 + s) / 86400;
}

/// The text a cell is edited from: its formula in French, or its value
/// written in full.
String editText(Map<String, Object?> fields, {NumberLocale locale = NumberLocale.fr, NumberFormat? format, bool date1904 = false}) {
  final f = fields['f'];
  if (f is String && f.isNotEmpty) return '=${locale.french ? formulaToFrench(f) : f}';
  final e = fields['e'];
  if (e is String) return locale.french ? errorText(e) : e;
  final v = fields['v'];
  if (v is bool) return v ? locale.trueText : locale.falseText;
  if (v is num) {
    final n = v.toDouble();
    if (format != null && format.isDate) {
      final time = n - n.floorToDouble();
      final code = n < 1 ? 'hh:mm:ss' : (time == 0 ? 'dd/mm/yyyy' : 'dd/mm/yyyy hh:mm:ss');
      return NumberFormat(code).format(n, locale, date1904: date1904).text;
    }
    if (format != null && format.isPercent) return '${generalText(n * 100, locale)}%';
    return generalText(n, locale);
  }
  return v is String ? v : '';
}
