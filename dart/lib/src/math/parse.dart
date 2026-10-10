import 'dart:ui' show Color;

import 'symbols.dart';

/// A piece of a formula as it was written.
sealed class Node {
  const Node();
}

/// A character; [plain] is the letter it is, when [rune] shows it in an
/// alphabet a font may lack.
class Sym extends Node {
  const Sym(this.rune, this.cls, [this.plain]);

  final int rune;
  final Cls cls;
  final int? plain;
}

class Group extends Node {
  const Group(this.body);

  final List<Node> body;
}

/// [base] with what is written above and below it; [limits] is where a
/// command asked them to be, over and under or beside.
class Scripts extends Node {
  const Scripts(this.base, this.sup, this.sub, this.primes, this.limits);

  final Node? base;
  final List<Node>? sup, sub;
  final int primes;
  final bool? limits;
}

/// One thing over another, with a [rule] between them or not; [level] is
/// the style a command asked for, as in [Styled].
class Frac extends Node {
  const Frac(this.num, this.den, {this.rule = true, this.level});

  final List<Node> num, den;
  final bool rule;
  final int? level;
}

class Radical extends Node {
  const Radical(this.body, this.index);

  final List<Node> body;
  final List<Node>? index;
}

/// [parts] between delimiters as tall as they are: [left] and [right], 0
/// for none, and [middles] between two parts.
class Delimited extends Node {
  const Delimited(this.left, this.parts, this.middles, this.right);

  final int left, right;
  final List<List<Node>> parts;
  final List<int> middles;
}

/// A delimiter of a size asked for, from 1 to 4.
class Big extends Node {
  const Big(this.rune, this.size, this.cls);

  final int rune, size;
  final Cls cls;
}

/// [body] with the accent [rune] over it, or [under]; it is as wide as the
/// body when it is to [stretch], and takes scripts as [limits] when it is a
/// brace.
class Accent extends Node {
  const Accent(this.rune, this.body, {this.stretch = false, this.under = false, this.limits = false});

  final int rune;
  final List<Node> body;
  final bool stretch, under, limits;
}

/// [body] with a line over or under it.
class Line extends Node {
  const Line(this.body, {required this.over});

  final List<Node> body;
  final bool over;
}

/// [base] with smaller things set right [above] and [below] it.
class Stack extends Node {
  const Stack(this.base, this.above, this.below, this.cls);

  final List<Node> base;
  final List<Node>? above, below;
  final Cls cls;
}

/// The arrow [rune] as long as what is written [above] and [below] it.
class Arrow extends Node {
  const Arrow(this.rune, this.above, this.below);

  final int rune;
  final List<Node> above;
  final List<Node>? below;
}

/// A function named in upright letters.
class OpName extends Node {
  const OpName(this.name, {required this.limits});

  final String name;
  final bool limits;
}

class TextNode extends Node {
  const TextNode(this.text, this.variant);

  final String text;
  final Variant variant;
}

/// Room of [mu] eighteenths of an em.
class Space extends Node {
  const Space(this.mu);

  final double mu;
}

/// [body] in the style of a line of its own (0), of text (1), of a script
/// (2) or of the script of a script (3).
class Styled extends Node {
  const Styled(this.level, this.body);

  final int level;
  final List<Node> body;
}

class Classed extends Node {
  const Classed(this.cls, this.body);

  final Cls cls;
  final List<Node> body;
}

class Colored extends Node {
  const Colored(this.color, this.body);

  final Color color;
  final List<Node> body;
}

/// The room [body] would take, in [width], in [height], or both.
class Phantom extends Node {
  const Phantom(this.body, {this.width = true, this.height = true});

  final List<Node> body;
  final bool width, height;
}

class Boxed extends Node {
  const Boxed(this.body);

  final List<Node> body;
}

/// [body] struck through.
class Not extends Node {
  const Not(this.body);

  final Node body;
}

