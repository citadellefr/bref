import 'package:bref/src/highlight.dart';
import 'package:bref/src/note_syntax.dart';
import 'package:bref/src/note_text.dart';
import 'package:bref/src/syntax.dart';
import 'package:flutter_test/flutter_test.dart';

LineSyntax _line(String note, [int i = 0]) => NoteSyntax(NoteText('$note\n')).line(i);

/// The pieces of line [i] of [note] marked [mark], as text.
List<String> _pieces(String note, int mark, [int i = 0]) {
  final line = note.split('\n')[i];
  final s = _line(note, i);
  final out = <String>[];
  var from = 0;
  for (var k = 0; k < s.ends.length; k++) {
    if (s.marks[k] & mark != 0) {
      if (out.isNotEmpty && from > 0 && s.marks[k - 1] & mark != 0) {
        out.last += line.substring(from, s.ends[k]);
      } else {
        out.add(line.substring(from, s.ends[k]));
      }
    }
    from = s.ends[k];
  }
  return out;
}

/// What the preview shows of line [i] of [note]: its text without what it
/// hides, other swaps in brackets.
/// Line [i] of [note] as the preview shows it, the host having said
/// nothing of its pictures and links.
String _preview(String note, [int i = 0]) {
  final line = note.split('\n')[i];
  final out = StringBuffer();
  var col = 0;
  for (final s in _line(note, i).swaps) {
    if (s.start < col || s.kind == SwapKind.picture || s.kind == SwapKind.label) continue;
    out.write(line.substring(col, s.start));
    switch (s.kind) {
      case SwapKind.hide:
        break;
      case SwapKind.text:
        out.write(s.text);
      default:
        out.write('[${s.kind.name}${s.text.isEmpty ? '' : ' ${s.text}'}]');
    }
    col = s.end;
  }
  out.write(line.substring(col));
  return out.toString();
}

