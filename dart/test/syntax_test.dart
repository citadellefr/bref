import 'package:bref/src/syntax.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pieces of a line marked [mark], as text.
List<String> _pieces(String line, int mark, {BlockState state = BlockState.text, int index = 1}) {
  final s = readLine(line, index, state);
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

void main() {
  test('headings, quotes, lists and rules', () {
    expect(readLine('## Titre ##', 1, BlockState.text).heading, 2);
    expect(_pieces('## Titre ##', Mark.markup), ['## ', ' ##']);
    expect(readLine('#hashtag', 1, BlockState.text).heading, 0);
    expect(_pieces('> > cité', Mark.markup), ['> > ']);
    expect(_pieces('> > cité', Mark.quote), ['> > cité']);
    expect(_pieces('  - [x] fait', Mark.listMarker), ['  - ']);
    expect(_pieces('  - [x] fait', Mark.task), ['[x]']);
    expect(_pieces('12) douze', Mark.listMarker), ['12) ']);
    expect(_pieces('* * *', Mark.rule), ['* * *']);
    expect(_pieces('| a | b |', Mark.table), ['|', '|', '|']);
    expect(_pieces('|---|:-:|', Mark.table), ['|---|:-:|']);
  });

  test('emphasis pairs as CommonMark pairs it', () {
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
  });

  test('math hugs its dollars, prices are left alone', () {
    expect(_pieces(r'soit $x^2$ ici', Mark.math), [r'$x^2$']);
    expect(_pieces(r'de 5 $ à 10 $', Mark.math), isEmpty);
    expect(_pieces(r'$$a+b$$', Mark.math), [r'$$a+b$$']);
  });

  test('blocks over several lines', () {
    var state = nextState('```dart', 1, BlockState.text);
    expect(state, const BlockState.code('```', 0));
    expect(_pieces('**pas gras**', Mark.code, state: state), ['**pas gras**']);
    expect(nextState('~~~', 2, state), state);
    expect(nextState('````', 2, state), BlockState.text);
    expect(nextState('``` rust', 2, state), state);

    state = nextState(r'$$', 1, BlockState.text);
    expect(state, BlockState.math);
    expect(nextState(r'$$', 2, state), BlockState.text);

    expect(nextState('---', 0, BlockState.text), BlockState.frontMatter);
    expect(nextState('---', 3, BlockState.text), BlockState.text);
    expect(nextState('titre: x', 1, BlockState.frontMatter), BlockState.frontMatter);
    expect(nextState('---', 2, BlockState.frontMatter), BlockState.text);

    expect(nextState('> ```', 1, BlockState.text), const BlockState.code('```', 0));
    expect(nextState('```a`b', 1, BlockState.text), BlockState.text);
  });
}
