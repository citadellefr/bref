package md

import (
	"regexp"
	"slices"
	"strings"
)

type extensions uint16

const (
	extTables extensions = 1 << iota
	extTasks
	extStrike
	extAutolinks
	extFrontMatter
	extMath
	extHighlight
	extWiki

	gfm  = extTables | extTasks | extStrike | extAutolinks
	bref = gfm | extFrontMatter | extMath | extHighlight | extWiki
)

// Parse reads a Markdown document, whose lines end with "\n", "\r\n" or
// "\r".
func Parse(src string) *Node {
	return parse(src, bref)
}

func parse(src string, ext extensions) *Node {
	p := newBlockParser(src, ext)
	lines := splitLines(src)
	i := 0
	if ext&extFrontMatter != 0 {
		i = p.frontMatter(lines)
	}
	for ; i < len(lines); i++ {
		p.addLine(lines[i])
	}
	return p.finish()
}

func splitLines(src string) []Span {
	var lines []Span
	start := 0
	for i := 0; i < len(src); i++ {
		switch src[i] {
		case '\n':
			lines = append(lines, Span{start, i})
			start = i + 1
		case '\r':
			lines = append(lines, Span{start, i})
			if i+1 < len(src) && src[i+1] == '\n' {
				i++
			}
			start = i + 1
		}
	}
	if start < len(src) {
		lines = append(lines, Span{start, len(src)})
	}
	return lines
}

const codeIndent = 4

// segment is a line of the content of a leaf block: where it lies in the
// source, after the spaces a partly consumed tab stands for.
type segment struct {
	start, end int
	pad        int
}

type block struct {
	node  *Node
	lines []segment

	markerOffset, padding int

	fenceChar   byte
	fenceLen    int
	fenceOffset int
	html        int

	columns    int
	tableTried bool
}

// leaf is a block whose content is parsed for inlines once all blocks are
// known, with the definitions they hold.
type leaf struct {
	node  *Node
	lines []segment
	table bool
}

type blockParser struct {
	src    string
	ext    extensions
	doc    *Node
	open   []*block
	leaves []leaf
	refs   map[string]*Node

	line                             string
	start, end, prevEnd              int
	offset, column                   int
	nextNonspace, nextNonspaceColumn int
	indent                           int
	indented, blank, partialTab      bool
	spaceEnd, spaceTab               int

	allClosed   bool
	lastMatched int
	oldTip      int
}

func newBlockParser(src string, ext extensions) *blockParser {
	doc := &Node{Kind: Document, Span: Span{0, len(src)}}
	return &blockParser{src: src, ext: ext, doc: doc, open: []*block{{node: doc}}, refs: map[string]*Node{}, allClosed: true}
}

func (p *blockParser) top() *block { return p.open[len(p.open)-1] }

func (p *blockParser) peek(i int) int {
	if i < len(p.line) {
		return int(p.line[i])
	}
	return -1
}

func isSpaceOrTab(c int) bool { return c == ' ' || c == '\t' }

func (p *blockParser) findNextNonspace() {
	i, cols := p.offset, p.column
	if p.offset <= p.spaceEnd && p.offset > p.spaceTab {
		// the spaces up to spaceEnd were read already, and hold no tab
		cols += p.spaceEnd - p.offset
		i = p.spaceEnd
	} else {
		p.spaceTab = -1
		for i < len(p.line) {
			if p.line[i] == ' ' {
				i++
				cols++
			} else if p.line[i] == '\t' {
				p.spaceTab = i
				i++
				cols += 4 - cols%4
			} else {
				break
			}
		}
		p.spaceEnd = i
	}
	p.blank = i == len(p.line)
	p.nextNonspace = i
	p.nextNonspaceColumn = cols
	p.indent = cols - p.column
	p.indented = p.indent >= codeIndent
}

func (p *blockParser) advanceNextNonspace() {
	p.offset = p.nextNonspace
	p.column = p.nextNonspaceColumn
	p.partialTab = false
}

// advanceOffset moves count characters, or count columns when columns is
// set, a tab then being partly consumed.
func (p *blockParser) advanceOffset(count int, columns bool) {
	for count > 0 && p.offset < len(p.line) {
		if p.line[p.offset] == '\t' {
			toTab := 4 - p.column%4
			if columns {
				p.partialTab = toTab > count
				n := min(toTab, count)
				p.column += n
				if !p.partialTab {
					p.offset++
				}
				count -= n
			} else {
				p.partialTab = false
				p.column += toTab
				p.offset++
				count--
			}
		} else {
			p.partialTab = false
			p.offset++
			p.column++
			count--
		}
	}
}

