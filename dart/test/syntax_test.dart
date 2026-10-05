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
    expect(_pieces('> ```\n> code', Mark.code, 1), ['code']);
    expect(_line('```a`b').block, isFalse);
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
    expect(asked('Hi [@A](user:1) <https://x.fr>'), [(start: 4, end: 6, kind: SwapKind.label, text: 'user:1')]);
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
