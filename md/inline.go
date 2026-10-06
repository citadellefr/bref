package md

import (
	"html"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// inl is an inline being parsed, in a list its siblings share, which
// emphasis and links take nodes out of.
type inl struct {
	n                  *Node
	parent, prev, next *inl
	first, last        *inl
}

func (p *inl) append(c *inl) {
	c.unlink()
	c.parent, c.prev = p, p.last
	if p.last != nil {
		p.last.next = c
	} else {
		p.first = c
	}
	p.last = c
}

func (c *inl) unlink() {
	if c.prev != nil {
		c.prev.next = c.next
	} else if c.parent != nil {
		c.parent.first = c.next
	}
	if c.next != nil {
		c.next.prev = c.prev
	} else if c.parent != nil {
		c.parent.last = c.prev
	}
	c.parent, c.prev, c.next = nil, nil, nil
}

func (c *inl) insertAfter(s *inl) {
	s.unlink()
	s.parent, s.prev, s.next = c.parent, c, c.next
	if c.next != nil {
		c.next.prev = s
	} else if c.parent != nil {
		c.parent.last = s
	}
	c.next = s
}

type delimiter struct {
	ch                byte
	count, orig       int
	node              *inl
	prev, next        *delimiter
	canOpen, canClose bool
}

type bracket struct {
	node         *inl
	prev         *bracket
	prevDelim    *delimiter
	index        int
	image        bool
	active       bool
	bracketAfter bool
}

// inlineParser reads the inlines of a leaf block. Its text is the content of
// the block, its lines joined by "\n" and trimmed; offsets in it map back to
// the source line by line.
type inlineParser struct {
	p      *blockParser
	text   string
	lines  []segment
	starts []int
	lo     int
	table  bool

	pos      int
	delims   *delimiter
	brackets *bracket

	// what searches found, for runs of openers not to search the rest of
	// the text each
	finds          map[string]found
	ticks          map[int][]int
	noMath, mathTo int
}

type found struct{ from, at int }

func newInlineParser(p *blockParser, lines []segment, table bool) *inlineParser {
	ip := &inlineParser{p: p, lines: lines, table: table, mathTo: -1}
	var b strings.Builder
	for i, l := range lines {
		if i > 0 {
			b.WriteByte('\n')
		}
		ip.starts = append(ip.starts, b.Len())
		for range l.pad {
			b.WriteByte(' ')
		}
		b.WriteString(p.src[l.start:l.end])
	}
	text := b.String()
	hi := len(text)
	for hi > 0 && isTrim(text[hi-1]) {
		hi--
	}
	for ip.lo < hi && isTrim(text[ip.lo]) {
		ip.lo++
	}
	ip.text = text[ip.lo:hi]
	return ip
}

func isTrim(c byte) bool { return c == ' ' || c == '\t' || c == '\n' || c == '\r' }

func (ip *inlineParser) ext(e extensions) bool { return ip.p.ext&e != 0 }

// src is the offset in the source of offset i of the text.
func (ip *inlineParser) src(i int) int {
	i += ip.lo
	k := sort.Search(len(ip.starts), func(k int) bool { return ip.starts[k] > i }) - 1
	l := ip.lines[k]
	if off := i - ip.starts[k] - l.pad; off >= 0 {
		return l.start + off
	}
	return l.start - 1
}

func (ip *inlineParser) span(a, b int) Span { return Span{ip.src(a), ip.src(b)} }

// marks are the spans of a to b of the text, line by line.
func (ip *inlineParser) marks(a, b int) []Span {
	var out []Span
	for a < b {
		e := b
		if nl := strings.IndexByte(ip.text[a:b], '\n'); nl >= 0 {
			e = a + nl
		}
		if e > a {
			out = append(out, ip.span(a, e))
		}
		a = e + 1
	}
	return out
}

// line is the index of the line holding offset i of the text.
func (ip *inlineParser) line(i int) int {
	return sort.Search(len(ip.starts), func(k int) bool { return ip.starts[k] > i+ip.lo }) - 1
}

func (ip *inlineParser) parse() []*Node {
	root := &inl{n: &Node{}}
	for ip.pos < len(ip.text) {
		ip.inline(root)
	}
	ip.processEmphasis(nil)
	nodes := children(root)
	if ip.ext(extAutolinks) {
		nodes = splitEmails(nodes)
	}
	for _, n := range nodes {
		n.Walk(func(n *Node) bool {
			if n.Kind == Text {
				n.Literal = literal(n.Literal)
			}
			return true
		})
	}
	return nodes
}

// children are the nodes of a list, adjacent texts merged.
func children(p *inl) []*Node {
	var out []*Node
	var run []string
	flush := func() {
		if len(run) > 1 {
			out[len(out)-1].Literal = strings.Join(run, "")
		}
		run = run[:0]
	}
	for c := p.first; c != nil; c = c.next {
		n := c.n
		if c.first != nil {
			n.Children = children(c)
		}
		if n.Kind == Text {
			if n.Literal == "" {
				continue
			}
			if k := len(out) - 1; k >= 0 && len(run) > 0 && out[k].End == n.Start {
				run = append(run, n.Literal)
				out[k].End = n.End
				continue
			}
		}
		flush()
		if n.Kind == Text {
			run = append(run, n.Literal)
		}
		out = append(out, n)
	}
	flush()
	return out
}

func (ip *inlineParser) add(p *inl, n *Node) *inl {
	c := &inl{n: n}
	p.append(c)
	return c
}

func (ip *inlineParser) addText(p *inl, a, b int) *inl {
	return ip.add(p, &Node{Kind: Text, Span: ip.span(a, b), Literal: ip.text[a:b]})
}

func literal(s string) string { return strings.ReplaceAll(s, "\x00", "\uFFFD") }

func (ip *inlineParser) inline(p *inl) {
	ok := false
	switch c := ip.text[ip.pos]; c {
	case '\n':
		ok = ip.newline(p)
	case '\\':
		ok = ip.backslash(p)
	case '`':
		ok = ip.backticks(p)
	case '*', '_':
		ok = ip.delim(c, p)
	case '~':
		ok = ip.ext(extStrike) && ip.delim(c, p)
	case '=':
		ok = ip.ext(extHighlight) && ip.delim(c, p)
	case '[':
		ok = ip.openBracket(p)
	case '!':
		ok = ip.bang(p)
	case ']':
		ok = ip.closeBracket(p)
	case '<':
		ok = ip.autolink(p) || ip.htmlTag(p)
	case '&':
		ok = ip.entity(p)
	case '$':
		ok = ip.ext(extMath) && ip.math(p)
	default:
		ok = ip.bareLink(p) || ip.str(p)
	}
	if !ok {
		_, n := utf8.DecodeRuneInString(ip.text[ip.pos:])
		ip.addText(p, ip.pos, ip.pos+n)
		ip.pos += n
	}
}

func (ip *inlineParser) special(c byte) bool {
	switch c {
	case '\n', '`', '[', ']', '\\', '!', '<', '&', '*', '_':
		return true
	case '~':
		return ip.ext(extStrike)
	case '=':
		return ip.ext(extHighlight)
	case '$':
		return ip.ext(extMath)
	}
	return false
}

func (ip *inlineParser) str(p *inl) bool {
	start := ip.pos
	i := start
	for i < len(ip.text) && !ip.special(ip.text[i]) && (i == start || !ip.linkAt(i)) {
		i++
	}
	if i == start {
		return false
	}
	ip.addText(p, start, i)
	ip.pos = i
	return true
}

func (ip *inlineParser) newline(p *inl) bool {
	at := ip.pos
	ip.pos++
	n := &Node{Kind: SoftBreak, Span: ip.span(at, at)}
	if l := p.last; l != nil && l.n.Kind == Text && strings.HasSuffix(l.n.Literal, " ") {
		trimmed := strings.TrimRight(l.n.Literal, " ")
		removed := len(l.n.Literal) - len(trimmed)
		l.n.Literal = trimmed
		l.n.End -= removed
		if removed >= 2 {
			n.Kind = HardBreak
			n.Span = Span{l.n.End, l.n.End + removed}
			n.Marks = []Span{n.Span}
		}
	}
	ip.add(p, n)
	for ip.pos < len(ip.text) && ip.text[ip.pos] == ' ' {
		ip.pos++
	}
	return true
}

func isEscapable(c byte) bool {
	return c >= '!' && c <= '/' || c >= ':' && c <= '@' || c >= '[' && c <= '`' || c >= '{' && c <= '~'
}

func (ip *inlineParser) backslash(p *inl) bool {
	at := ip.pos
	ip.pos++
	switch {
	case ip.pos < len(ip.text) && ip.text[ip.pos] == '\n':
		ip.pos++
		s := ip.span(at, at+1)
		ip.add(p, &Node{Kind: HardBreak, Span: s, Marks: []Span{s}})
	case ip.pos < len(ip.text) && isEscapable(ip.text[ip.pos]):
		ip.pos++
		ip.add(p, &Node{Kind: Escape, Span: ip.span(at, at+2), Marks: []Span{ip.span(at, at+1)}, Literal: ip.text[at+1 : at+2]})
	default:
		ip.addText(p, at, at+1)
	}
	return true
}

func (ip *inlineParser) backticks(p *inl) bool {
	start := ip.pos
	for ip.pos < len(ip.text) && ip.text[ip.pos] == '`' {
		ip.pos++
	}
	open := ip.pos
	n := open - start
	i := ip.closingTicks(n, open)
	if i < 0 {
		ip.addText(p, start, open)
		return true
	}
	j := i + n
	content := strings.ReplaceAll(ip.text[open:i], "\n", " ")
	if len(content) > 1 && content[0] == ' ' && content[len(content)-1] == ' ' && strings.Trim(content, " ") != "" {
		content = content[1 : len(content)-1]
	}
	if ip.table {
		content = strings.ReplaceAll(content, `\|`, "|")
	}
	ip.add(p, &Node{Kind: Code, Span: ip.span(start, j), Marks: []Span{ip.span(start, open), ip.span(i, j)}, Literal: literal(content)})
	ip.pos = j
	return true
}

// closingTicks is where the first run of n backticks from offset from
// starts, or -1.
func (ip *inlineParser) closingTicks(n, from int) int {
	if ip.ticks == nil {
		ip.ticks = map[int][]int{}
		for i := 0; i < len(ip.text); {
			if ip.text[i] != '`' {
				i++
				continue
			}
			j := i
			for j < len(ip.text) && ip.text[j] == '`' {
				j++
			}
			ip.ticks[j-i] = append(ip.ticks[j-i], i)
			i = j
		}
	}
	runs := ip.ticks[n]
	if k := sort.SearchInts(runs, from); k < len(runs) {
		return runs[k]
	}
	return -1
}

// find is where sub is first found from offset from, or -1; offsets only
// grow from one call to the next.
func (ip *inlineParser) find(sub string, from int) int {
	if f, ok := ip.finds[sub]; ok && from >= f.from && (f.at < 0 || f.at >= from) {
		return f.at
	}
	at := strings.Index(ip.text[from:], sub)
	if at >= 0 {
		at += from
	}
	if ip.finds == nil {
		ip.finds = map[string]found{}
	}
	ip.finds[sub] = found{from, at}
	return at
}

// runeBefore is the character before offset i, a newline at the start.
func (ip *inlineParser) runeBefore(i int) rune {
	if i == 0 {
		return '\n'
	}
	r, _ := utf8.DecodeLastRuneInString(ip.text[:i])
	return r
}

func (ip *inlineParser) runeAt(i int) rune {
	if i >= len(ip.text) {
		return '\n'
	}
	r, _ := utf8.DecodeRuneInString(ip.text[i:])
	return r
}

func isUnicodeSpace(r rune) bool {
	return r == '\t' || r == '\n' || r == '\f' || r == '\r' || unicode.Is(unicode.Zs, r)
}

func isPunct(r rune) bool {
	if r < 0x80 {
		return isEscapable(byte(r))
	}
	return unicode.IsPunct(r) || unicode.IsSymbol(r)
}

func (ip *inlineParser) delim(c byte, p *inl) bool {
	start := ip.pos
	for ip.pos < len(ip.text) && ip.text[ip.pos] == c {
		ip.pos++
	}
	n := ip.pos - start
	before, after := ip.runeBefore(start), ip.runeAt(ip.pos)
	afterSpace, afterPunct := isUnicodeSpace(after), isPunct(after)
	beforeSpace, beforePunct := isUnicodeSpace(before), isPunct(before)
	left := !afterSpace && (!afterPunct || beforeSpace || beforePunct)
	right := !beforeSpace && (!beforePunct || afterSpace || afterPunct)
	canOpen, canClose := left, right
	if c == '_' {
		canOpen = left && (!right || beforePunct)
		canClose = right && (!left || afterPunct)
	}
	node := ip.addText(p, start, ip.pos)
	push := canOpen || canClose
	switch c {
	case '~':
		push = push && n <= 2
	case '=':
		push = push && n == 2
	}
	if push {
		d := &delimiter{ch: c, count: n, orig: n, node: node, prev: ip.delims, canOpen: canOpen, canClose: canClose}
		if ip.delims != nil {
			ip.delims.next = d
		}
		ip.delims = d
	}
	return true
}

func (ip *inlineParser) removeDelim(d *delimiter) {
	if d.prev != nil {
		d.prev.next = d.next
	}
	if d.next == nil {
		ip.delims = d.prev
	} else {
		d.next.prev = d.prev
	}
}

func delimIndex(d *delimiter) int {
	i := 0
	switch d.ch {
	case '_':
		i = 1
	case '~':
		i = 2
	case '=':
		i = 3
	}
	if d.canOpen {
		i += 4
	}
	return i*3 + d.orig%3
}

// processEmphasis pairs the delimiters above bottom, as CommonMark asks.
func (ip *inlineParser) processEmphasis(bottom *delimiter) {
	var openersBottom [24]*delimiter
	for i := range openersBottom {
		openersBottom[i] = bottom
	}
	closer := ip.delims
	for closer != nil && closer.prev != bottom {
		closer = closer.prev
	}
	for closer != nil {
		if !closer.canClose {
			closer = closer.next
			continue
		}
		idx := delimIndex(closer)
		opener := closer.prev
		found := false
		for opener != nil && opener != bottom && opener != openersBottom[idx] {
			odd := (closer.canOpen || opener.canClose) && closer.orig%3 != 0 && (opener.orig+closer.orig)%3 == 0
			if opener.ch == closer.ch && opener.canOpen && !odd {
				found = true
				break
			}
			opener = opener.prev
		}
		old := closer
		switch {
		case !found:
			closer = closer.next
		case closer.ch == '*' || closer.ch == '_':
			use := 1
			if closer.count >= 2 && opener.count >= 2 {
				use = 2
			}
			oi, ci := opener.node, closer.node
			opener.count -= use
			closer.count -= use
			oi.n.Literal = oi.n.Literal[:len(oi.n.Literal)-use]
			oi.n.End -= use
			ci.n.Literal = ci.n.Literal[use:]
			ci.n.Start += use
			kind := Emphasis
			if use == 2 {
				kind = Strong
			}
			emph := &inl{n: &Node{Kind: kind, Span: Span{oi.n.End, ci.n.Start}, Marks: []Span{{oi.n.End, oi.n.End + use}, {ci.n.Start - use, ci.n.Start}}}}
			for t := oi.next; t != nil && t != ci; {
				next := t.next
				emph.append(t)
				t = next
			}
			oi.insertAfter(emph)
			if opener.next != closer {
				opener.next, closer.prev = closer, opener
			}
			if opener.count == 0 {
				oi.unlink()
				ip.removeDelim(opener)
			}
			if closer.count == 0 {
				ci.unlink()
				next := closer.next
				ip.removeDelim(closer)
				closer = next
			}
		default:
			next := closer.next
			if opener.count == closer.count {
				oi, ci := opener.node, closer.node
				kind := Strike
				if closer.ch == '=' {
					kind = Highlight
				}
				n := &inl{n: &Node{Kind: kind, Span: Span{oi.n.Start, ci.n.End}, Marks: []Span{oi.n.Span, ci.n.Span}}}
				for t := oi.next; t != nil && t != ci; {
					next := t.next
					n.append(t)
					t = next
				}
				oi.insertAfter(n)
				oi.unlink()
				ci.unlink()
			}
			for d := closer; d != nil && d != opener; {
				prev := d.prev
				ip.removeDelim(d)
				d = prev
			}
			ip.removeDelim(opener)
			closer = next
		}
		if !found {
			openersBottom[idx] = old.prev
			if !old.canOpen {
				ip.removeDelim(old)
			}
		}
	}
	for ip.delims != nil && ip.delims != bottom {
		ip.removeDelim(ip.delims)
	}
}

func (ip *inlineParser) addBracket(node *inl, index int, image bool) {
	if ip.brackets != nil {
		ip.brackets.bracketAfter = true
	}
	ip.brackets = &bracket{node: node, prev: ip.brackets, prevDelim: ip.delims, index: index, image: image, active: true}
}

func (ip *inlineParser) openBracket(p *inl) bool {
	start := ip.pos
	if ip.ext(extFootnotes) && ip.footnote(p, start) {
		return true
	}
	if ip.ext(extWiki) && ip.wiki(p, start, false) {
		return true
	}
	ip.pos++
	ip.addBracket(ip.addText(p, start, start+1), start, false)
	return true
}

func (ip *inlineParser) bang(p *inl) bool {
	start := ip.pos
	if start+1 >= len(ip.text) || ip.text[start+1] != '[' {
		ip.pos++
		ip.addText(p, start, start+1)
		return true
	}
	if ip.ext(extWiki) && ip.wiki(p, start, true) {
		return true
	}
	ip.pos += 2
	ip.addBracket(ip.addText(p, start, start+2), start+1, true)
	return true
}

// footnote reads [^label], a reference to a footnote that is defined.
func (ip *inlineParser) footnote(p *inl, start int) bool {
	if !strings.HasPrefix(ip.text[start:], "[^") {
		return false
	}
	end := strings.IndexByte(ip.text[start:], ']')
	if end < 0 {
		return false
	}
	label := ip.text[start+2 : start+end]
	if !noteLabel(label) || ip.p.notes[noteKey(label)] == nil {
		return false
	}
	end += start + 1
	ip.add(p, &Node{Kind: FootnoteRef, Span: ip.span(start, end), Label: label})
	ip.pos = end
	return true
}

// wiki reads [[dest]], [[dest|text]] and their ![[…]] embeds, on one line.
func (ip *inlineParser) wiki(p *inl, start int, image bool) bool {
	from := start + 2
	if image {
		from++
	}
	if !strings.HasPrefix(ip.text[from-2:], "[[") {
		return false
	}
	end := ip.find("]]", from)
	if end < 0 {
		return false
	}
	inner := ip.text[from:end]
	if strings.ContainsAny(inner, "[]\n") || isBlank(inner) {
		return false
	}
	target, textFrom, textTo := inner, from, end
	marks := []Span{ip.span(start, from), ip.span(end, end+2)}
	if bar := strings.IndexByte(inner, '|'); bar >= 0 {
		target = inner[:bar]
		if isBlank(inner[bar+1:]) {
			textTo = from + bar
			marks[1] = ip.span(from+bar, end+2)
		} else {
			textFrom = from + bar + 1
			marks[0] = ip.span(start, textFrom)
		}
	}
	kind := Link
	if image {
		kind = Image
	}
	link := &inl{n: &Node{Kind: kind, Form: LinkWiki, Span: ip.span(start, end+2), Marks: marks, Dest: strings.TrimSpace(target), URL: ip.span(from, from+len(target))}}
	link.append(&inl{n: &Node{Kind: Text, Span: ip.span(textFrom, textTo), Literal: ip.text[textFrom:textTo]}})
	p.append(link)
	if !image {
		ip.deactivateLinks()
	}
	ip.pos = end + 2
	return true
}

func (ip *inlineParser) deactivateLinks() {
	for b := ip.brackets; b != nil; b = b.prev {
		if !b.image {
			b.active = false
		}
	}
}

func (ip *inlineParser) closeBracket(p *inl) bool {
	closeAt := ip.pos
	ip.pos++
	after := ip.pos
	opener := ip.brackets
	if opener == nil {
		ip.addText(p, closeAt, after)
		return true
	}
	if !opener.active {
		ip.addText(p, closeAt, after)
		ip.brackets = opener.prev
		return true
	}
	link := &Node{Kind: Link}
	if opener.image {
		link.Kind = Image
	}
	matched := false
	if ip.pos < len(ip.text) && ip.text[ip.pos] == '(' {
		ip.pos++
		ip.spnl()
		if dest, ds, de, ok := ip.linkDestination(); ok {
			ip.spnl()
			title, hasTitle := "", false
			if isWhitespace(ip.text[ip.pos-1]) {
				title, hasTitle = ip.linkTitle()
			}
			ip.spnl()
			if ip.pos < len(ip.text) && ip.text[ip.pos] == ')' {
				ip.pos++
				matched = true
				link.Dest, link.URL = dest, ip.span(ds, de)
				if hasTitle {
					link.Title = title
				}
			}
		}
		if !matched {
			ip.pos = after
		}
	}
	if !matched {
		before := ip.pos
		n := ip.linkLabel()
		ref := ""
		if n > 2 {
			ref = ip.text[before : before+n]
		} else if !opener.bracketAfter {
			ref = ip.text[opener.index:after]
		}
		if n == 0 {
			ip.pos = after
		}
		if ref != "" {
			if def := ip.p.refs[normalizeLabel(ref)]; def != nil {
				matched = true
				link.Form, link.Label = LinkReference, ref[1:len(ref)-1]
				link.Dest, link.Title = def.Dest, def.Title
			}
		}
	}
	if !matched {
		ip.brackets = opener.prev
		ip.pos = after
		ip.addText(p, closeAt, after)
		return true
	}
	link.Span = Span{opener.node.n.Start, ip.src(ip.pos)}
	link.Marks = append([]Span{opener.node.n.Span}, ip.marks(closeAt, ip.pos)...)
	l := &inl{n: link}
	for t := opener.node.next; t != nil; {
		next := t.next
		l.append(t)
		t = next
	}
	p.append(l)
	ip.processEmphasis(opener.prevDelim)
	ip.brackets = opener.prev
	opener.node.unlink()
	if !opener.image {
		ip.deactivateLinks()
	}
	return true
}

func isWhitespace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r'
}

