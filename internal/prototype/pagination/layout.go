package pagination

import (
	"math"
	"unicode"
)

// Options are the rules whose Word behavior the prototype measures.
type Options struct {
	// SuppressBeforeAtTop drops the space before a paragraph that a natural
	// page break brings to the top of a page.
	SuppressBeforeAtTop bool
	// Round rounds every line height up to a multiple of this, in pt.
	Round float64
	// Borders makes the borders of table cells take room in their row.
	Borders bool
	// Sync starts every page where Word started it, so that one difference
	// does not shift all the pages after it.
	Sync bool
}

var DefaultOptions = Options{SuppressBeforeAtTop: true, Borders: true}

// Pos is where a page starts: a body paragraph and a character offset in
// it, or a table row.
type Pos struct {
	Para, Offset int
	Row          int // -1 outside tables
}

type Result struct {
	Pages  int
	Breaks []Pos
	// Flow counts Word's page breaks that the flow of text caused, and Kept
	// those we made at the same place, on a page started at Word's previous
	// break.
	Flow, Kept int
}

// line is a laid out line of a paragraph.
type line struct {
	height    float64
	start     int // character offset of its first item
	pageBreak bool
}

type cell struct {
	width, height float64
	space         bool
	breakAfter    bool
	kind          ItemKind
	offset        int
	tab           bool
}

func Paginate(d *Doc, o Options) Result {
	e := &engine{doc: d, opt: o, rowOf: map[int]int{}}
	e.indexRows(d.Body, -1)
	e.word = wordBreaks(d, e.key)
	e.seen = map[Pos]bool{}
	e.clean = true
	e.run()
	return Result{Pages: e.page, Breaks: e.breaks, Flow: len(e.word) - e.hard, Kept: e.kept}
}

type engine struct {
	doc *Doc
	opt Options

	sec       *Section
	page      int
	pageInSec int
	y, height float64
	atTop     bool
	natural   bool
	prev      *Para // the paragraph just placed, nil after a table or at the top of a page
	started   bool  // whether anything was placed yet
	breaks    []Pos
	rowOf     map[int]int // paragraph index → outermost table row
	rows      int
	pending   bool
	forcing   bool

	word  map[Pos]bool // Word's page breaks, by key
	seen  map[Pos]bool
	clean bool // no break of ours since Word's last one
	hard  int  // Word's breaks that are page breaks of the document
	kept  int
}

// key identifies a page break: a table row, whatever the cell and line it
// splits at, else a paragraph and offset.
func (e *engine) key(p Pos) Pos {
	if row, ok := e.rowOf[p.Para]; ok {
		return Pos{Row: row}
	}
	return Pos{Para: p.Para, Offset: p.Offset, Row: -1}
}

// account scores a page break, counting each of Word's once.
func (e *engine) account(at Pos, natural, forced bool) {
	k := e.key(at)
	switch {
	case !e.word[k]:
		if natural {
			e.clean = false
		}
		return
	case e.seen[k]:
	case !natural:
		e.hard++
	case e.clean && !forced:
		e.kept++
	}
	e.seen[k] = true
	e.clean = true
}

// force starts a new page where Word started one, if Sync asks for it.
func (e *engine) force(at Pos) bool {
	if !e.opt.Sync || e.atTop || !e.word[e.key(at)] {
		return false
	}
	e.forcing = true
	e.newPage(&at, true)
	e.forcing = false
	e.account(at, true, true)
	return true
}

// indexRows numbers the rows of the top level tables and maps every
// paragraph inside to its row.
func (e *engine) indexRows(blocks []Block, row int) {
	for _, b := range blocks {
		switch b := b.(type) {
		case *Para:
			if row >= 0 {
				e.rowOf[b.Index] = row
			}
		case *Table:
			for _, r := range b.Rows {
				id := row
				if row < 0 {
					id = e.rows
					e.rows++
				}
				for _, c := range r.Cells {
					e.indexRows(c.Blocks, id)
				}
			}
		}
	}
}

