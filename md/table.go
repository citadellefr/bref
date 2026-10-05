package md

import "slices"

// openTable turns a paragraph into a table when its last line is a row and
// the current line the delimiter row under it, with as many cells.
func (p *blockParser) openTable(c *block) bool {
	rest := p.line[p.nextNonspace:]
	if len(c.lines) == 0 || !delimiterRow(rest) {
		return false
	}
	delims, _ := splitRow(rest)
	head := c.lines[len(c.lines)-1]
	cells, pipes := splitRow(p.src[head.start:head.end])
	if len(cells) != len(delims) {
		c.tableTried = true
		return false
	}
	p.closeUnmatched()
	parent := p.open[len(p.open)-2].node
	if len(c.lines) > 1 {
		before := &block{node: &Node{Kind: Paragraph, Span: Span{c.lines[0].start, c.lines[len(c.lines)-2].end}}, lines: c.lines[:len(c.lines)-1]}
		parent.Children = slices.Insert(parent.Children, slices.Index(parent.Children, c.node), before.node)
		p.closeParagraph(before, parent)
	}
	n := c.node
	n.Kind = Table
	n.Start = head.start
	for _, d := range delims {
		cell := rest[d.Start:d.End]
		left, right := cell[0] == ':', cell[len(cell)-1] == ':'
		switch {
		case left && right:
			n.Align = append(n.Align, AlignCenter)
		case left:
			n.Align = append(n.Align, AlignLeft)
		case right:
			n.Align = append(n.Align, AlignRight)
		default:
			n.Align = append(n.Align, AlignNone)
		}
	}
	c.columns = len(cells)
	c.lines = nil
	n.Children = append(n.Children, p.row(head.start, head.end, cells, pipes, true, c.columns))
	n.Marks = append(n.Marks, Span{p.start + p.nextNonspace, p.end})
	p.advanceOffset(len(p.line)-p.offset, false)
	return true
}

func (p *blockParser) addRow(c *block) {
	cells, pipes := splitRow(p.line[p.offset:])
	c.node.Children = append(c.node.Children, p.row(p.start+p.offset, p.end, cells, pipes, false, c.columns))
}

// row is a row of columns cells, those missing left empty and those beyond
// dropped.
func (p *blockParser) row(start, end int, cells, pipes []Span, header bool, columns int) *Node {
	r := &Node{Kind: Row, Span: Span{start, end}, Header: header}
	for _, s := range pipes {
		r.Marks = append(r.Marks, Span{start + s.Start, start + s.End})
	}
	for i := range columns {
		cell := &Node{Kind: Cell, Span: Span{end, end}}
		if i < len(cells) {
			cell.Span = Span{start + cells[i].Start, start + cells[i].End}
			if cell.Start < cell.End {
				p.leaves = append(p.leaves, leaf{node: cell, lines: []segment{{start: cell.Start, end: cell.End}}, table: true})
			}
		}
		r.Children = append(r.Children, cell)
	}
	return r
}

// splitRow reads the cells of a row, trimmed, and its pipes. A pipe after a
// backslash belongs to its cell.
func splitRow(s string) (cells, pipes []Span) {
	i := 0
	if i < len(s) && s[i] == '|' {
		pipes = append(pipes, Span{0, 1})
		i = skipTableSpaces(s, 1)
	}
	for i < len(s) {
		j := i
		for j < len(s) && s[j] != '|' {
			if s[j] == '\\' && j+1 < len(s) && s[j+1] == '|' {
				j++
			}
			j++
		}
		a, b := i, j
		for a < b && isTableTrim(s[a]) {
			a++
		}
		for b > a && isTableTrim(s[b-1]) {
			b--
		}
		cells = append(cells, Span{a, b})
		if j == len(s) {
			break
		}
		pipes = append(pipes, Span{j, j + 1})
		i = skipTableSpaces(s, j+1)
	}
	return cells, pipes
}

// delimiterRow tells the row under a table's header: cells of hyphens, a
// colon at either end telling the alignment.
func delimiterRow(s string) bool {
	i := 0
	if s[0] == '|' {
		i++
	}
	for {
		i = skipTableSpaces(s, i)
		if i < len(s) && s[i] == ':' {
			i++
		}
		n := 0
		for i < len(s) && s[i] == '-' {
			i++
			n++
		}
		if n == 0 {
			return false
		}
		if i < len(s) && s[i] == ':' {
			i++
		}
		i = skipTableSpaces(s, i)
		if i == len(s) {
			return true
		}
		if s[i] != '|' {
			return false
		}
		if i = skipTableSpaces(s, i+1); i == len(s) {
			return true
		}
	}
}

func skipTableSpaces(s string, i int) int {
	for i < len(s) && (s[i] == ' ' || s[i] == '\t' || s[i] == '\v' || s[i] == '\f') {
		i++
	}
	return i
}

func isTableTrim(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}