// spnl skips spaces, a newline and spaces.
func (ip *inlineParser) spnl() {
	for ip.pos < len(ip.text) && ip.text[ip.pos] == ' ' {
		ip.pos++
	}
	if ip.pos < len(ip.text) && ip.text[ip.pos] == '\n' {
		ip.pos++
		for ip.pos < len(ip.text) && ip.text[ip.pos] == ' ' {
			ip.pos++
		}
	}
}

// linkDestination reads a destination: what it says, and where it is
// written.
func (ip *inlineParser) linkDestination() (string, int, int, bool) {
	t := ip.text
	start := ip.pos
	if start < len(t) && t[start] == '<' {
		for i := start + 1; i < len(t); i++ {
			switch t[i] {
			case '\\':
				if i+1 < len(t) && t[i+1] != '\n' {
					i++
				} else {
					return "", 0, 0, false
				}
			case '>':
				ip.pos = i + 1
				return unescape(t[start+1 : i]), start + 1, i, true
			case '<', '\n':
				return "", 0, 0, false
			}
		}
		return "", 0, 0, false
	}
	parens := 0
	i := start
loop:
	for i < len(t) {
		switch c := t[i]; {
		case c == '\\' && i+1 < len(t) && isEscapable(t[i+1]):
			i += 2
		case c == '(':
			if parens++; parens > 32 {
				return "", 0, 0, false
			}
			i++
		case c == ')':
			if parens < 1 {
				break loop
			}
			i++
			parens--
		case isWhitespace(c):
			break loop
		default:
			i++
		}
	}
	if i == start && (i >= len(t) || t[i] != ')') || parens != 0 {
		return "", 0, 0, false
	}
	ip.pos = i
	return unescape(t[start:i]), start, i, true
}

