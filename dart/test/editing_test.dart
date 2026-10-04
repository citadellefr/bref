import 'package:bref/src/editing.dart';
import 'package:bref/src/note_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moves by characters as the reader sees them', () {
    final t = NoteText('ét😀\nb\n');
    expect(nextCharacter(t, 0), 2);
    expect(nextCharacter(t, 3), 5);
    expect(nextCharacter(t, 5), 6);
    expect(previousCharacter(t, 5), 3);
    expect(previousCharacter(t, 2), 0);
    expect(previousCharacter(t, 6), 5);
    expect(nextCharacter(t, t.length), t.length);
  });

  test('moves by words, stopping at the ends of lines', () {
    final t = NoteText('Le chat, noir.\nfin\n');
    expect(nextWord(t, 0), 2);
    expect(nextWord(t, 2), 7);
    expect(nextWord(t, 7), 8);
    expect(nextWord(t, 14), 15);
    expect(previousWord(t, 14), 13);
    expect(previousWord(t, 13), 9);
    expect(previousWord(t, 15), 14);
    expect(wordAt(t, 4), (3, 7));
    expect(wordAt(t, 14), (13, 14));
  });

  test('Enter goes on with lists and quotes, or ends them', () {
    String press(String line, [int? at]) {
      final t = NoteText('$line\n');
      final r = enter(t, at ?? line.length);
      if (r == null) return 'none';
      final text = t.text;
      return text.substring(0, r.start) + r.text + text.substring(r.end);
    }

    expect(press('- un'), '- un\n- ');
    expect(press('  * [x] fait'), '  * [x] fait\n  * [ ] ');
    expect(press('9. neuf'), '9. neuf\n10. ');
    expect(press('> > cité'), '> > cité\n> > ');
    expect(press('> - dans'), '> - dans\n> - ');
    expect(press('- '), '');
    expect(press('3. '), '');
    expect(press('> '), '');
    expect(press('texte'), 'none');
    expect(press('- un', 1), 'none');
  });

  test('indents and outdents lines', () {
    final t = NoteText('- a\n\t- b\nc\n');
    expect(indent(t, 0, 5, outdent: false), [(start: 0, end: 0, text: '  '), (start: 4, end: 4, text: '\t')]);
    expect(indent(t, 0, t.length, outdent: true), [(start: 4, end: 5, text: '')]);
  });
}