func (p *blockParser) addLine(l Span) {
	p.line = p.src[l.Start:l.End]
	p.start, p.end = l.Start, l.End
	p.offset, p.column = 0, 0
	p.blank, p.partialTab = false, false
	p.spaceEnd, p.spaceTab = -1, -1
	p.oldTip = len(p.open) - 1
	defer func() { p.prevEnd = p.end }()

	container := 0
	for container+1 < len(p.open) {
		p.findNextNonspace()
		r := p.continues(p.open[container+1])
		if r == 2 {
			return
		}
		if r == 1 {
			break
		}
		container++
	}
	p.allClosed = container == p.oldTip
	p.lastMatched = container

	k := p.open[container].node.Kind
	matchedLeaf := k != Paragraph && acceptsLines(k)
	for !matchedLeaf {
		p.findNextNonspace()
		if !p.indented && !maybeSpecial(p.peek(p.nextNonspace)) {
			p.advanceNextNonspace()
			break
		}
		r := p.blockStart(container)
		if r == 0 {
			p.advanceNextNonspace()
			break
		}
		container = len(p.open) - 1
		matchedLeaf = r == 2
	}

	if !p.allClosed && !p.blank && p.top().node.Kind == Paragraph {
		p.addContent(p.top())
		return
	}
	p.closeUnmatched()
	c := p.top()
	switch {
	case acceptsLines(c.node.Kind):
		p.addContent(c)
		if c.node.Kind == HTMLBlock && c.html >= 1 && c.html <= 5 && htmlClose[c.html].MatchString(p.line[p.offset:]) {
			p.close(true)
		}
	case c.node.Kind == Table:
		if p.offset < len(p.line) {
			p.addRow(c)
		}
	case p.offset < len(p.line) && !p.blank:
		p.addChild(Paragraph, p.nextNonspace)
		p.advanceNextNonspace()
		p.addContent(p.top())
	}
}

func maybeSpecial(c int) bool {
	switch c {
	case '#', '`', '~', '*', '+', '_', '=', '<', '>', '-', '|', ':', '$':
		return true
	}
	return c >= '0' && c <= '9'
}

func acceptsLines(k Kind) bool {
	return k == Paragraph || k == CodeBlock || k == HTMLBlock || k == MathBlock
}

func canContain(parent, child Kind) bool {
	switch parent {
	case Document, Quote, Item:
		return child != Item
	case List:
		return child == Item
	}
	return false
}

// continues tells whether an open block goes on on the current line:
// 0 if it does, 1 if not, 2 if the line closed it and is done.
func (p *blockParser) continues(b *block) int {
	switch b.node.Kind {
	case Quote:
		if p.indented || p.peek(p.nextNonspace) != '>' {
			return 1
		}
		at := p.nextNonspace
		p.advanceNextNonspace()
		p.advanceOffset(1, false)
		if isSpaceOrTab(p.peek(p.offset)) {
			p.advanceOffset(1, true)
		}
		b.node.Marks = append(b.node.Marks, Span{p.start + at, p.start + p.offset})
	case Item:
		switch {
		case p.indent >= b.markerOffset+b.padding:
			p.advanceOffset(b.markerOffset+b.padding, true)
		case p.blank && len(b.node.Children) > 0:
			p.advanceNextNonspace()
		default:
			return 1
		}
	case Heading, ThematicBreak:
		return 1
	case CodeBlock:
		if b.fenceLen == 0 {
			switch {
			case p.indent >= codeIndent:
				p.advanceOffset(codeIndent, true)
			case p.blank:
				p.advanceNextNonspace()
			default:
				return 1
			}
			return 0
		}
		if p.indent <= 3 && p.peek(p.nextNonspace) == int(b.fenceChar) && closingFence(p.line[p.nextNonspace:], b.fenceChar) >= b.fenceLen {
			b.node.Marks = append(b.node.Marks, Span{p.start + p.nextNonspace, p.end})
			p.close(true)
			return 2
		}
		p.skipFenceOffset(b)
	case MathBlock:
		if p.indent <= 3 && strings.HasPrefix(p.line[p.nextNonspace:], "$$") && isBlank(p.line[p.nextNonspace+2:]) {
			b.node.Marks = append(b.node.Marks, Span{p.start + p.nextNonspace, p.end})
			p.close(true)
			return 2
		}
		p.skipFenceOffset(b)
	case HTMLBlock:
		if p.blank && (b.html == 6 || b.html == 7) {
			return 1
		}
	case Paragraph:
		if p.blank {
			return 1
		}
	case Table:
		if p.blank {
			return 1
		}
		if cells, _ := splitRow(p.line[p.nextNonspace:]); len(cells) == 0 {
			return 1
		}
	}
	return 0
}