func (ip *inlineParser) linkTitle() (string, bool) {
	t := ip.text
	if ip.pos >= len(t) {
		return "", false
	}
	open := t[ip.pos]
	end := open
	switch open {
	case '(':
		end = ')'
	case '"', '\'':
	default:
		return "", false
	}
	for i := ip.pos + 1; i < len(t); i++ {
		switch c := t[i]; {
		case c == '\\' && i+1 < len(t):
			i++
		case c == end:
			title := t[ip.pos+1 : i]
			ip.pos = i + 1
			return unescape(title), true
		case c == '(' && open == '(', c == 0:
			return "", false
		}
	}
	return "", false
}

// linkLabel reads [label] and answers its length, or 0.
func (ip *inlineParser) linkLabel() int {
	t := ip.text
	start := ip.pos
	if start >= len(t) || t[start] != '[' {
		return 0
	}
	n := 0
	for i := start + 1; i < len(t); i++ {
		switch t[i] {
		case '\\':
			if i+1 < len(t) {
				_, w := utf8.DecodeRuneInString(t[i+1:])
				i += w
			}
		case '[':
			return 0
		case ']':
			if n > 999 {
				return 0
			}
			ip.pos = i + 1
			return i + 1 - start
		default:
			_, w := utf8.DecodeRuneInString(t[i:])
			i += w - 1
		}
		n++
	}
	return 0
}

