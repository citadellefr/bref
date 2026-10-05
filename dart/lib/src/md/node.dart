/// What a node is.
enum MdKind {
  document,
  paragraph,
  heading,
  thematicBreak,
  codeBlock,
  htmlBlock,
  quote,
  list,
  item,
  table,
  row,
  cell,
  mathBlock,
  frontMatter,
  definition,

  text,
  softBreak,
  hardBreak,
  escape,
  entity,
  code,
  emphasis,
  strong,
  strike,
  highlight,
  link,
  image,
  inlineHtml,
  math,
}

/// How a link or an image is written.
enum LinkForm {
  /// `[text](dest "title")`.
  inline,

  /// `[text][label]`, `[label][]` or `[label]`.
  reference,

  /// `<dest>`.
  angle,

  /// A web or mail address in the text.
  bare,

  /// `[[dest]]` or `[[dest|text]]`.
  wiki,
}

enum Align { none, left, center, right }

/// The box of a task list item.
enum Task { none, open, done }

/// A range of the source, in UTF-16 code units.
typedef Span = ({int start, int end});

/// The syntax a document is read with.
abstract final class MdSyntax {
  static const tables = 1 << 0;
  static const tasks = 1 << 1;
  static const strike = 1 << 2;
  static const autolinks = 1 << 3;
  static const frontMatter = 1 << 4;
  static const math = 1 << 5;
  static const highlight = 1 << 6;
  static const wiki = 1 << 7;

  static const commonMark = 0;
  static const gfm = tables | tasks | strike | autolinks;
  static const bref = gfm | frontMatter | math | highlight | wiki;
}

/// A block or an inline of a document, as the Go package of Bref reads it.
class MdNode {
  MdNode(this.kind, this.start, [int? end]) : end = end ?? start;

  MdKind kind;
  int start;
  int end;

  /// The syntax of the node in the source, in order: the markers of a quote
  /// on each of its lines, the asterisks around emphasis, the brackets and
  /// destination of a link. They never cross a line.
  List<Span> marks = const [];
  List<MdNode> children = const [];

  /// The text of text, escape, entity, code, inline HTML and math, and the
  /// content of code, HTML and math blocks and of front matter.
  String literal = '';

  /// The level of a heading, from 1 to 6.
  int level = 0;

  /// The info string of a fenced code block.
  String info = '';

  bool ordered = false;

  /// The number of the first item of an ordered list.
  int number = 0;
  bool tight = false;

  /// The bullet of a list, or the delimiter after its numbers.
  String marker = '';
  Task task = Task.none;
  List<Align> align = const [];

  /// Whether a row is the header of its table.
  bool header = false;

  /// What a link, an image or a definition leads to, and where it is
  /// written: [url] is empty when it comes from a definition.
  String dest = '';
  String title = '';
  Span url = (start: 0, end: 0);

  /// The label of a definition or a reference, as written.
  String label = '';
  LinkForm form = LinkForm.inline;

  /// Whether math is `$$display$$` rather than `$inline$`.
  bool display = false;

  void mark(int start, int end) {
    final span = (start: start, end: end);
    if (marks.isEmpty) {
      marks = [span];
    } else {
      marks.add(span);
    }
  }

  void add(MdNode child) {
    if (children.isEmpty) {
      children = [child];
    } else {
      children.add(child);
    }
  }

  /// Calls [f] on this node and its descendants, depth first, skipping the
  /// descendants of a node for which it answers false.
  void walk(bool Function(MdNode) f) {
    if (!f(this)) return;
    for (final c in children) {
      c.walk(f);
    }
  }
}