void main() {
  test('headings, quotes, lists and rules', () {
    expect(_line('## Titre ##').heading, 2);
    expect(_pieces('## Titre ##', Mark.markup), ['## ', ' ##']);
    expect(_line('#hashtag').heading, 0);
    expect(_pieces('> > cité', Mark.markup), ['> > ']);
    expect(_pieces('> > cité', Mark.quote), ['> > cité']);
    expect(_pieces('  - [x] fait', Mark.listMarker), ['-']);
    expect(_pieces('  - [x] fait', Mark.task), ['[x]']);
    expect(_pieces('12) douze', Mark.listMarker), ['12)']);
    expect(_pieces('* * *', Mark.rule), ['* * *']);
    expect(_pieces('| a | b |\n|---|:-:|', Mark.table), ['|', '|', '|']);
    expect(_pieces('| a | b |\n|---|:-:|', Mark.table, 1), ['|---|:-:|']);
    expect(_line('Titre\n===').heading, 1);
    expect(_line('Titre\n===', 1).heading, 1);
  });

  test('emphasis pairs as CommonMark pairs it, over several lines', () {
    expect(_pieces('a **gras** b', Mark.strong), ['gras']);
    expect(_pieces('a *it* b', Mark.emphasis), ['it']);
    expect(_pieces('***les deux***', Mark.strong), ['les deux']);
    expect(_pieces('***les deux***', Mark.emphasis), ['**les deux**']);
    expect(_pieces('snake_case_name', Mark.emphasis), isEmpty);
    expect(_pieces('_mot_ ici', Mark.emphasis), ['mot']);
    expect(_pieces('2 * 3 * 4', Mark.emphasis), isEmpty);
    expect(_pieces('~~barré~~ et ==surligné==', Mark.strike), ['barré']);
    expect(_pieces('~~barré~~ et ==surligné==', Mark.highlight), ['surligné']);
    expect(_pieces(r'\*pas\* *oui*', Mark.emphasis), ['oui']);
    expect(_pieces('un *début\net une fin*', Mark.emphasis, 1), ['et une fin']);
  });

  test('code spans hide everything inside them', () {
    expect(_pieces('a `**x**` b', Mark.code), ['`**x**`']);
    expect(_pieces('a `**x**` b', Mark.strong), isEmpty);
    expect(_pieces('``a ` b``', Mark.code), ['``a ` b``']);
    expect(_pieces('`ouvert', Mark.code), isEmpty);
  });

  test('links, images, wiki links and addresses', () {
    expect(_pieces('[un **lien**](https://x.fr) fin', Mark.link), ['un **lien**']);
    expect(_pieces('[un **lien**](https://x.fr) fin', Mark.strong), ['lien']);
    expect(_pieces('[un **lien**](https://x.fr) fin', Mark.url), ['https://x.fr']);
    expect(_pieces('![alt](img.png)', Mark.image), ['alt']);
    expect(_pieces('voir [[Autre note]]', Mark.link), ['Autre note']);
    expect(_pieces('[@Alice](user:42)', Mark.url), ['user:42']);
    expect(_pieces('va sur https://citadelle.fr/a_b_c.', Mark.url), ['https://citadelle.fr/a_b_c']);
    expect(_pieces('va sur https://citadelle.fr/a_b_c.', Mark.emphasis), isEmpty);
    expect(_pieces('<https://x.fr> et <b>gras</b>', Mark.url), ['https://x.fr']);
    expect(_pieces('<https://x.fr> et <b>gras</b>', Mark.html), ['<b>', '</b>']);
    expect(_pieces('[a][r]\n\n[r]: /x', Mark.link), ['a']);
    expect(_pieces('[a][r]', Mark.link), isEmpty);
  });

  test('a footnote is a marker in the color of a list and its references, those of a link', () {
    const note = 'Vu[^1] mais pas[^2].\n\n[^1]: La note\n    suite *ici*\n\nfin';
    expect(_pieces(note, Mark.link), ['[^1]']);
    expect(_pieces(note, Mark.listMarker, 2), ['[^1]:']);
    expect(_pieces(note, Mark.emphasis, 3), ['ici']);
    expect(_preview(note, 2), '[^1]: La note');
    expect(_pieces('[^a]: x', Mark.listMarker), ['[^a]:']);
    expect(_pieces('Vu[^a]', Mark.link), isEmpty);
  });

  test('math hugs its dollars, prices are left alone', () {
    expect(_pieces(r'soit $x^2$ ici', Mark.math), [r'$x^2$']);
    expect(_pieces(r'de 5 $ à 10 $', Mark.math), isEmpty);
    expect(_pieces(r'$$a+b$$', Mark.math), [r'$$a+b$$']);
  });

  test('blocks over several lines', () {
    const code = '```dart\n**pas gras**\n```';
    expect(_pieces(code, Mark.code, 1), ['**pas gras**']);
    expect(_pieces(code, Mark.fence, 0), ['```dart']);
    expect([for (var i = 0; i < 3; i++) _line(code, i).block], [true, true, true]);
    expect(_line('a\n\nb', 1).block, isFalse);
    expect(_pieces('---\ntitre: x\n---\ntexte', Mark.frontMatter, 1), ['titre: x']);
    const matter = '---\ntitre: "x" # c\ntags: [a]\n---\ntexte';
    expect([for (var i = 0; i < 5; i++) _line(matter, i).block], [true, true, true, true, false]);
    expect(_pieces(matter, Mark.token(Token.name), 1), ['titre']);
    expect(_pieces(matter, Mark.token(Token.string), 1), ['"x"']);
    expect(_pieces(matter, Mark.token(Token.comment), 1), ['# c']);
    expect(_pieces(matter, Mark.token(Token.name), 2), ['tags']);
    expect(_pieces(matter, Mark.tokens, 4), isEmpty);
    expect([for (var i = 0; i < 4; i++) _preview(matter, i)], ['[fold]', 'titre: "x" # c', 'tags: [a]', '[fold]']);
    expect(_pieces('> ```\n> code', Mark.code, 1), ['code']);
    expect(_line('```a`b').block, isFalse);
  });

  test('code of a known language is colored line by line, over containers too', () {
    const code = '```dart\nfinal a = 1; /* un\ndeux */\n```';
    expect(_pieces(code, Mark.token(Token.keyword), 1), ['final']);
    expect(_pieces(code, Mark.token(Token.number), 1), ['1']);
    expect(_pieces(code, Mark.token(Token.comment), 1), ['/* un']);
    expect(_pieces(code, Mark.token(Token.comment), 2), ['deux */']);
    expect(_pieces(code, Mark.code, 1), ['final a = 1; /* un']);
    expect(_pieces(code, Mark.token(Token.keyword), 0), isEmpty);
    expect(_pieces('```klingon\nfinal a\n```', Mark.tokens, 1), isEmpty);
    expect(_pieces('> ```go\n> func f() {}\n> ```', Mark.token(Token.keyword), 1), ['func']);
    expect(_pieces('- ```go\n  func f() {}\n  ```', Mark.token(Token.keyword), 1), ['func']);
    expect(_pieces('`final` seul', Mark.tokens), isEmpty);
  });

  test('a quote opened by [!kind] is a callout, whose title is shown in its color', () {
    const note = '> [!warning]- Attention\n> corps\n>\n> suite\n\n> pas un [!note]';
    expect([for (var i = 0; i < 6; i++) _line(note, i).callout], [
      CalloutKind.warning, CalloutKind.warning, CalloutKind.warning, CalloutKind.warning, null, null,
    ]);
    expect(_preview(note), '[bar]Attention');
    expect(_preview(note, 1), '[bar]corps');
    expect(_preview('> [!tip]'), '[bar]Tip');
    expect(_preview('> [!QUESTION]  À voir'), '[bar]À voir');
    expect(_pieces(note, Mark.callout(CalloutKind.warning), 0), ['[!warning]- Attention']);
    expect(_pieces(note, Mark.callouts, 1), isEmpty);
    expect(_pieces(note, Mark.quote, 1), isEmpty);
    expect(_pieces('> citation', Mark.quote), ['> citation']);
    expect(_line('> [!inconnu] x').callout, CalloutKind.note);
    expect(_line('> [!note] a\n> [!tip] b', 1).callout, CalloutKind.note);
    expect(_line('> [! note]').callout, isNull);
    expect(_line('[!note] seul').callout, isNull);
    expect(_line('- > [!note]').callout, isNull);
  });

  test('the rows of a table that is a block of its own read as a grid', () {
    const note = '| a | **b** |\n|:-:|--:|\n|c|\n\n> | q |\n> |---|';
    final head = _line(note).table!;
    expect((head.first, head.last, head.header, head.delimiter), (0, 2, true, false));
    expect(head.align.map((a) => a.name), ['center', 'right']);
    expect([for (final c in head.cells) (c.start, c.end)], [(2, 3), (6, 11)]);
    final rule = _line(note, 1).table!;
    expect(rule.delimiter, isTrue);
    expect(rule.cells, isEmpty);
    final body = _line(note, 2).table!;
    expect((body.header, body.delimiter, body.cells.length), (false, false, 2));
    expect([for (final c in body.cells) (c.start, c.end)], [(1, 2), (3, 3)]);
    expect(_line(note, 3).table, isNull);
    expect(_line(note, 4).table, isNull);
    expect(_line('| a |\n|---|', 0).table, isNotNull);
    expect(_line('| a | b\n|---|---|', 0).table, isNotNull);
  });

  test('the preview hides the syntax, and shows bullets, boxes, bars and rules', () {
    expect(_preview('## Titre ##'), 'Titre');
    expect(_preview('Un **gras** et un [lien](https://x.fr).'), 'Un gras et un lien.');
    expect(_preview(r'\*pas\* &amp; `code`'), '*pas* & code');
    expect(_preview('- item'), '• item');
    expect(_preview('3. item'), '3. item');
    expect(_preview('- [ ] à faire\n- [x] fait'), '• [box] à faire');
    expect(_preview('- [ ] à faire\n- [x] fait', 1), '• [doneBox] fait');
    expect(_preview('> cité'), '[bar]cité');
    expect(_preview('***'), '[rule]');
    expect(_preview('```dart\nx\n```'), '[fold dart]');
    expect(_preview('```dart\nx\n```', 1), 'x');
    expect(_preview('```dart\nx\n```', 2), '[fold]');
    expect(_preview('Titre\n---', 1), '[fold]');
    expect(_preview('[[Note|alias]]'), 'alias');
    expect(_preview('| a | b |\n|---|---|'), '| a | b |');
  });

  test('pictures and the text of links are what the host may show otherwise', () {
    List<Swap> asked(String line) =>
        _line(line).swaps.where((s) => s.kind == SwapKind.picture || s.kind == SwapKind.label).toList();
    expect(asked('Hi [@A](user:1) <https://x.fr> www.y.fr'), [
      (start: 4, end: 6, kind: SwapKind.label, text: 'user:1'),
      (start: 16, end: 30, kind: SwapKind.label, text: 'https://x.fr'),
      (start: 31, end: 39, kind: SwapKind.label, text: 'http://www.y.fr'),
    ]);
    expect(asked('[[My note|this]] ![[pic.png]]'), [
      (start: 10, end: 14, kind: SwapKind.label, text: 'My%20note'),
      (start: 17, end: 29, kind: SwapKind.picture, text: 'pic.png'),
    ]);
    expect(asked('[![a](p.png)](x)'), [
      (start: 1, end: 12, kind: SwapKind.picture, text: 'p.png'),
      (start: 1, end: 12, kind: SwapKind.label, text: 'x'),
    ]);
    expect(_preview('![a *b*](p.png)'), 'a b');
  });
}