// normalizeLabel is how labels are compared: without their brackets,
// trimmed, their spaces collapsed and their case folded.
func normalizeLabel(s string) string {
	s = strings.Join(strings.FieldsFunc(s[1:len(s)-1], func(r rune) bool {
		return r == ' ' || r == '\t' || r == '\n' || r == '\r'
	}), " ")
	var b strings.Builder
	for _, r := range s {
		switch r = unicode.ToLower(r); r {
		case 'ı':
			b.WriteRune(r)
		case 'ß':
			b.WriteString("SS")
		default:
			b.WriteRune(unicode.ToUpper(r))
		}
	}
	return b.String()
}

// definition reads the link reference definition at the position, which
// it moves past, or answers nil.
func (ip *inlineParser) definition() *Node {
	start := ip.pos
	n := ip.linkLabel()
	if n == 0 || ip.pos >= len(ip.text) || ip.text[ip.pos] != ':' {
		ip.pos = start
		return nil
	}
	label := ip.text[start : start+n]
	ip.pos++
	ip.spnl()
	dest, ds, de, ok := ip.linkDestination()
	if !ok {
		ip.pos = start
		return nil
	}
	beforeTitle := ip.pos
	ip.spnl()
	title, hasTitle := "", false
	if ip.pos != beforeTitle {
		title, hasTitle = ip.linkTitle()
	}
	if !hasTitle {
		ip.pos = beforeTitle
	}
	if !ip.lineEnd() {
		if !hasTitle {
			ip.pos = start
			return nil
		}
		title, hasTitle = "", false
		ip.pos = beforeTitle
		if !ip.lineEnd() {
			ip.pos = start
			return nil
		}
	}
	key := normalizeLabel(label)
	if key == "" {
		ip.pos = start
		return nil
	}
	end := ip.pos
	if ip.text[end-1] == '\n' {
		end--
	}
	def := &Node{Kind: Definition, Span: ip.span(start, end), Marks: ip.marks(start, start+n+1), Label: label[1 : len(label)-1], Dest: dest, Title: title, URL: ip.span(ds, de)}
	if _, ok := ip.p.refs[key]; !ok {
		ip.p.refs[key] = def
	}
	return def
}