func (p *blockParser) skipFenceOffset(b *block) {
	for i := b.fenceOffset; i > 0 && isSpaceOrTab(p.peek(p.offset)); i-- {
		p.advanceOffset(1, true)
	}
}

// blockStart opens the blocks the current line starts: 0 if none, 1 for a
// container, 2 for a leaf, after which no other block starts.
func (p *blockParser) blockStart(container int) int {
	c := p.open[container]
	at := p.nextNonspace
	rest := p.line[at:]
	if !p.indented {
		switch {
		case rest[0] == '>':
			p.advanceNextNonspace()
			p.advanceOffset(1, false)
			if isSpaceOrTab(p.peek(p.offset)) {
				p.advanceOffset(1, true)
			}
			p.closeUnmatched()
			b := p.addChild(Quote, at)
			b.node.Marks = append(b.node.Marks, Span{p.start + at, p.start + p.offset})
			return 1
		case rest[0] == '#':
			if n, level := atxMarker(rest); n > 0 {
				p.advanceNextNonspace()
				p.advanceOffset(n, false)
				p.closeUnmatched()
				b := p.addChild(Heading, at)
				b.node.Level = level
				b.node.Marks = append(b.node.Marks, Span{p.start + at, p.start + p.offset})
				content := p.line[p.offset:]
				if i := atxClosing(content); i >= 0 {
					b.node.Marks = append(b.node.Marks, Span{p.start + p.offset + i, p.end})
					content = content[:i]
				}
				b.lines = []segment{{start: p.start + p.offset, end: p.start + p.offset + len(content)}}
				p.advanceOffset(len(p.line)-p.offset, false)
				return 2
			}
		}
		if n := openingFence(rest); n > 0 {
			p.closeUnmatched()
			b := p.addChild(CodeBlock, at)
			b.fenceChar, b.fenceLen, b.fenceOffset = rest[0], n, p.indent
			b.node.Marks = append(b.node.Marks, Span{p.start + at, p.end})
			p.advanceNextNonspace()
			p.advanceOffset(n, false)
			return 2
		}
		if p.ext&extMath != 0 && strings.HasPrefix(rest, "$$") && isBlank(rest[2:]) {
			p.closeUnmatched()
			b := p.addChild(MathBlock, at)
			b.fenceOffset = p.indent
			b.node.Marks = append(b.node.Marks, Span{p.start + at, p.end})
			p.advanceOffset(len(p.line)-p.offset, false)
			return 2
		}
		if rest[0] == '<' {
			lazy := !p.allClosed && !p.blank && p.top().node.Kind == Paragraph
			for kind := 1; kind <= 7; kind++ {
				if htmlOpen[kind].MatchString(rest) && (kind < 7 || (c.node.Kind != Paragraph && !lazy)) {
					p.closeUnmatched()
					b := p.addChild(HTMLBlock, p.offset)
					b.html = kind
					return 2
				}
			}
		}
		if c.node.Kind == Paragraph {
			if level := setextLevel(rest); level > 0 {
				p.closeUnmatched()
				p.takeDefinitions(c, p.open[len(p.open)-2].node)
				if len(c.lines) > 0 {
					c.node.Kind = Heading
					c.node.Level = level
					c.node.Start = c.lines[0].start
					c.node.Marks = append(c.node.Marks, Span{p.start + at, p.end})
					p.advanceOffset(len(p.line)-p.offset, false)
					return 2
				}
			}
		}
		if thematicBreak(rest) {
			p.closeUnmatched()
			b := p.addChild(ThematicBreak, at)
			b.node.Marks = append(b.node.Marks, Span{p.start + at, p.end})
			p.advanceOffset(len(p.line)-p.offset, false)
			return 2
		}
	}
	if !p.indented || c.node.Kind == List {
		if d, ok := p.listMarker(c); ok {
			p.closeUnmatched()
			if t := p.top().node; t.Kind != List || t.Ordered != d.ordered || t.Marker != d.marker {
				l := p.addChild(List, at)
				l.node.Ordered, l.node.Number, l.node.Marker, l.node.Tight = d.ordered, d.number, d.marker, true
			}
			b := p.addChild(Item, at)
			b.markerOffset, b.padding = d.markerOffset, d.padding
			b.node.Marks = append(b.node.Marks, Span{p.start + at, p.start + at + d.length})
			if p.ext&extTasks != 0 {
				if task := taskBox(p.line[p.offset:]); task != TaskNone {
					b.node.Task = task
					b.node.Marks = append(b.node.Marks, Span{p.start + p.offset, p.start + p.offset + 3})
					p.advanceOffset(3, false)
				}
			}
			return 1
		}
	}
	if p.indented && p.top().node.Kind != Paragraph && !p.blank {
		p.advanceOffset(codeIndent, true)
		p.closeUnmatched()
		p.addChild(CodeBlock, p.offset)
		return 2
	}
	if p.ext&extTables != 0 && !p.indented && c.node.Kind == Paragraph && !c.tableTried && p.openTable(c) {
		return 2
	}
	return 0
}