func (e *engine) run() {
	sections := make([]*Section, len(e.doc.Body))
	sec := e.doc.Final
	for i := len(e.doc.Body) - 1; i >= 0; i-- {
		if p, ok := e.doc.Body[i].(*Para); ok && p.Section != nil {
			sec = p.Section
		}
		sections[i] = sec
	}
	for i, b := range e.doc.Body {
		if i == 0 || sections[i] != sections[i-1] {
			e.startSection(sections[i], i > 0)
		}
		switch b := b.(type) {
		case *Para:
			e.para(b, i)
		case *Table:
			e.table(b)
		}
	}
	if e.page == 0 {
		e.page = 1
	}
}

func (e *engine) startSection(s *Section, after bool) {
	e.sec = s
	if !after {
		e.newPage(nil, false)
		return
	}
	switch s.Type {
	case "continuous":
		e.updateHeight()
		return
	case "evenPage", "oddPage":
		if (e.page%2 == 0) == (s.Type == "evenPage") {
			e.page++
		}
	}
	e.pageInSec = 0
	if !e.pending {
		e.newPage(nil, false)
	}
}

// newPage starts a page at a position; a natural break is one that the
// flow of text caused, not a page break of the document.
// A nil position leaves it to the next block to record where the page starts.
func (e *engine) newPage(at *Pos, natural bool) {
	e.page++
	e.pageInSec++
	if e.page > 1 {
		if at != nil {
			e.breaks = append(e.breaks, *at)
		} else {
			e.pending = true
		}
	}
	if at != nil && !e.forcing {
		e.account(*at, natural, false)
	}
	e.y = 0
	e.atTop = true
	e.natural = natural
	e.prev = nil
	e.updateHeight()
}

// updateHeight is the height of the body on the current page: a header or
// footer taller than its margin pushes the body back.
func (e *engine) updateHeight() {
	s := e.sec
	header, footer := s.Header, s.Footer
	if s.TitlePage && e.pageInSec == 1 {
		header, footer = s.FirstHeader, s.FirstFooter
	}
	width := s.Width - s.Left - s.Right
	top := max(s.Top, s.HeaderDist+e.blocksHeight(header, width))
	bottom := max(s.Bottom, s.FooterDist+e.blocksHeight(footer, width))
	e.height = s.Height - top - bottom
}

// blocksHeight is the height of blocks laid out in one piece.
func (e *engine) blocksHeight(blocks []Block, width float64) float64 {
	h, after := 0.0, 0.0
	for _, b := range blocks {
		switch b := b.(type) {
		case *Para:
			h += after + b.Props.Before
			for _, l := range e.lines(b, width) {
				h += l.height
			}
			after = b.Props.After
		case *Table:
			h += after
			after = 0
			for _, r := range b.Rows {
				h += e.rowHeight(r)
			}
		}
	}
	return h + after
}

func (e *engine) textWidth() float64 {
	return e.sec.Width - e.sec.Left - e.sec.Right
}

// spacing is the space above a paragraph where it is placed.
func (e *engine) spacing(p *Para) float64 {
	switch {
	case !e.started && p.Props.AutoBefore:
		return 0
	case e.atTop && e.natural && e.opt.SuppressBeforeAtTop:
		return 0
	}
	return gap(e.prev, p)
}

// gap is the space between two paragraphs: the space after the first plus
// the space before the second, which Word adds up, unless contextual spacing
// drops them, or both are HTML auto spacing, which collapses. A nil prev
// stands for a table or the top of a page.
func gap(prev, p *Para) float64 {
	if prev == nil {
		return p.Props.Before
	}
	after, before := prev.Props.After, p.Props.Before
	if prev.Style == p.Style {
		if p.Props.Contextual {
			before = 0
		}
		if prev.Props.Contextual {
			after = 0
		}
	}
	if prev.Props.AutoAfter && p.Props.AutoBefore {
		return max(after, before)
	}
	return after + before
}