// lineEnd skips spaces up to the end of the line, and past it.
func (ip *inlineParser) lineEnd() bool {
	i := ip.pos
	for i < len(ip.text) && ip.text[i] == ' ' {
		i++
	}
	if i < len(ip.text) && ip.text[i] != '\n' {
		return false
	}
	if i < len(ip.text) {
		i++
	}
	ip.pos = i
	return true
}

var (
	emailAutolink = regexp.MustCompile("^<([a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>")
	uriAutolink   = regexp.MustCompile(`^<[A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\x00-\x20]*>`)
	htmlTag       = regexp.MustCompile(htmlTagRegex)
	entityRef     = regexp.MustCompile(`^&(?:#[xX][a-fA-F0-9]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});`)
	escapeOrRef   = regexp.MustCompile("\\\\[!\"#$%&'()*+,./:;<=>?@[\\\\\\]^_`{|}~-]|&(?:#[xX][a-fA-F0-9]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});")
)

func (ip *inlineParser) autolink(p *inl) bool {
	rest := ip.text[ip.pos:]
	mail := true
	m := emailAutolink.FindStringIndex(rest)
	if m == nil {
		mail = false
		if m = uriAutolink.FindStringIndex(rest); m == nil {
			return false
		}
	}
	start, end := ip.pos, ip.pos+m[1]
	dest := ip.text[start+1 : end-1]
	link := &inl{n: &Node{Kind: Link, Form: LinkAngle, Span: ip.span(start, end), Marks: []Span{ip.span(start, start+1), ip.span(end-1, end)}, Dest: dest, URL: ip.span(start+1, end-1)}}
	if mail {
		link.n.Dest = "mailto:" + dest
	}
	link.append(&inl{n: &Node{Kind: Text, Span: ip.span(start+1, end-1), Literal: dest}})
	p.append(link)
	ip.pos = end
	return true
}

