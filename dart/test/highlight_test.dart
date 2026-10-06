import 'package:bref/src/highlight.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pieces of [code] of kind [kind], line by line, as text.
List<List<String>> _pieces(String language, String code, Token kind) {
  final lines = code.split('\n');
  final runs = highlight(language, code);
  return [
    for (var i = 0; i < lines.length; i++)
      [for (final r in runs[i]) if (r.kind == kind) lines[i].substring(r.start, r.end)],
  ];
}

final none = <String>[];

List<String> _flat(String language, String code, Token kind) => _pieces(language, code, kind).expand((l) => l).toList();

void main() {
  test('knows the languages by the first word of the info string', () {
    expect(languageOf('dart'), 'dart');
    expect(languageOf('Go title="main.go"'), 'go');
    expect(languageOf('{.python}'), 'python');
    expect(languageOf('js,linenos'), 'js');
    expect(languageOf('klingon'), isNull);
    expect(languageOf(''), isNull);
  });

  test('keywords, strings, numbers and comments of the languages of the C family', () {
    const code = 'func main() {\n\tx := 0x1F + 2.5e-3 // fin\n\ts := "a\\"b" + `raw\nsuite`\n}';
    expect(_flat('go', code, Token.keyword), ['func']);
    expect(_flat('go', code, Token.number), ['0x1F', '2.5e-3']);
    expect(_flat('go', code, Token.comment), ['// fin']);
    expect(_pieces('go', code, Token.string), [none, none, ['"a\\"b"', '`raw'], ['suite`'], none]);
    expect(_flat('go', code, Token.name), ['main']);
  });

  test('block comments cut at the end of each line', () {
    expect(_pieces('js', 'a /* un\n deux */ b', Token.comment), [['/* un'], [' deux */']]);
    expect(_flat('js', '/* ouvert\nencore', Token.comment), ['/* ouvert', 'encore']);
  });

  test('a string that is not closed stops at the end of its line', () {
    expect(_pieces('js', 'x = "ouvert\ny = 1', Token.string), [['"ouvert'], none]);
    expect(_flat('js', 'x = "ouvert\ny = 1', Token.number), ['1']);
  });

  test('numbers are not cut out of words', () {
    expect(_flat('js', 'a1 + b2 + 3', Token.number), ['3']);
    expect(_flat('js', 'v.x1(2)', Token.number), ['2']);
  });

  test('Python has docstrings over several lines and hash comments', () {
    const code = 'def f(x):\n    """doc\n    suite"""  # fin\n    return None';
    expect(_flat('py', code, Token.keyword), ['def', 'return', 'None']);
    expect(_pieces('py', code, Token.string), [none, ['"""doc'], ['    suite"""'], none]);
    expect(_flat('py', code, Token.comment), ['# fin']);
  });

  test('a hash is a comment only where a word starts', () {
    expect(_flat('sh', r'echo $# ${#x} # note', Token.comment), ['# note']);
  });

  test('a Rust lifetime is not a character', () {
    const code = "fn f<'a>(x: &'a str) -> char { 'z' }";
    expect(_flat('rust', code, Token.string), ["'z'"]);
    expect(_flat('rust', "let c = '\\n';", Token.string), ["'\\n'"]);
  });

  test('C directives', () {
    expect(_flat('c', '#include <stdio.h>\nint x; // #pas', Token.keyword), ['#include', 'int']);
  });

  test('keys of JSON, YAML and CSS are names', () {
    expect(_flat('json', '{"a": [1, true], "b": "x"}', Token.name), ['"a"', '"b"']);
    expect(_flat('json', '{"a": [1, true], "b": "x"}', Token.string), ['"x"']);
    expect(_flat('yaml', 'nom: Zoé # ici\nok: true', Token.name), ['nom', 'ok']);
    expect(_flat('yaml', 'nom: Zoé # ici\nok: true', Token.comment), ['# ici']);
    expect(_flat('css', '@media x { a { color: red; } }', Token.keyword), ['@media']);
    expect(_flat('css', '@media x { a { color: red; } }', Token.name), ['color']);
  });

  test('SQL keywords do not depend on the case', () {
    expect(_flat('sql', "SELECT a FROM t -- fin\nwhere x = 'o'", Token.keyword), ['SELECT', 'FROM', 'where']);
    expect(_flat('sql', "SELECT a FROM t -- fin\nwhere x = 'o'", Token.comment), ['-- fin']);
  });

  test('tags and attributes of markup', () {
    const code = '<!-- n -->\n<a href="x"\n   class=b>texte l\'ami</a>';
    expect(_flat('html', code, Token.comment), ['<!-- n -->']);
    expect(_flat('html', code, Token.keyword), ['a', 'a']);
    expect(_flat('html', code, Token.name), ['href', 'class']);
    expect(_flat('html', code, Token.string), ['"x"']);
  });

  test('capitalized words and calls are names, not keywords', () {
    expect(_flat('java', 'new Foo(bar(1));', Token.name), ['Foo', 'bar']);
    expect(_flat('java', 'if (x) {}', Token.name), isEmpty);
  });

  test('every line is answered, even an empty or an odd one', () {
    expect(highlight('dart', '').length, 1);
    expect(highlight('dart', 'a\n\nb\n').length, 4);
    expect(highlight('c', '#').length, 1);
    expect(highlight('html', '<').length, 1);
    expect(highlight('rust', "'").length, 1);
  });
}