func (p *blockParser) closeUnmatched() {
	if p.allClosed {
		return
	}
	for len(p.open)-1 > p.lastMatched {
		p.close(false)
	}
	p.allClosed = true
}

func (p *blockParser) addChild(kind Kind, offset int) *block {
	for !canContain(p.top().node.Kind, kind) {
		p.close(false)
	}
	n := &Node{Kind: kind, Span: Span{p.start + offset, p.start + offset}}
	parent := p.top().node
	parent.Children = append(parent.Children, n)
	b := &block{node: n}
	p.open = append(p.open, b)
	return b
}

func (p *blockParser) addContent(b *block) {
	if p.partialTab {
		p.offset++
		b.lines = append(b.lines, segment{start: p.start + p.offset, end: p.end, pad: 4 - p.column%4})
		return
	}
	b.lines = append(b.lines, segment{start: p.start + p.offset, end: p.end})
}

// close closes the innermost open block, which ends on the current line
// when here is set, else on the line before.
func (p *blockParser) close(here bool) {
	b := p.top()
	p.open = p.open[:len(p.open)-1]
	n := b.node
	n.End = p.prevEnd
	if here {
		n.End = p.end
	}
	switch n.Kind {
	case Paragraph:
		p.closeParagraph(b, p.top().node)
	case Heading:
		p.leaves = append(p.leaves, leaf{node: n, lines: b.lines})
	case CodeBlock:
		if b.fenceLen > 0 {
			n.Info = unescape(strings.Trim(p.text(b.lines[:1]), " \t"))
			n.Literal = p.text(b.lines[1:])
			break
		}
		lines := b.lines
		for len(lines) > 0 && isBlank(p.src[lines[len(lines)-1].start:lines[len(lines)-1].end]) {
			lines = lines[:len(lines)-1]
		}
		n.Literal = p.text(lines)
		n.End = lines[len(lines)-1].end
	case MathBlock:
		n.Literal = p.text(b.lines[1:])
	case HTMLBlock:
		n.Literal = strings.TrimSuffix(p.text(b.lines), "\n")
	case List:
		n.Tight = p.tight(n)
		n.End = n.Children[len(n.Children)-1].End
	case Item:
		if len(n.Children) > 0 {
			n.End = n.Children[len(n.Children)-1].End
		} else {
			n.End = n.Marks[len(n.Marks)-1].End
		}
	case Table:
		n.End = n.Children[len(n.Children)-1].End
	}
}

// text is the content of lines, each ended by "\n".
func (p *blockParser) text(lines []segment) string {
	var b strings.Builder
	for _, l := range lines {
		for range l.pad {
			b.WriteByte(' ')
		}
		b.WriteString(p.src[l.start:l.end])
		b.WriteByte('\n')
	}
	return strings.ReplaceAll(b.String(), "\x00", "�")
}

// tight tells a list none of whose items, nor their children, are
// separated by a blank line.
func (p *blockParser) tight(list *Node) bool {
	for i, item := range list.Children {
		if i+1 < len(list.Children) && p.blankBetween(item, list.Children[i+1]) {
			return false
		}
		for j := 0; j+1 < len(item.Children); j++ {
			if p.blankBetween(item.Children[j], item.Children[j+1]) {
				return false
			}
		}
	}
	return true
}