func (ip *inlineParser) htmlTag(p *inl) bool {
	t := ip.text[ip.pos:]
	end := -1
	closing := func(sub string, from int) {
		if i := ip.find(sub, ip.pos+from); i >= 0 {
			end = i + len(sub)
		}
	}
	switch {
	case strings.HasPrefix(t, "<!-->"):
		end = ip.pos + 5
	case strings.HasPrefix(t, "<!--->"):
		end = ip.pos + 6
	case strings.HasPrefix(t, "<!--"):
		closing("-->", 4)
	case strings.HasPrefix(t, "<?"):
		closing("?>", 2)
	case strings.HasPrefix(t, "<![CDATA["):
		closing("]]>", 9)
	case len(t) > 2 && t[1] == '!' && isAlpha(t[2]):
		closing(">", 2)
	default:
		if m := htmlTag.FindStringIndex(t); m != nil {
			end = ip.pos + m[1]
		}
	}
	if end < 0 {
		return false
	}
	ip.add(p, &Node{Kind: InlineHTML, Span: ip.span(ip.pos, end), Literal: literal(ip.text[ip.pos:end])})
	ip.pos = end
	return true
}

func (ip *inlineParser) entity(p *inl) bool {
	m := entityRef.FindStringIndex(ip.text[ip.pos:])
	if m == nil {
		return false
	}
	value, ok := decodeEntity(ip.text[ip.pos : ip.pos+m[1]])
	if !ok {
		return false
	}
	ip.add(p, &Node{Kind: Entity, Span: ip.span(ip.pos, ip.pos+m[1]), Literal: value})
	ip.pos += m[1]
	return true
}