func (e *engine) para(p *Para, index int) {
	lines := e.lines(p, e.textWidth())
	start := Pos{Para: p.Index, Row: -1}
	e.startBlock(start)
	if p.Props.BreakBefore && !e.atTop {
		e.newPage(&start, false)
	}
	if !e.atTop {
		need := e.keepHeight(index, lines)
		if e.y+need > e.height && need <= e.height {
			e.newPage(&start, true)
		}
	}
	e.force(start)
	space := e.spacing(p)
	for i := 0; i < len(lines); {
		n := 0
		for y := e.y + space; i+n < len(lines) && y+lines[i+n].height <= e.height+0.01; n++ {
			y += lines[i+n].height
			if lines[i+n].pageBreak {
				n++
				break
			}
		}
		hard := n > 0 && lines[i+n-1].pageBreak
		if !hard && i+n < len(lines) {
			n = e.keep(p, len(lines), i, n)
		}
		if n == 0 && e.atTop {
			n = 1
		}
		forced := false
		for j := i + 1; j < i+n && e.opt.Sync; j++ {
			if e.word[e.key(Pos{Para: p.Index, Offset: lines[j].start})] {
				n, forced = j-i, true
				break
			}
		}
		for k := i; k < i+n; k++ {
			e.y += lines[k].height
		}
		if n > 0 {
			e.y += space
			e.atTop = false
			space = 0
		}
		i += n
		switch {
		case hard && i < len(lines):
			e.newPage(&Pos{Para: p.Index, Offset: lines[i].start, Row: -1}, false)
		case hard:
			e.newPage(nil, false)
		case i < len(lines):
			at := Pos{Para: p.Index, Offset: lines[i].start, Row: -1}
			e.forcing = forced
			e.newPage(&at, true)
			e.forcing = false
			if forced {
				e.account(at, true, true)
			}
			if i == 0 {
				space = e.spacing(p)
			}
		}
	}
	e.prev = p
	e.started = true
}

// keep applies widow and orphan control and "keep lines together" to a
// paragraph that breaks after its line i+n-1.
func (e *engine) keep(p *Para, total, i, n int) int {
	if p.Props.KeepLines && i == 0 {
		return 0
	}
	if p.Props.Widow && total > 1 {
		if total-(i+n) == 1 && n > 0 {
			n--
		}
		if i == 0 && n == 1 {
			n = 0
		}
	}
	return n
}

// startBlock records where the page starts when the previous block ended it
// without knowing what comes next.
func (e *engine) startBlock(at Pos) {
	if e.pending {
		e.breaks = append(e.breaks, at)
		e.pending = false
		e.account(at, false, false)
	}
}

// keepHeight is how much of the page a paragraph needs so that it starts on
// it: the paragraph and those kept with it, then the first lines of the next.
func (e *engine) keepHeight(index int, lines []line) float64 {
	body := e.doc.Body
	p := body[index].(*Para)
	need := e.spacing(p)
	first := func(p *Para, lines []line) float64 {
		n := 1
		if p.Props.KeepLines {
			n = len(lines)
		} else if p.Props.Widow && len(lines) > 1 {
			n = 2
		}
		h := 0.0
		for _, l := range lines[:min(n, len(lines))] {
			h += l.height
		}
		return h
	}
	if !p.Props.KeepNext {
		return need + first(p, lines)
	}
	for j := index; j < len(body); j++ {
		switch b := body[j].(type) {
		case *Para:
			ls := lines
			if j > index {
				ls = e.lines(b, e.textWidth())
				need += b.Props.Before
			}
			if !b.Props.KeepNext || j+1 == len(body) || b.Section != nil {
				return need + first(b, ls)
			}
			for _, l := range ls {
				need += l.height
			}
			need += b.Props.After
		case *Table:
			if len(b.Rows) > 0 {
				need += e.rowHeight(b.Rows[0])
			}
			return need
		}
	}
	return need
}

