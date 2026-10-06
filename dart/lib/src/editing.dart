import 'package:characters/characters.dart';

import 'note_syntax.dart';
import 'note_text.dart';

/// The offset a character before [offset]: a character as the reader sees
/// one, an emoji with its modifiers or a letter with its accents. The start
/// of a line steps back over its "\n".
int previousCharacter(NoteText text, int offset) {
  final i = text.lineAt(offset);
  final column = offset - text.lineStart(i);
  if (column == 0) return offset == 0 ? 0 : offset - 1;
  final range = CharacterRange.at(text.line(i), column)..moveBack();
  return text.lineStart(i) + range.stringBeforeLength;
}

int nextCharacter(NoteText text, int offset) {
  final i = text.lineAt(offset);
  final line = text.line(i);
  final column = offset - text.lineStart(i);
  if (column == line.length) return offset == text.length ? offset : offset + 1;
  final range = CharacterRange.at(line, column)..moveNext();
  return text.lineStart(i) + range.stringBeforeLength + range.current.length;
}

enum _Kind { space, word, other }

final _wordChar = RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);

_Kind _kind(String s, int i) {
  final c = s.codeUnitAt(i);
  if (c == 0x20 || c == 0x09 || c == 0xA0) return _Kind.space;
  if (c < 0x80) return _wordChar.hasMatch(s[i]) ? _Kind.word : _Kind.other;
  final end = (c >= 0xD800 && c < 0xDC00 && i + 1 < s.length) ? i + 2 : i + 1;
  return _wordChar.hasMatch(s.substring(i, end)) ? _Kind.word : _Kind.other;
}

/// Where a word move from [offset] lands: past the spaces, then past the
/// word or the punctuation that follows them. A line's end and start are
/// stops of their own.
int nextWord(NoteText text, int offset) {
  final i = text.lineAt(offset);
  final line = text.line(i);
  var c = offset - text.lineStart(i);
  if (c == line.length) return offset == text.length ? offset : offset + 1;
  while (c < line.length && _kind(line, c) == _Kind.space) {
    c++;
  }
  if (c < line.length) {
    final kind = _kind(line, c);
    while (c < line.length && _kind(line, c) == kind) {
      c++;
    }
  }
  return text.lineStart(i) + c;
}

int previousWord(NoteText text, int offset) {
  final i = text.lineAt(offset);
  final line = text.line(i);
  var c = offset - text.lineStart(i);
  if (c == 0) return offset == 0 ? 0 : offset - 1;
  while (c > 0 && _kind(line, c - 1) == _Kind.space) {
    c--;
  }
  if (c > 0) {
    final kind = _kind(line, c - 1);
    while (c > 0 && _kind(line, c - 1) == kind) {
      c--;
    }
  }
  return text.lineStart(i) + c;
}

/// The word, run of spaces or of punctuation around [offset], as a double
/// click selects it.
(int, int) wordAt(NoteText text, int offset) {
  final i = text.lineAt(offset);
  final line = text.line(i);
  if (line.isEmpty) return (offset, offset);
  var c = offset - text.lineStart(i);
  if (c == line.length) c--;
  final kind = _kind(line, c);
  var start = c, end = c;
  while (start > 0 && _kind(line, start - 1) == kind) {
    start--;
  }
  while (end < line.length && _kind(line, end) == kind) {
    end++;
  }
  return (text.lineStart(i) + start, text.lineStart(i) + end);
}

/// A replacement of the text: [start] to [end] by [text], the caret after.
typedef Replacement = ({int start, int end, String text});

final _item = RegExp(r'^((?:[ \t]*>[ \t]?)*)([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?');
final _quoted = RegExp(r'^(?:[ \t]*>[ \t]?)+');

/// What pressing Enter at [offset] does in a list or a quote: goes on with
/// the next item, numbered after this one, or ends the list when the item
/// is empty. Null elsewhere: the "\n" alone.
Replacement? enter(NoteText text, int offset) {
  final i = text.lineAt(offset);
  final line = text.line(i);
  final start = text.lineStart(i);
  final item = _item.firstMatch(line);
  final marker = item ?? _quoted.firstMatch(line);
  if (marker == null || offset - start < marker.end) return null;
  if (line.substring(marker.end).trim().isEmpty) return (start: start, end: start + line.length, text: '');
  if (item == null) return (start: offset, end: offset, text: '\n${marker[0]}');
  final number = item[4];
  final bullet = number == null ? item[3]! : '${int.parse(number) + 1}${item[5]}';
  final task = item[7] == null ? '' : '[ ] ';
  return (start: offset, end: offset, text: '\n${item[1]}${item[2]}$bullet${item[6]}$task');
}

/// The lines from [start] to [end] indented by one level, or [outdent]ed:
/// a level is two spaces, or a tab where the line starts with one.
List<Replacement> indent(NoteText text, int start, int end, {required bool outdent}) {
  final out = <Replacement>[];
  for (var i = text.lineAt(start); i <= text.lineAt(end); i++) {
    final line = text.line(i);
    final at = text.lineStart(i);
    if (!outdent) {
      out.add((start: at, end: at, text: line.startsWith('\t') ? '\t' : '  '));
      continue;
    }
    final n = line.startsWith('\t') ? 1 : (line.startsWith('  ') ? 2 : (line.startsWith(' ') ? 1 : 0));
    if (n > 0) out.add((start: at, end: at + n, text: ''));
  }
  return out;
}

/// Where the caret goes in a table: [base] to [extent] is the selection
/// after [insert], the row added at the end of the table when there is one.
typedef CellMove = ({int base, int extent, Replacement? insert});

/// Where moving [columns] cells and [rows] rows from [offset] leads in a
/// table, or null when [offset] is not in one. Past the last cell, or below
/// the last row, a row is added; before the first cell nothing moves.
CellMove? moveInTable(NoteText text, NoteSyntax syntax, int offset, {int rows = 0, int columns = 0}) {
  final i = text.lineAt(offset);
  final t = syntax.line(i).table;
  if (t == null || t.delimiter || t.cells.isEmpty) return null;
  final column = offset - text.lineStart(i);
  var k = 0;
  for (var j = 0; j < t.cells.length; j++) {
    if (t.cells[j].start <= column) k = j;
  }
  var row = i, cell = k + columns;
  if (rows == 0 && (cell < 0 || cell >= t.cells.length)) {
    row += columns;
    cell = columns > 0 ? 0 : t.cells.length - 1;
  } else {
    row += rows;
  }
  if (row != i && syntax.line(row.clamp(0, text.lineCount - 1)).table?.delimiter == true) row += row > i ? 1 : -1;
  if (row < t.first) return (base: offset, extent: offset, insert: null);
  if (row > t.last) {
    final end = text.lineEnd(t.last);
    final at = end + 1 + 2 + 4 * cell.clamp(0, t.cells.length - 1);
    final added = '\n|${'   |' * t.cells.length}';
    return (base: at, extent: at, insert: (start: end, end: end, text: added));
  }
  final target = syntax.line(row).table;
  if (target == null || target.cells.isEmpty) return null;
  final range = target.cells[cell.clamp(0, target.cells.length - 1)];
  final start = text.lineStart(row);
  return (base: start + range.start, extent: start + range.end, insert: null);
}
