import 'note_text.dart';
import 'syntax.dart';

/// The syntax of every line of a note. What each line leaves open is known
/// for all of them; the marks of a line are read when it is first shown,
/// and read again only when its text or what precedes it changes.
class NoteSyntax {
  NoteSyntax(this.text) {
    reset();
  }

  final NoteText text;

  /// What the lines before each line left open, and after the last.
  final _states = <BlockState>[];
  final _lines = <LineSyntax?>[];

  LineSyntax line(int i) => _lines[i] ??= readLine(text.line(i), i, _states[i]);

  /// Whether line [i] belongs to a block of code or math, its fences
  /// included: it is drawn on a background of its own.
  bool inBlock(int i) => _block(_states[i]) || _block(_states[i + 1]);

  static bool _block(BlockState s) => s != BlockState.text && s != BlockState.frontMatter;

  void reset() {
    _states
      ..clear()
      ..add(BlockState.text);
    _lines
      ..clear()
      ..length = text.lineCount;
    for (var i = 0; i < text.lineCount; i++) {
      _states.add(nextState(text.line(i), i, _states[i]));
    }
  }

  /// Follows a splice the text made, and answers the lines after the new
  /// ones whose syntax changed with it: a fence opened changes all those up
  /// to the next fence.
  int splice(LineSplice s) {
    _lines.replaceRange(s.index, s.index + s.removed, List.filled(s.inserted, null));
    _states.replaceRange(s.index + 1, s.index + s.removed + 1, List.filled(s.inserted, BlockState.text));
    var changed = 0;
    for (var i = s.index; i < text.lineCount; i++) {
      final next = nextState(text.line(i), i, _states[i]);
      if (i >= s.index + s.inserted && next == _states[i + 1]) break;
      _states[i + 1] = next;
      if (i + 1 < text.lineCount) {
        _lines[i + 1] = null;
        if (i + 1 >= s.index + s.inserted) changed++;
      }
    }
    return changed;
  }
}