// lines breaks a paragraph into lines.
func (e *engine) lines(p *Para, width float64) []line {
	props := p.Props
	cells := e.cells(p)
	var out []line
	markHeight := e.runHeight(p.Mark)
	start := 0
	for start < len(cells) || len(out) == 0 {
		left := props.Left
		if len(out) == 0 {
			left += props.First
		}
		right := width - props.Right
		x := left
		end, lastBreak := start, -1
		h := 0.0
		stop := false
		for end < len(cells) && !stop {
			c := &cells[end]
			w := c.width
			if c.tab {
				w = e.tabStop(x, props) - x
				if x+w > right && end > start {
					break
				}
			}
			switch {
			case c.kind == LineBreak || c.kind == PageBreak || c.kind == ColumnBreak:
				h = max(h, c.height)
				end++
				stop = true
				continue
			case c.space:
			case x+w > right+0.001 && end > start:
				if lastBreak >= start {
					end = lastBreak + 1
				}
				stop = true
				continue
			}
			x += w
			h = max(h, c.height)
			if c.breakAfter {
				lastBreak = end
			}
			end++
		}
		if stop && end > start && lastBreak >= start && end == lastBreak+1 {
			h = 0
			for k := start; k < end; k++ {
				h = max(h, cells[k].height)
			}
		}
		l := line{start: 0, height: h}
		if start < len(cells) {
			l.start = cells[start].offset
		}
		if end > start && (cells[end-1].kind == PageBreak || cells[end-1].kind == ColumnBreak) {
			l.pageBreak = true
		}
		if end >= len(cells) {
			l.height = max(l.height, markHeight)
		}
		if l.height == 0 {
			l.height = markHeight
		}
		l.height = e.lineSpacing(l.height, props)
		out = append(out, l)
		if end == start {
			break
		}
		start = end
	}
	return out
}

// cells measures the characters of a paragraph and marks where a line may
// break: after spaces, hyphens and dashes, and around ideographs.
func (e *engine) cells(p *Para) []cell {
	var out []cell
	offset := 0
	for _, it := range p.Items {
		switch it.Kind {
		case TextItem:
			size := it.Run.Size
			h := e.runHeight(it.Run)
			for _, r := range it.Text {
				c := cell{kind: TextItem, height: h, offset: offset}
				c.width = it.Run.Font.Advance(r)*size + it.Run.Spacing
				switch {
				case r == ' ' || r == '　':
					c.space, c.breakAfter = true, true
				case r == '-' || r == '—' || r == '–' || r == '­':
					c.breakAfter = true
				case unicode.Is(unicode.Han, r) || unicode.Is(unicode.Hiragana, r) || unicode.Is(unicode.Katakana, r):
					c.breakAfter = true
					if len(out) > 0 {
						out[len(out)-1].breakAfter = true
					}
				}
				if r == '­' {
					c.width = 0
				}
				out = append(out, c)
				offset++
			}
			continue
		case TabItem:
			out = append(out, cell{kind: TabItem, tab: true, breakAfter: true, height: e.runHeight(it.Run), offset: offset})
		case ObjectItem:
			out = append(out, cell{kind: ObjectItem, width: it.W, height: it.H, breakAfter: true, offset: offset})
		default:
			h := 0.0
			if it.Run != nil {
				h = e.runHeight(it.Run)
			}
			out = append(out, cell{kind: it.Kind, height: h, offset: offset})
		}
		offset++
	}
	return out
}

func (e *engine) runHeight(r *RunStyle) float64 {
	return r.Font.LineHeight() * r.Size
}

func (e *engine) lineSpacing(natural float64, p paraProps) float64 {
	h := natural
	switch p.LineRule {
	case "exact":
		h = p.Line
	case "atLeast":
		h = max(natural, p.Line)
	default:
		h = natural * p.Line
	}
	if e.opt.Round > 0 {
		h = math.Ceil(h/e.opt.Round-1e-9) * e.opt.Round
	}
	return h
}

// tabStop is the next tab stop after x: a custom one, the hanging indent,
// or a default one.
func (e *engine) tabStop(x float64, p paraProps) float64 {
	for _, t := range p.Tabs {
		if t > x+0.01 {
			return t
		}
	}
	if p.First < 0 && p.Left > x+0.01 {
		return p.Left
	}
	d := e.doc.DefaultTab
	return (math.Floor(x/d+1e-6) + 1) * d
}

func (e *engine) table(t *Table) {
	e.prev = nil
	for _, r := range t.Rows {
		e.row(r)
	}
	e.prev = nil
	e.started = true
}

