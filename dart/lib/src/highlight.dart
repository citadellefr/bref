import 'dart:math' as math;

/// What a piece of code is, for coloring it.
enum Token { keyword, string, comment, number, name }

/// A piece of a line of code, in its columns.
typedef Run = ({int start, int end, Token kind});

/// How a language is read: what its comments, strings and words look like.
class _Language {
  _Language(
    String words, {
    this.line = const [],
    this.block,
    this.quotes = '"\'',
    this.multi = const [],
    this.types = false,
    this.calls = false,
    this.keys = false,
    this.markup = false,
    this.directives = false,
    this.chars = false,
    this.at,
    this.ignoreCase = false,
  }) : words = words.split(' ').toSet();

  final Set<String> words;
  final List<String> line;
  final (String, String)? block;

  /// The characters that open a string ending on its line.
  final String quotes;

  /// The delimiters of strings that go on over lines.
  final List<String> multi;

  /// Capitalized words, and words followed by a parenthesis, are names.
  final bool types, calls;

  /// A word or a string followed by a colon is a name.
  final bool keys;

  /// Tags between angle brackets.
  final bool markup;

  /// A `#` leading a line starts a keyword.
  final bool directives;

  /// A quote may open a character (`'a'`, `'\n'`) rather than a string.
  final bool chars;

  /// What a word starting with `@` is, when it is anything.
  final Token? at;

  final bool ignoreCase;
}

const _cWords = 'auto break case char const continue default do double else enum extern float for goto if inline int long '
    'register return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false NULL '
    'nullptr class namespace new delete template typename public private protected virtual this using try catch throw '
    'operator constexpr override final';

_Language _cLike(String words, {List<String> multi = const [], bool directives = false}) =>
    _Language(words, line: const ['//'], block: ('/*', '*/'), multi: multi, types: true, calls: true, directives: directives);

final _languages = () {
  final js = _cLike(
    'async await break case catch class const continue debugger default delete do else enum export extends false finally for '
    'from function get if implements import in instanceof interface let new null of private protected public readonly return '
    'set static super switch this throw true try type typeof undefined var void while with yield as abstract declare '
    'namespace module keyof satisfies',
    multi: const ['`'],
  );
  final python = _Language(
    'False None True and as assert async await break class continue def del elif else except finally for from global if '
    'import in is lambda nonlocal not or pass raise return try while with yield match case',
    line: const ['#'],
    multi: const ['"""', "'''"],
    types: true,
    calls: true,
  );
  final go = _cLike(
    'break case chan const continue default defer else fallthrough for func go goto if import interface map package range '
    'return select struct switch type var true false nil iota string bool byte rune error any int int8 int16 int32 int64 '
    'uint uint8 uint16 uint32 uint64 uintptr float32 float64 complex64 complex128',
    multi: const ['`'],
  );
  final rust = _Language(
    'as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub '
    'ref return self Self static struct super trait true type unsafe use where while i8 i16 i32 i64 i128 isize u8 u16 u32 '
    'u64 u128 usize f32 f64 bool char str',
    line: const ['//'],
    block: ('/*', '*/'),
    quotes: '"',
    types: true,
    calls: true,
    chars: true,
  );
  final c = _cLike(_cWords, directives: true);
  final java = _cLike(
    'abstract assert boolean break byte case catch char class const continue default do double else enum extends final '
    'finally float for if implements import instanceof int interface long new null package private protected public return '
    'short static super switch synchronized this throw throws transient true false try var void volatile while record',
  );
  final csharp = _cLike(
    'abstract as async await base bool break byte case catch char checked class const continue decimal default delegate do '
    'double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal '
    'is lock long namespace new null object operator out override params private protected public readonly ref return sbyte '
    'sealed short sizeof static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using var '
    'virtual void volatile while get set record',
  );
  final kotlin = _cLike(
    'as break class continue do else false for fun if in interface is null object package return super this throw true try '
    'typealias val var when while by catch constructor finally init import override open data sealed companion private '
    'public protected internal suspend',
    multi: const ['"""'],
  );
  final swift = _cLike(
    'as break case catch class continue default defer do else enum extension fallthrough false fileprivate for func guard if '
    'import in init inout internal is let nil open operator private protocol public repeat return self Self static struct '
    'subscript super switch throw throws true try typealias var where while async await',
    multi: const ['"""'],
  );
  final dart = _cLike(
    'abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum '
    'export extends extension external factory false final finally for Function get hide if implements import in interface '
    'is late library mixin new null on operator part required rethrow return set show static super switch sync this throw '
    'true try typedef var void while with yield',
    multi: const ["'''", '"""'],
  );
  final zig = _Language(
    'align allowzero and anyframe anytype asm async await break callconv catch comptime const continue defer else enum '
    'errdefer error export extern fn for if inline linksection noalias nosuspend noinline opaque or orelse packed pub resume '
    'return struct suspend switch test threadlocal try union unreachable usingnamespace var volatile while true false null '
    'undefined',
    line: const ['//'],
    types: true,
    calls: true,
    at: Token.name,
  );
  final ruby = _Language(
    'def end class module if elsif else unless while until for in do begin rescue ensure return yield self nil true false '
    'and or not then case when require include',
    line: const ['#'],
    types: true,
    calls: true,
  );
  final shell = _Language(
    'if then else elif fi for while until do done case esac in function select time return exit break continue export local '
    'readonly declare unset echo cd',
    line: const ['#'],
    calls: false,
  );
  final sql = _Language(
    'select from where and or not insert into values update set delete create table alter drop index view join left right '
    'inner outer full cross on as group by order having limit offset union all distinct null is in between like exists case '
    'when then else end primary key foreign references default unique check constraint asc desc count sum avg min max with '
    'returning',
    line: const ['--'],
    block: ('/*', '*/'),
    quotes: "'",
    ignoreCase: true,
  );
  final json = _Language('true false null', keys: true, quotes: '"');
  final yaml = _Language('true false null', line: const ['#'], keys: true);
  final css = _Language('', block: ('/*', '*/'), keys: true, at: Token.keyword);
  final markup = _Language('', block: ('<!--', '-->'), markup: true);
  return <String, _Language>{
    for (final k in ['js', 'javascript', 'jsx', 'mjs', 'ts', 'typescript', 'tsx']) k: js,
    for (final k in ['py', 'python']) k: python,
    for (final k in ['go', 'golang']) k: go,
    for (final k in ['rust', 'rs']) k: rust,
    for (final k in ['c', 'h', 'cpp', 'c++', 'cc', 'hpp']) k: c,
    'java': java,
    for (final k in ['cs', 'csharp']) k: csharp,
    for (final k in ['kotlin', 'kt']) k: kotlin,
    'swift': swift,
    'dart': dart,
    'zig': zig,
    for (final k in ['ruby', 'rb']) k: ruby,
    for (final k in ['sh', 'bash', 'shell', 'zsh']) k: shell,
    'sql': sql,
    for (final k in ['json', 'jsonc']) k: json,
    for (final k in ['yaml', 'yml']) k: yaml,
    'css': css,
    for (final k in ['html', 'xml', 'svg']) k: markup,
  };
}();