// decodeEntity is the character an entity stands for: unknown names are no
// entity, and invalid numbers stand for U+FFFD.
func decodeEntity(s string) (string, bool) {
	if s[1] == '#' {
		var n uint64
		var err error
		if s[2] == 'x' || s[2] == 'X' {
			n, err = strconv.ParseUint(s[3:len(s)-1], 16, 32)
		} else {
			n, err = strconv.ParseUint(s[2:len(s)-1], 10, 32)
		}
		if err != nil || n == 0 || n > unicode.MaxRune || (n >= 0xD800 && n <= 0xDFFF) {
			return "�", true
		}
		return string(rune(n)), true
	}
	v := html.UnescapeString(s)
	if v == s || (strings.HasSuffix(v, ";") && v != ";") {
		return "", false
	}
	return v, true
}

// unescape decodes the backslash escapes and entities of a destination, a
// title or an info string.
func unescape(s string) string {
	if !strings.ContainsAny(s, `\&`) {
		return s
	}
	return escapeOrRef.ReplaceAllStringFunc(s, func(m string) string {
		if m[0] == '\\' {
			return m[1:]
		}
		if v, ok := decodeEntity(m); ok {
			return v
		}
		return m
	})
}

// math reads $math$, whose dollars hug it, and $$math$$, on one line.
func (ip *inlineParser) math(p *inl) bool {
	t := ip.text
	start := ip.pos
	n := 0
	for start+n < len(t) && t[start+n] == '$' {
		n++
	}
	if n > 2 {
		ip.addText(p, start, start+n)
		ip.pos += n
		return true
	}
	from := start + n
	lineEnd := len(t)
	if nl := strings.IndexByte(t[from:], '\n'); nl >= 0 {
		lineEnd = from + nl
	}
	end := -1
	if n == 1 {
		if from >= lineEnd || t[from] == ' ' || t[from] == '\t' || from >= ip.noMath && from < ip.mathTo {
			return false
		}
		for j := from + 1; j < lineEnd; j++ {
			if t[j] == '\\' {
				j++
				continue
			}
			if t[j] == '$' && t[j-1] != ' ' && t[j-1] != '\t' && (j+1 >= len(t) || t[j+1] < '0' || t[j+1] > '9') {
				end = j
				break
			}
		}
		if end < 0 {
			ip.noMath, ip.mathTo = from, lineEnd
		}
	} else if i := ip.find("$$", from); i >= 0 && i < lineEnd && !isBlank(t[from:i]) {
		end = i
	}
	if end < 0 {
		return false
	}
	ip.add(p, &Node{Kind: Math, Display: n == 2, Span: ip.span(start, end+n), Marks: []Span{ip.span(start, from), ip.span(end, end+n)}, Literal: literal(t[from:end])})
	ip.pos = end + n
	return true
}