func (p *blockParser) blankBetween(a, b *Node) bool {
	return lineBreaks(p.src[a.End:b.Start]) > 1
}

func lineBreaks(s string) int {
	n := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' || (s[i] == '\r' && (i+1 == len(s) || s[i+1] != '\n')) {
			n++
		}
	}
	return n
}

func (p *blockParser) closeParagraph(b *block, parent *Node) {
	p.takeDefinitions(b, parent)
	if len(b.lines) == 0 {
		parent.Children = slices.DeleteFunc(parent.Children, func(c *Node) bool { return c == b.node })
		return
	}
	b.node.Start = b.lines[0].start
	p.leaves = append(p.leaves, leaf{node: b.node, lines: b.lines})
}

// takeDefinitions moves the link reference definitions a paragraph starts
// with out of it, before it in its parent.
func (p *blockParser) takeDefinitions(b *block, parent *Node) {
	if len(b.lines) == 0 || !strings.HasPrefix(p.src[b.lines[0].start:], "[") {
		return
	}
	ip := newInlineParser(p, b.lines, false)
	var defs []*Node
	for ip.pos < len(ip.text) && ip.text[ip.pos] == '[' {
		def := ip.definition()
		if def == nil {
			break
		}
		defs = append(defs, def)
	}
	if len(defs) == 0 {
		return
	}
	if ip.pos == len(ip.text) {
		b.lines = nil
	} else {
		b.lines = b.lines[ip.line(ip.pos):]
	}
	parent.Children = slices.Insert(parent.Children, slices.Index(parent.Children, b.node), defs...)
}

func (p *blockParser) finish() *Node {
	for len(p.open) > 1 {
		p.close(false)
	}
	for _, l := range p.leaves {
		ip := newInlineParser(p, l.lines, l.table)
		l.node.Children = ip.parse()
	}
	return p.doc
}

func (p *blockParser) frontMatter(lines []Span) int {
	if len(lines) < 2 || strings.TrimRight(p.src[lines[0].Start:lines[0].End], " \t") != "---" {
		return 0
	}
	for k := 1; k < len(lines); k++ {
		t := strings.TrimRight(p.src[lines[k].Start:lines[k].End], " \t")
		if t != "---" && t != "..." {
			continue
		}
		var body []segment
		for _, l := range lines[1:k] {
			body = append(body, segment{start: l.Start, end: l.End})
		}
		p.doc.Children = append(p.doc.Children, &Node{
			Kind:    FrontMatter,
			Span:    Span{0, lines[k].End},
			Marks:   []Span{lines[0], lines[k]},
			Literal: p.text(body),
		})
		p.prevEnd = lines[k].End
		return k + 1
	}
	return 0
}

type listData struct {
	ordered               bool
	marker                byte
	number                int
	length                int
	markerOffset, padding int
}

func (p *blockParser) listMarker(container *block) (listData, bool) {
	if p.indent >= 4 {
		return listData{}, false
	}
	rest := p.line[p.nextNonspace:]
	d := listData{markerOffset: p.indent}
	switch rest[0] {
	case '*', '+', '-':
		d.marker, d.length = rest[0], 1
	default:
		n := 0
		for n < len(rest) && n < 9 && rest[n] >= '0' && rest[n] <= '9' {
			d.number = d.number*10 + int(rest[n]-'0')
			n++
		}
		if n == 0 || n >= len(rest) || (rest[n] != '.' && rest[n] != ')') {
			return d, false
		}
		if container.node.Kind == Paragraph && d.number != 1 {
			return d, false
		}
		d.ordered, d.marker, d.length = true, rest[n], n+1
	}
	if next := p.peek(p.nextNonspace + d.length); next != -1 && !isSpaceOrTab(next) {
		return d, false
	}
	if container.node.Kind == Paragraph && isBlank(rest[d.length:]) {
		return d, false
	}
	p.advanceNextNonspace()
	p.advanceOffset(d.length, true)
	startColumn, startOffset, startTab := p.column, p.offset, p.partialTab
	for {
		p.advanceOffset(1, true)
		if p.column-startColumn >= 5 || !isSpaceOrTab(p.peek(p.offset)) {
			break
		}
	}
	spaces := p.column - startColumn
	if spaces >= 5 || spaces < 1 || p.peek(p.offset) == -1 {
		d.padding = d.length + 1
		p.column, p.offset, p.partialTab = startColumn, startOffset, startTab
		if isSpaceOrTab(p.peek(p.offset)) {
			p.advanceOffset(1, true)
		}
	} else {
		d.padding = d.length + spaces
	}
	return d, true
}