/// Rows of cells in columns: a matrix, lines aligned, cases.
class Table extends Node {
  const Table(this.rows, {this.aligns = '', this.sep = 1, this.pairs = false, this.display = false, this.jot = 0});

  final List<List<List<Node>>> rows;

  /// `l`, `c` or `r` for each column; those beyond are centered.
  final String aligns;

  /// The room between two columns, in ems.
  final double sep;

  /// Whether columns go by two, the first to the right and the second to
  /// the left, with nothing between them: lines aligned on a relation.
  final bool pairs;

  /// Whether cells are set as lines of their own.
  final bool display;

  /// The room added between two rows, in ems.
  final double jot;
}

/// What was written and cannot be read, shown as it is.
class Bad extends Node {
  const Bad(this.text);

  final String text;
}

/// Reads [tex], the source of a formula. Nothing makes it fail: what it
/// does not know is kept as a [Bad] node.
List<Node> parseMath(String tex) => _Parser(tex).formula();

const _stops = {'}', '&', r'\\', r'\cr', r'\right', r'\middle', r'\end'};

const _styles = {r'\displaystyle': 0, r'\textstyle': 1, r'\scriptstyle': 2, r'\scriptscriptstyle': 3};

const _declared = {
  r'\rm': Variant.roman, r'\bf': Variant.bold, r'\it': Variant.italic, r'\cal': Variant.script, r'\sf': Variant.sans,
  r'\tt': Variant.mono, r'\frak': Variant.fraktur, r'\Bbb': Variant.doubleStruck,
};

const _alphabets = {
  'mathrm': Variant.roman, 'mathup': Variant.roman, 'mathnormal': Variant.normal, 'mathbf': Variant.bold,
  'mathit': Variant.italic, 'boldsymbol': Variant.boldItalic, 'bm': Variant.boldItalic, 'mathbfit': Variant.boldItalic,
  'mathcal': Variant.script, 'mathscr': Variant.script, 'mathfrak': Variant.fraktur, 'mathbb': Variant.doubleStruck,
  'mathsf': Variant.sans, 'mathtt': Variant.mono,
};

const _texts = {
  'text': Variant.roman, 'textrm': Variant.roman, 'textnormal': Variant.roman, 'textup': Variant.roman,
  'mbox': Variant.roman, 'hbox': Variant.roman, 'textbf': Variant.bold, 'textit': Variant.italic,
  'textsf': Variant.sans, 'texttt': Variant.mono,
};

const _spaces = {
  ',': 3.0, 'thinspace': 3.0, ':': 4.0, '>': 4.0, 'medspace': 4.0, ';': 5.0, 'thickspace': 5.0, '!': -3.0,
  'negthinspace': -3.0, 'negmedspace': -4.0, 'negthickspace': -5.0, ' ': 6.0, 'space': 6.0, 'nobreakspace': 6.0,
  'enspace': 9.0, 'quad': 18.0, 'qquad': 36.0,
};

const _classes = {
  'mathord': Cls.ord, 'mathop': Cls.op, 'mathbin': Cls.bin, 'mathrel': Cls.rel, 'mathopen': Cls.open,
  'mathclose': Cls.close, 'mathpunct': Cls.punct, 'mathinner': Cls.inner,
};

const _bigs = {'big': 1, 'Big': 2, 'bigg': 3, 'Bigg': 4};

const _matrices = {
  'matrix': (0, 0), 'pmatrix': (0x28, 0x29), 'bmatrix': (0x5B, 0x5D), 'Bmatrix': (0x7B, 0x7D),
  'vmatrix': (0x7C, 0x7C), 'Vmatrix': (0x2016, 0x2016),
};

const _aligned = {'aligned', 'align', 'alignat', 'alignedat', 'split', 'eqnarray', 'flalign'};

const _gathered = {'gathered', 'gather', 'equation', 'multline', 'displaymath', 'math'};

