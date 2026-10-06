// Package md parses Markdown: CommonMark, the extensions of GitHub (tables,
// task lists, strikethrough, autolinks) and those of Bref (front matter,
// math, highlights, wiki links, footnotes). Each node knows where it lies in the source
// and which of its characters are syntax rather than text, so that an editor
// can hide them and a host can find what a person wrote.
//
// The Dart package of Bref parses the same way, checked against the vectors
// in testdata/md.
package md

// Kind is what a node is.
type Kind uint8

const (
	Document Kind = iota
	Paragraph
	Heading
	ThematicBreak
	CodeBlock
	HTMLBlock
	Quote
	List
	Item
	Table
	Row
	Cell
	MathBlock
	FrontMatter
	Definition
	FootnoteDef

	Text
	SoftBreak
	HardBreak
	Escape
	Entity
	Code
	Emphasis
	Strong
	Strike
	Highlight
	Link
	Image
	InlineHTML
	Math
	FootnoteRef
)

var kindNames = [...]string{
	"document", "paragraph", "heading", "thematic_break", "code_block", "html_block", "quote", "list", "item",
	"table", "row", "cell", "math_block", "front_matter", "definition", "footnote_def",
	"text", "soft_break", "hard_break", "escape", "entity", "code", "emphasis", "strong", "strike", "highlight",
	"link", "image", "inline_html", "math", "footnote_ref",
}

func (k Kind) String() string { return kindNames[k] }

// LinkForm is how a link or an image is written.
type LinkForm uint8

const (
	// LinkInline is [text](dest "title").
	LinkInline LinkForm = iota
	// LinkReference is [text][label], [label][] or [label].
	LinkReference
	// LinkAngle is <dest>.
	LinkAngle
	// LinkBare is a web or mail address in the text.
	LinkBare
	// LinkWiki is [[dest]] or [[dest|text]].
	LinkWiki
)

// Align is the alignment of a column of a table.
type Align uint8

const (
	AlignNone Align = iota
	AlignLeft
	AlignCenter
	AlignRight
)

// Task is the box of a task list item.
type Task uint8

const (
	TaskNone Task = iota
	TaskOpen
	TaskDone
)

// Span is a range of the source, in bytes.
type Span struct {
	Start, End int
}

// Node is a block or an inline of a document.
type Node struct {
	Kind Kind
	Span
	// Marks are the syntax of the node in the source, in order: the markers
	// of a quote on each of its lines, the asterisks around emphasis, the
	// brackets and destination of a link. They never cross a line.
	Marks    []Span
	Children []*Node

	// Literal is the text of Text, Escape, Entity, Code, InlineHTML and Math, and
	// the content of CodeBlock, HTMLBlock, MathBlock and FrontMatter.
	Literal string
	// Level is that of a Heading, from 1 to 6.
	Level int
	// Info is the info string of a fenced CodeBlock.
	Info string

	// Ordered, Number, Tight and Marker describe a List: Number is that of
	// its first item, Marker the bullet or the delimiter after numbers.
	Ordered bool
	Number  int
	Tight   bool
	Marker  byte
	// Task is the box of an Item.
	Task Task

	// Align is that of each column of a Table; Header tells the first Row.
	Align  []Align
	Header bool

	// Dest, Title and URL describe a Link, an Image or a Definition: URL is
	// where Dest is written, empty when it comes from a definition. Label is
	// that of a Definition, a FootnoteDef, a FootnoteRef or a reference, as
	// written.
	Dest  string
	Title string
	URL   Span
	Label string
	Form  LinkForm

	// Display tells $$math$$ from $math$.
	Display bool
}

// Walk calls f on n and its descendants, depth first, skipping the
// descendants of a node for which f is false.
func (n *Node) Walk(f func(*Node) bool) {
	if !f(n) {
		return
	}
	for _, c := range n.Children {
		c.Walk(f)
	}
}

// Links are the links and pictures of a document, in order, those in the
// text of others included.
func Links(doc *Node) []*Node {
	var links []*Node
	doc.Walk(func(n *Node) bool {
		if n.Kind == Link || n.Kind == Image {
			links = append(links, n)
		}
		return true
	})
	return links
}