func taskBox(s string) Task {
	if len(s) < 3 || s[0] != '[' || s[2] != ']' || (len(s) > 3 && s[3] != ' ' && s[3] != '\t') {
		return TaskNone
	}
	switch s[1] {
	case ' ':
		return TaskOpen
	case 'x', 'X':
		return TaskDone
	}
	return TaskNone
}

func isBlank(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] != ' ' && s[i] != '\t' {
			return false
		}
	}
	return true
}

// atxMarker is the length of the opening of an ATX heading, its spaces
// included, and its level.
func atxMarker(s string) (int, int) {
	n := 0
	for n < len(s) && s[n] == '#' {
		n++
	}
	if n == 0 || n > 6 || (n < len(s) && s[n] != ' ' && s[n] != '\t') {
		return 0, 0
	}
	level := n
	for n < len(s) && (s[n] == ' ' || s[n] == '\t') {
		n++
	}
	return n, level
}

// atxClosing is where the closing sequence of an ATX heading's content
// starts, or -1.
func atxClosing(s string) int {
	end := len(s)
	for end > 0 && (s[end-1] == ' ' || s[end-1] == '\t') {
		end--
	}
	i := end
	for i > 0 && s[i-1] == '#' {
		i--
	}
	if i == end {
		return -1
	}
	if i == 0 {
		return 0
	}
	if s[i-1] != ' ' && s[i-1] != '\t' {
		return -1
	}
	for i > 0 && (s[i-1] == ' ' || s[i-1] == '\t') {
		i--
	}
	return i
}

func openingFence(s string) int {
	c := s[0]
	if c != '`' && c != '~' {
		return 0
	}
	n := 0
	for n < len(s) && s[n] == c {
		n++
	}
	if n < 3 || (c == '`' && strings.IndexByte(s[n:], '`') >= 0) {
		return 0
	}
	return n
}

func closingFence(s string, c byte) int {
	n := 0
	for n < len(s) && s[n] == c {
		n++
	}
	if n < 3 || !isBlank(s[n:]) {
		return 0
	}
	return n
}

func setextLevel(s string) int {
	c := s[0]
	if c != '=' && c != '-' {
		return 0
	}
	n := 0
	for n < len(s) && s[n] == c {
		n++
	}
	if !isBlank(s[n:]) {
		return 0
	}
	if c == '=' {
		return 1
	}
	return 2
}

func thematicBreak(s string) bool {
	c := s[0]
	if c != '*' && c != '-' && c != '_' {
		return false
	}
	n := 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case c:
			n++
		case ' ', '\t':
		default:
			return false
		}
	}
	return n >= 3
}

const (
	tagName      = `[A-Za-z][A-Za-z0-9-]*`
	attribute    = `(?:\s+[a-zA-Z_:][a-zA-Z0-9:._-]*(?:\s*=\s*(?:[^"'=<>` + "`" + `\x00-\x20]+|'[^']*'|"[^"]*"))?)`
	openTag      = `<` + tagName + attribute + `*\s*/?>`
	closeTag     = `</` + tagName + `\s*[>]`
	htmlTagRegex = `^(?:` + openTag + `|` + closeTag + `)`
)

var (
	htmlOpen = [...]*regexp.Regexp{
		nil,
		regexp.MustCompile(`(?i)^<(?:script|pre|textarea|style)(?:\s|>|$)`),
		regexp.MustCompile(`^<!--`),
		regexp.MustCompile(`^<[?]`),
		regexp.MustCompile(`^<![A-Za-z]`),
		regexp.MustCompile(`^<!\[CDATA\[`),
		regexp.MustCompile(`(?i)^<[/]?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[123456]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|search|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:\s|[/]?[>]|$)`),
		regexp.MustCompile(`(?i)^(?:` + openTag + `|` + closeTag + `)\s*$`),
	}
	htmlClose = [...]*regexp.Regexp{
		nil,
		regexp.MustCompile(`(?i)</(?:script|pre|textarea|style)>`),
		regexp.MustCompile(`-->`),
		regexp.MustCompile(`\?>`),
		regexp.MustCompile(`>`),
		regexp.MustCompile(`\]\]>`),
	}
)