const _colors = {
  'black': 0xFF000000, 'white': 0xFFFFFFFF, 'gray': 0xFF808080, 'grey': 0xFF808080, 'red': 0xFFE03131,
  'orange': 0xFFE8590C, 'yellow': 0xFFF08C00, 'green': 0xFF2F9E44, 'teal': 0xFF0C8599, 'cyan': 0xFF1098AD,
  'blue': 0xFF1C7ED6, 'purple': 0xFF7048E8, 'violet': 0xFF7048E8, 'magenta': 0xFFD6336C, 'pink': 0xFFD6336C,
  'brown': 0xFF8D6E63,
};

/// The lengths of TeX, in ems.
const _units = {'em': 1.0, 'mu': 1 / 18, 'ex': 0.43, 'pt': 0.1, 'px': 0.075, 'cm': 2.85, 'mm': 0.285, 'in': 7.23};

final _length = RegExp(r'^\s*(-?[0-9]*\.?[0-9]+)\s*([a-z]{2})\s*$');

class _Parser {
  _Parser(this.src);

  final String src;
  var at = 0;
  var variant = Variant.normal;

  /// How many lists are open one in the other, and the most there may be.
  var _depth = 0;
  static const _deepest = 100;

  /// The next token, a command with its backslash or a character, or null at
  /// the end.
  String? _next() {
    while (at < src.length) {
      final c = src.codeUnitAt(at);
      if (c == 0x25) {
        while (at < src.length && src.codeUnitAt(at) != 0x0A) {
          at++;
        }
      } else if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        at++;
      } else {
        break;
      }
    }
    if (at >= src.length) return null;
    final start = at;
    final c = src.codeUnitAt(at++);
    if (c == 0x5C && at < src.length) {
      if (_letter(src.codeUnitAt(at))) {
        while (at < src.length && _letter(src.codeUnitAt(at))) {
          at++;
        }
      } else {
        at++;
      }
    } else if (c >= 0xD800 && c < 0xDC00 && at < src.length) {
      at++;
    }
    return src.substring(start, at);
  }

  static bool _letter(int c) => c >= 0x41 && c <= 0x5A || c >= 0x61 && c <= 0x7A;

  String? _peek() {
    final saved = at;
    final t = _next();
    at = saved;
    return t;
  }

  bool _take(String token) {
    if (_peek() != token) return false;
    _next();
    return true;
  }

  List<Node> formula() {
    final rows = _rows(null);
    if (rows.length == 1 && rows.single.length == 1) return rows.single.single;
    return [Table(rows, pairs: true, display: true, jot: 0.3)];
  }

  /// Rows of cells, up to the token [end], left unread, or to the end.
  List<List<List<Node>>> _rows(String? end) {
    final rows = [
      [<Node>[]],
    ];
    while (true) {
      rows.last.last.addAll(_list());
      final t = _peek();
      if (t == null || t == end) break;
      _next();
      if (t == '&') {
        rows.last.add([]);
      } else if (t == r'\\' || t == r'\cr') {
        if (at < src.length && src.codeUnitAt(at) == 0x5B) _bracketed();
        rows.add([[]]);
      } else {
        rows.last.last.add(Bad(t));
      }
    }
    if (rows.length > 1 && rows.last.length == 1 && rows.last.single.isEmpty) rows.removeLast();
    return rows;
  }

  /// What is written up to where a list ends, which is left unread: a
  /// closing brace, the end of a cell, of a row, of what delimiters hold.
  List<Node> _list({bool bracket = false}) {
    if (_depth >= _deepest) {
      at = src.length;
      return const [Bad('…')];
    }
    _depth++;
    final nodes = _listed(bracket);
    _depth--;
    return nodes;
  }

  List<Node> _listed(bool bracket) {
    var nodes = <Node>[];
    List<Node>? over;
    var infix = '';
    final saved = variant;
    while (true) {
      final t = _peek();
      if (t == null || _stops.contains(t) || bracket && t == ']') break;
      if (t == '^' || t == '_' || t == "'") {
        nodes.add(_scripted(null));
        continue;
      }
      _next();
      if (t == r'\over' || t == r'\atop' || t == r'\choose') {
        over = nodes;
        infix = t;
        nodes = [];
        continue;
      }
      final declared = _declared[t];
      if (declared != null) {
        variant = declared;
        continue;
      }
      final level = _styles[t];
      if (level != null) {
        nodes.add(Styled(level, _list(bracket: bracket)));
        break;
      }
      if (t == r'\color') {
        final color = _color(_raw());
        final rest = _list(bracket: bracket);
        nodes.add(color == null ? Group(rest) : Colored(color, rest));
        break;
      }
      nodes.add(_scripted(_atom(t)));
    }
    variant = saved;
    if (over == null) return nodes;
    final stack = Frac(over, nodes, rule: infix == r'\over');
    return [if (infix == r'\choose') Delimited(0x28, [[stack]], const [], 0x29) else stack];
  }

  /// [base] with the scripts and primes that follow it.
  Node _scripted(Node? base) {
    List<Node>? sup, sub;
    var primes = 0;
    bool? limits;
    while (true) {
      final t = _peek();
      if (t == '^') {
        _next();
        sup = [...?sup, ..._arg()];
      } else if (t == '_') {
        _next();
        sub = [...?sub, ..._arg()];
      } else if (t == "'") {
        _next();
        primes++;
      } else if (t == r'\limits' || t == r'\nolimits') {
        _next();
        limits = t == r'\limits';
      } else {
        break;
      }
    }
    if (base != null && sup == null && sub == null && primes == 0 && limits == null) return base;
    return Scripts(base, sup, sub, primes, limits);
  }

  /// What a command takes: a group, or the one thing that follows.
  List<Node> _arg() {
    final t = _peek();
    if (t == null || _stops.contains(t)) return const [];
    _next();
    return t == '{' ? _group() : [_atom(t)];
  }

  /// What a group holds, its opening brace read.
  List<Node> _group() {
    final nodes = <Node>[];
    while (true) {
      nodes.addAll(_list());
      final t = _next();
      if (t == null || t == '}') return nodes;
      nodes.add(Bad(t));
    }
  }

  /// What is written between brackets, the opening one being next, or null.
  List<Node>? _optional() {
    if (!_take('[')) return null;
    final nodes = _list(bracket: true);
    _take(']');
    return nodes;
  }

  void _bracketed() {
    final end = src.indexOf(']', at);
    at = end < 0 ? src.length : end + 1;
  }

  /// The text of an argument, as it is written: what braces hold, or one
  /// token.
  String _raw() {
    final saved = at;
    final t = _next();
    if (t == null || _stops.contains(t)) {
      at = saved;
      return '';
    }
    if (t != '{') return t;
    final start = at;
    var depth = 1;
    while (at < src.length) {
      final c = src.codeUnitAt(at);
      if (c == 0x5C) {
        at++;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D && --depth == 0) {
        break;
      }
      at++;
    }
    final end = at < src.length ? at : src.length;
    at = end < src.length ? end + 1 : end;
    return src.substring(start, end);
  }

  /// Text as it reads: its escapes undone, its braces gone, its spaces one.
  static String _plain(String raw) {
    final out = StringBuffer();
    for (var k = 0; k < raw.length; k++) {
      final c = raw[k];
      if (c == r'\' && k + 1 < raw.length) {
        final next = raw[++k];
        if (next != '!') out.write(r'\,;: '.contains(next) ? ' ' : next);
      } else if (c == '~') {
        out.write(' ');
      } else if (c != '{' && c != '}' && c != r'$') {
        out.write(c);
      }
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Color? _color(String name) {
    final known = _colors[name.trim().toLowerCase()];
    if (known != null) return Color(known);
    var hex = name.trim();
    if (!hex.startsWith('#')) return null;
    hex = hex.substring(1);
    if (hex.length == 3) hex = [for (final c in hex.split('')) '$c$c'].join();
    final value = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
    return value == null ? null : Color(0xFF000000 | value);
  }

  /// A length of TeX in eighteenths of an em, 0 when it is not one.
  static double _mu(String length) {
    final m = _length.firstMatch(length);
    final unit = m == null ? null : _units[m[2]];
    return unit == null ? 0 : double.parse(m![1]!) * unit * 18;
  }

  /// The character of a delimiter, 0 for none.
  int _delimiter() {
    final t = _next();
    if (t == null || t == '.') return 0;
    if (t == '<') return 0x27E8;
    if (t == '>') return 0x27E9;
    if (!t.startsWith(r'\')) return t.runes.first;
    return symbols[t.substring(1)]?.rune ?? 0;
  }

  Node _char(int rune) {
    if (rune == 0x2D) rune = 0x2212;
    if (rune == 0x2A) rune = 0x2217;
    if (rune == 0x7E) return const Space(6);
    return Sym(styled(rune, variant), classes[rune] ?? Cls.ord, rune);
  }

  List<Node> _in(Variant v, List<Node> Function() read) {
    final saved = variant;
    variant = v;
    final nodes = read();
    variant = saved;
    return nodes;
  }

  /// What the token [t], already read, stands for.
  Node _atom(String t) {
    if (t == '{') return Group(_group());
    if (!t.startsWith(r'\') || t.length == 1) return _char(t.runes.first);
    var name = t.substring(1);

    final symbol = symbols[name];
    if (symbol != null) return Sym(styled(symbol.rune, variant), symbol.cls, symbol.rune);
    final space = _spaces[name];
    if (space != null) return Space(space);
    final alphabet = _alphabets[name];
    if (alphabet != null) return Group(_in(alphabet, _arg));
    final text = _texts[name];
    if (text != null) return TextNode(_plain(_raw()), text);
    if (functions.contains(name)) return OpName(name, limits: false);
    final limited = limitFunctions[name];
    if (limited != null) return OpName(limited, limits: true);
    final accent = accents[name];
    if (accent != null) return Accent(accent, _arg());
    final wide = wideAccents[name];
    if (wide != null) return Accent(wide, _arg(), stretch: true, limits: name == 'overbrace');
    final under = underAccents[name];
    if (under != null) return Accent(under, _arg(), stretch: true, under: true, limits: name == 'underbrace');
    final arrow = stretchArrows[name];
    if (arrow != null) {
      final below = _optional();
      return Arrow(arrow, _arg(), below);
    }
    final cls = _classes[name];
    if (cls != null) return Classed(cls, _arg());

    var big = Cls.ord;
    final last = name[name.length - 1];
    if ('lrm'.contains(last) && _bigs.containsKey(name.substring(0, name.length - 1))) {
      big = last == 'l' ? Cls.open : (last == 'r' ? Cls.close : Cls.rel);
      name = name.substring(0, name.length - 1);
    }
    final size = _bigs[name];
    if (size != null) return Big(_delimiter(), size, big);

    switch (name) {
      case 'frac' || 'dfrac' || 'tfrac' || 'cfrac':
        final num = _arg();
        return Frac(num, _arg(), level: name == 'dfrac' || name == 'cfrac' ? 0 : (name == 'tfrac' ? 1 : null));
      case 'binom' || 'dbinom' || 'tbinom':
        final num = _arg();
        final stack = Frac(num, _arg(), rule: false, level: name == 'dbinom' ? 0 : (name == 'tbinom' ? 1 : null));
        return Delimited(0x28, [[stack]], const [], 0x29);
      case 'sqrt':
        final index = _optional();
        return Radical(_arg(), index);
      case 'left':
        return _delimited();
      case 'overline' || 'underline':
        return Line(_arg(), over: name == 'overline');
      case 'overset' || 'stackrel':
        final above = _arg();
        return Stack(_arg(), above, null, name == 'stackrel' ? Cls.rel : Cls.ord);
      case 'underset':
        final below = _arg();
        return Stack(_arg(), null, below, Cls.ord);
      case 'operatorname':
        final limits = at < src.length && src[at] == '*';
        if (limits) at++;
        return OpName(_plain(_raw()), limits: limits);
      case 'hspace' || 'kern' || 'mkern' || 'mskip' || 'hskip':
        return Space(_mu(_raw()));
      case 'textcolor':
        final color = _color(_raw());
        final body = _arg();
        return color == null ? Group(body) : Colored(color, body);
      case 'phantom' || 'hphantom' || 'vphantom':
        return Phantom(_arg(), width: name != 'vphantom', height: name != 'hphantom');
      case 'boxed' || 'fbox':
        return Boxed(_arg());
      case 'not':
        final next = _peek();
        if (next == null || _stops.contains(next)) return const Bad(r'\not');
        _next();
        final body = _atom(next);
        final whole = body is Sym ? negated[body.rune] : null;
        return whole == null ? Not(body) : Sym(whole, Cls.rel);
      case 'pmod':
        return Group([const Space(8), const Sym(0x28, Cls.open), const TextNode('mod', Variant.roman), const Space(6), ..._arg(), const Sym(0x29, Cls.close)]);
      case 'bmod':
        return const Classed(Cls.bin, [TextNode('mod', Variant.roman)]);
      case 'mod':
        return const Group([Space(12), TextNode('mod', Variant.roman), Space(6)]);
      case 'substack':
        _take('{');
        final rows = _rows('}');
        _take('}');
        return Table(rows, sep: 0);
      case 'label' || 'tag':
        _raw();
        return const Group([]);
      case 'nonumber' || 'notag' || 'hline' || 'displaylimits' || 'relax' || 'allowbreak' || 'nobreak' || '/':
        return const Group([]);
      case 'begin':
        return _environment();
    }
    return Bad(t);
  }

  Node _delimited() {
    final left = _delimiter();
    final parts = <List<Node>>[], middles = <int>[];
    while (true) {
      parts.add(_list());
      if (_take(r'\middle')) {
        middles.add(_delimiter());
      } else {
        return Delimited(left, parts, middles, _take(r'\right') ? _delimiter() : 0);
      }
    }
  }

  Node _environment() {
    var name = _raw().trim();
    if (name.endsWith('*')) name = name.substring(0, name.length - 1);
    final spec = name == 'array' || name == 'subarray' ? _raw().replaceAll(RegExp('[^lcr]'), '') : '';
    if (name == 'alignat' || name == 'alignedat') _raw();
    final rows = _rows(r'\end');
    if (_take(r'\end')) _raw();
    final delimiters = _matrices[name];
    if (delimiters != null) {
      final table = Table(rows);
      return delimiters.$1 == 0 ? table : Delimited(delimiters.$1, [[table]], const [], delimiters.$2);
    }
    if (_aligned.contains(name)) return Table(rows, pairs: true, display: true, jot: 0.3);
    if (_gathered.contains(name)) return Table(rows, display: true, jot: 0.3);
    return switch (name) {
      'array' || 'subarray' => Table(rows, aligns: spec),
      'smallmatrix' => Styled(2, [Table(rows, sep: 0.5)]),
      'cases' || 'dcases' => Delimited(0x7B, [[Table(rows, aligns: 'll', display: name == 'dcases', jot: 0.2)]], const [], 0),
      'rcases' => Delimited(0, [[Table(rows, aligns: 'll', jot: 0.2)]], const [], 0x7D),
      _ => Group([Bad('\\begin{$name}'), Table(rows)]),
    };
  }
}