/// The language an info string names, if it is one that is highlighted.
String? languageOf(String info) {
  final word = info.trim().split(RegExp(r'[\s{},]+')).firstWhere((w) => w.isNotEmpty, orElse: () => '');
  final name = word.startsWith('.') ? word.substring(1) : word;
  final lower = name.toLowerCase();
  return _languages.containsKey(lower) ? lower : null;
}

bool _isDigit(int c) => c >= 48 && c <= 57;

bool _isSpace(int c) => c == 32 || c == 9 || c == 10 || c == 13;

bool _isStart(int c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127;

bool _isWord(int c) => _isStart(c) || _isDigit(c);

/// The pieces of each line of [code] in [language], a name [languageOf]
/// knows. Strings and comments that go on over lines are cut at their ends.
List<List<Run>> highlight(String language, String code) {
  final l = _languages[language]!;
  final starts = [0];
  for (var i = code.indexOf('\n'); i >= 0; i = code.indexOf('\n', i + 1)) {
    starts.add(i + 1);
  }
  final out = [for (var i = 0; i < starts.length; i++) <Run>[]];
  final n = code.length;
  var row = 0;

  void emit(int from, int to, Token kind) {
    while (row + 1 < starts.length && starts[row + 1] <= from) {
      row++;
    }
    for (var r = row; from < to && r < starts.length; r++) {
      final lineEnd = r + 1 < starts.length ? starts[r + 1] - 1 : n;
      final end = math.min(to, lineEnd);
      if (end > from) out[r].add((start: from - starts[r], end: end - starts[r], kind: kind));
      from = lineEnd + 1;
    }
  }

  int lineEnd(int i) {
    final e = code.indexOf('\n', i);
    return e < 0 ? n : e;
  }

  int after(int i) {
    while (i < n && (code.codeUnitAt(i) == 32 || code.codeUnitAt(i) == 9)) {
      i++;
    }
    return i;
  }

  /// Where the string opened at [i] with [close] ends, on its line unless
  /// [over] says it goes on.
  int stringEnd(int i, String close, bool over) {
    var k = i + close.length;
    final stop = over ? n : lineEnd(i);
    while (k < stop) {
      if (code.codeUnitAt(k) == 92) {
        k += 2;
      } else if (code.startsWith(close, k)) {
        return k + close.length;
      } else {
        k++;
      }
    }
    return math.min(k, stop);
  }

  var inTag = false;
  var i = 0;
  scan:
  while (i < n) {
    final c = code.codeUnitAt(i);
    final block = l.block;
    if (block != null && code.startsWith(block.$1, i)) {
      final e = code.indexOf(block.$2, i + block.$1.length);
      final end = e < 0 ? n : e + block.$2.length;
      emit(i, end, Token.comment);
      i = end;
      continue;
    }
    if (l.markup && !inTag) {
      if (c == 60) {
        var k = i + 1;
        if (k < n && (code.codeUnitAt(k) == 47 || code.codeUnitAt(k) == 33)) k++;
        if (k < n && _isStart(code.codeUnitAt(k))) {
          final from = k;
          while (k < n && (_isWord(code.codeUnitAt(k)) || code.codeUnitAt(k) == 45 || code.codeUnitAt(k) == 58)) {
            k++;
          }
          emit(from, k, Token.keyword);
          inTag = true;
          i = k;
          continue;
        }
      }
      final next = code.indexOf('<', i + 1);
      i = next < 0 ? n : next;
      continue;
    }
    if (inTag && c == 62) {
      inTag = false;
      i++;
      continue;
    }
    for (final m in l.line) {
      if (code.startsWith(m, i) && (m != '#' || i == 0 || _isSpace(code.codeUnitAt(i - 1)))) {
        final end = lineEnd(i);
        emit(i, end, Token.comment);
        i = end;
        continue scan;
      }
    }
    for (final m in l.multi) {
      if (code.startsWith(m, i)) {
        final end = stringEnd(i, m, true);
        emit(i, end, Token.string);
        i = end;
        continue scan;
      }
    }
    if (l.quotes.contains(String.fromCharCode(c))) {
      final end = stringEnd(i, String.fromCharCode(c), false);
      emit(i, end, l.keys && _colon(code, after(end), n) ? Token.name : Token.string);
      i = end;
      continue;
    }
    if (l.chars && c == 39) {
      final end = _character(code, i);
      if (end != null) {
        emit(i, end, Token.string);
        i = end;
        continue;
      }
    }
    if (l.directives && c == 35 && (i == 0 || code.substring(code.lastIndexOf('\n', i - 1) + 1, i).trim().isEmpty)) {
      var k = i + 1;
      while (k < n && _isWord(code.codeUnitAt(k))) {
        k++;
      }
      emit(i, k, Token.keyword);
      i = k;
      continue;
    }
    if (_isDigit(c) && (i == 0 || !_isWord(code.codeUnitAt(i - 1)))) {
      var k = i + 1;
      final hex = code.startsWith('0x', i) || code.startsWith('0X', i);
      while (k < n) {
        final d = code.codeUnitAt(k);
        if (_isWord(d) && d != 36 || d == 46 && k + 1 < n && _isDigit(code.codeUnitAt(k + 1))) {
          k++;
        } else if ((d == 43 || d == 45) && !hex && (code.codeUnitAt(k - 1) | 32) == 101) {
          k++;
        } else {
          break;
        }
      }
      emit(i, k, Token.number);
      i = k;
      continue;
    }
    final at = l.at != null && c == 64 && i + 1 < n && _isStart(code.codeUnitAt(i + 1));
    if (_isStart(c) || at) {
      var k = i + 1;
      while (k < n && (_isWord(code.codeUnitAt(k)) || inTag && (code.codeUnitAt(k) == 45 || code.codeUnitAt(k) == 58))) {
        k++;
      }
      final word = code.substring(i, k);
      if (inTag) {
        var b = i - 1;
        while (b >= 0 && _isSpace(code.codeUnitAt(b))) {
          b--;
        }
        if (b < 0 || code.codeUnitAt(b) != 61) emit(i, k, Token.name);
      } else if (at) {
        emit(i, k, l.at!);
      } else if (l.words.contains(l.ignoreCase ? word.toLowerCase() : word)) {
        emit(i, k, Token.keyword);
      } else if (l.keys && _colon(code, after(k), n) ||
          l.types && word.length > 1 && c >= 65 && c <= 90 ||
          l.calls && after(k) < n && code.codeUnitAt(after(k)) == 40) {
        emit(i, k, Token.name);
      }
      i = k;
      continue;
    }
    i++;
  }
  return out;
}

bool _colon(String code, int i, int n) => i < n && code.codeUnitAt(i) == 58 && !(i + 1 < n && code.codeUnitAt(i + 1) == 58);

/// Where the character literal opened by the quote at [i] ends, or null when
/// it is not one (a lifetime, in Rust).
int? _character(String code, int i) {
  final n = code.length;
  if (i + 2 < n && code.codeUnitAt(i + 1) == 92) {
    final e = code.indexOf("'", i + 3);
    return e >= 0 && e - i <= 12 && !code.substring(i, e).contains('\n') ? e + 1 : null;
  }
  if (i + 2 < n && code.codeUnitAt(i + 2) == 39 && code.codeUnitAt(i + 1) != 10) return i + 3;
  return null;
}