// cellSlices lays out the content of a cell as a pile of slices, each a line
// with the spacing above it, a page break being allowed between any two.
func (e *engine) cellSlices(c Cell) []float64 {
	var out []float64
	var prev *Para
	after := 0.0
	for i, b := range c.Blocks {
		switch b := b.(type) {
		case *Para:
			space := gap(prev, b)
			if i == 0 && b.Props.AutoBefore {
				space = 0
			}
			for k, l := range e.lines(b, c.Width) {
				h := l.height
				if k == 0 {
					h += space
				}
				out = append(out, h)
			}
			prev, after = b, b.Props.After
			if b.Props.AutoAfter && i == len(c.Blocks)-1 {
				after = 0
			}
		case *Table:
			h := after
			for _, r := range b.Rows {
				h += e.rowHeight(r)
			}
			out = append(out, h)
			prev, after = nil, 0
		}
	}
	if len(out) > 0 && prev != nil {
		out[len(out)-1] += after
	}
	return out
}

func (e *engine) rowHeight(r Row) float64 {
	h := 0.0
	for _, c := range r.Cells {
		if c.MergedFromAbove {
			continue
		}
		sum := e.cellFrame(c)
		for _, s := range e.cellSlices(c) {
			sum += s
		}
		h = max(h, sum)
	}
	return e.clampRow(h, r) + 2*r.Spacing
}

// cellFrame is the height a cell adds around its content: margins, and
// borders if they take room.
func (e *engine) cellFrame(c Cell) float64 {
	h := c.Top + c.Bottom
	if e.opt.Borders {
		h += c.BorderTop + c.BorderBottom
	}
	return h
}

func (e *engine) clampRow(h float64, r Row) float64 {
	if r.Height > 0 {
		if r.Exact {
			return r.Height
		}
		return max(h, r.Height)
	}
	return h
}

func (e *engine) row(r Row) {
	h := e.rowHeight(r)
	pos := e.rowStart(r)
	e.startBlock(pos)
	if e.y+h <= e.height+0.01 && !e.force(pos) || e.atTop && h <= e.height {
		e.y += h
		e.atTop = false
		return
	}
	if !e.atTop && (r.CantSplit || r.Exact || h <= e.height) {
		// Word moves a row that fits on a page rather than split it, unless
		// the row can split and most of it fits.
		if r.CantSplit || r.Exact || !e.splitWorthIt(r) {
			e.newPage(&pos, true)
			if h <= e.height {
				e.y += h
				e.atTop = false
				return
			}
		}
	}
	// split the row line by line across pages
	slices := make([][]float64, len(r.Cells))
	for i, c := range r.Cells {
		if !c.MergedFromAbove {
			slices[i] = e.cellSlices(c)
		}
	}
	margin := 2 * r.Spacing
	if len(r.Cells) > 0 {
		margin += e.cellFrame(r.Cells[0])
	}
	for {
		avail := e.height - e.y - margin
		used, done, moved := 0.0, true, false
		for i := range slices {
			sum, n := 0.0, 0
			for n < len(slices[i]) && sum+slices[i][n] <= avail+0.01 {
				sum += slices[i][n]
				n++
			}
			if n == 0 && len(slices[i]) > 0 && e.atTop {
				sum, n = slices[i][0], 1
			}
			if n > 0 {
				moved = true
			}
			slices[i] = slices[i][n:]
			if len(slices[i]) > 0 {
				done = false
			}
			used = max(used, sum)
		}
		e.y += used + margin
		e.atTop = false
		if done {
			return
		}
		if !moved && e.atTop {
			return
		}
		e.newPage(&pos, true)
	}
}

// splitWorthIt tells whether at least a line of every cell fits.
func (e *engine) splitWorthIt(r Row) bool {
	avail := e.height - e.y
	for _, c := range r.Cells {
		if c.MergedFromAbove {
			continue
		}
		s := e.cellSlices(c)
		if len(s) > 0 && s[0]+e.cellFrame(c) > avail {
			return false
		}
	}
	return true
}

func (e *engine) rowStart(r Row) Pos {
	for _, c := range r.Cells {
		for _, b := range c.Blocks {
			if p, ok := b.(*Para); ok {
				return Pos{Para: p.Index, Row: e.rowOf[p.Index]}
			}
		}
	}
	return Pos{Row: -1}
}
