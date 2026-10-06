package bref

import (
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"unicode/utf16"

	"github.com/citadellefr/trame"
	"github.com/citadellefr/trame/ot"
)

// What a note keeps beside its file, when its store is a trame.MetaStore: who
// wrote each character, and the threads of comments.
//
// A thread is a node of type Thread under the root, its messages the Msg
// nodes under it. The passage a thread is about carries the attribute
// "c." + the id of the thread, whose value is "1". A thread whose passage
// was deleted stays, without any.

const (
	Thread = "thread"
	Msg    = "msg"

	anchor     = "c."
	maxID      = 40
	maxMessage = 10000
)

var (
	errNoComments = errors.New("this note keeps no comments")
	errComment    = errors.New("comments take only their own text, and are written and deleted by their author")
)

// metaNote is the JSON a store keeps beside a note. Positions count UTF-16
// code units of the text of the document, final paragraph mark included.
type metaNote struct {
	Text    string       `json:"text"`
	By      []metaRun    `json:"by,omitempty"`
	Threads []metaThread `json:"threads,omitempty"`
}

type metaRun struct {
	From int    `json:"f"`
	To   int    `json:"t"`
	By   string `json:"b"`
}

type metaThread struct {
	ID     string        `json:"id"`
	Done   bool          `json:"done,omitempty"`
	Ranges [][2]int      `json:"at,omitempty"`
	Msgs   []metaMessage `json:"msgs"`
}

type metaMessage struct {
	ID   string `json:"id"`
	By   string `json:"by"`
	Name string `json:"name"`
	At   int64  `json:"at"`
	Text string `json:"text"`
}

func (n *note) ReadMeta(doc *ot.Tree, data []byte) error {
	n.kept = true
	if len(data) == 0 {
		return nil
	}
	var m metaNote
	if err := json.Unmarshal(data, &m); err != nil {
		return err
	}
	cur := utf16.Encode([]rune(textOf(doc)))
	at := newRemap(utf16.Encode([]rune(m.Text)), cur)

	var spans []span
	for _, r := range m.By {
		for _, p := range at.runs(r.From, r.To) {
			spans = append(spans, span{p[0], p[1], By, r.By})
		}
	}
	var nodes ot.Edit
	last := ""
	for _, t := range m.Threads {
		last = ot.KeyBetween(last, "")
		c := ot.Change{Op: ot.OpNew, ID: t.ID, Type: Thread, Key: last}
		if t.Done {
			c.Attrs = ot.Values{"done": json.RawMessage("true")}
		}
		nodes = append(nodes, c)
		msgKey := ""
		for _, g := range t.Msgs {
			msgKey = ot.KeyBetween(msgKey, "")
			nodes = append(nodes, ot.Change{Op: ot.OpNew, ID: g.ID, Type: Msg, Parent: t.ID, Key: msgKey, Attrs: ot.Values{
				By:     quote(g.By),
				"name": quote(g.Name),
				"at":   quote(g.At),
				"text": quote(g.Text),
			}})
		}
		for _, r := range t.Ranges {
			if from, to := at.passage(r[0], r[1]); from < to {
				spans = append(spans, span{from, to, anchor + t.ID, "1"})
			}
		}
	}
	if d := paint(spans, len(cur)); len(d) > 0 {
		nodes = append(nodes, ot.Change{Op: ot.OpTxt, ID: Body, Text: d})
	}
	return doc.Apply(nodes)
}

func (n *note) EncodeMeta(doc *ot.Tree) ([]byte, error) {
	m := metaNote{Text: textOf(doc)}
	ranges := map[string][][2]int{}
	pos := 0
	for _, p := range doc.Node(Body).Text.Paragraphs() {
		for _, o := range p {
			end := pos + o.Len()
			for k, v := range o.Attrs {
				switch {
				case k == By && v != "":
					if l := len(m.By); l > 0 && m.By[l-1].By == v && m.By[l-1].To == pos {
						m.By[l-1].To = end
					} else {
						m.By = append(m.By, metaRun{pos, end, v})
					}
				case strings.HasPrefix(k, anchor) && v != "":
					id := k[len(anchor):]
					rs := ranges[id]
					if l := len(rs); l > 0 && rs[l-1][1] == pos {
						rs[l-1][1] = end
					} else {
						rs = append(rs, [2]int{pos, end})
					}
					ranges[id] = rs
				}
			}
			pos = end
		}
	}
	for _, t := range doc.Children("") {
		if t.Type != Thread {
			continue
		}
		mt := metaThread{ID: t.ID, Done: string(t.Attrs["done"]) == "true", Ranges: ranges[t.ID], Msgs: []metaMessage{}}
		for _, g := range doc.Children(t.ID) {
			mt.Msgs = append(mt.Msgs, metaMessage{ID: g.ID, By: str(g, By), Name: str(g, "name"), At: num(g, "at"), Text: str(g, "text")})
		}
		m.Threads = append(m.Threads, mt)
	}
	return json.Marshal(m)
}

// comment tells whether a change that is not to the text of the note is one a
// person may make: a thread or a message created, a thread resolved, a
// message edited or deleted by whoever wrote it.
func comment(doc *ot.Tree, e ot.Edit, c ot.Change, by trame.Peer) error {
	node := doc.Node(c.ID)
	switch c.Op {
	case ot.OpNew:
		if node != nil || !validID(c.ID) {
			return errComment
		}
		switch c.Type {
		case Thread:
			if c.Parent == "" && len(c.Attrs) == 0 {
				return nil
			}
		case Msg:
			if only(c.Attrs, By, "name", "text") && str2(c.Attrs, By) == by.ID && str2(c.Attrs, "name") == by.Name &&
				text(str2(c.Attrs, "text")) && isThread(doc, e, c.Parent) {
				return nil
			}
		}
	case ot.OpSet:
		switch {
		case node == nil:
			return nil
		case c.Key != "":
		case node.Type == Thread && only(c.Attrs, "done"):
			if v := string(c.Attrs["done"]); v == "true" || v == "null" {
				return nil
			}
		case node.Type == Msg && only(c.Attrs, "text") && str(node, By) == by.ID && text(str2(c.Attrs, "text")):
			return nil
		}
	case ot.OpDel:
		switch {
		case node == nil:
			return nil
		case node.Type == Msg && str(node, By) == by.ID:
			return nil
		case node.Type == Thread:
			for _, g := range doc.Children(c.ID) {
				if str(g, By) != by.ID {
					return errComment
				}
			}
			return nil
		}
	}
	return errComment
}

func isThread(doc *ot.Tree, e ot.Edit, id string) bool {
	if t := doc.Node(id); t != nil {
		return t.Type == Thread
	}
	for _, c := range e {
		if c.Op == ot.OpNew && c.ID == id && c.Type == Thread {
			return true
		}
	}
	return false
}

func validID(s string) bool {
	if s == "" || len(s) > maxID {
		return false
	}
	for i := range len(s) {
		if s[i] <= ' ' || s[i] > '~' {
			return false
		}
	}
	return true
}

func isAnchor(k string) bool {
	return strings.HasPrefix(k, anchor) && validID(k[len(anchor):])
}

func text(s string) bool {
	return s != "" && len(s) <= maxMessage
}

// only tells whether attrs hold exactly the keys given, each once.
func only(attrs ot.Values, keys ...string) bool {
	if len(attrs) != len(keys) {
		return false
	}
	for _, k := range keys {
		if _, ok := attrs[k]; !ok {
			return false
		}
	}
	return true
}

func quote(v any) json.RawMessage {
	b, _ := json.Marshal(v)
	return b
}

func str(n *ot.Node, k string) string {
	return str2(n.Attrs, k)
}

func str2(a ot.Values, k string) string {
	var s string
	_ = json.Unmarshal(a[k], &s)
	return s
}

func num(n *ot.Node, k string) int64 {
	var v int64
	_ = json.Unmarshal(n.Attrs[k], &v)
	return v
}

// textOf is the text of the document, as the positions of its attributes
// count it.
func textOf(doc *ot.Tree) string {
	var b strings.Builder
	for _, p := range doc.Node(Body).Text.Paragraphs() {
		for _, o := range p {
			b.WriteString(o.Insert)
		}
	}
	return b.String()
}

// remap carries positions of the text a note was saved with to the text it
// was found with. The two share what begins and ends them; what lies between
// was changed by someone else.
type remap struct {
	old, cur []uint16
	head     int // what begins both texts
	oldEnd   int // where, in the old text, what they share at the end begins
	newEnd   int
}

func newRemap(old, cur []uint16) remap {
	head := 0
	for head < min(len(old), len(cur)) && old[head] == cur[head] {
		head++
	}
	if head > 0 && old[head-1] >= 0xD800 && old[head-1] < 0xDC00 {
		head--
	}
	tail := 0
	for tail < min(len(old), len(cur))-head && old[len(old)-1-tail] == cur[len(cur)-1-tail] {
		tail++
	}
	if tail > 0 && cur[len(cur)-tail] >= 0xDC00 && cur[len(cur)-tail] < 0xE000 {
		tail--
	}
	return remap{old, cur, head, len(old) - tail, len(cur) - tail}
}

// passage is where a passage went. Outside what changed it moves with the
// text around it; inside, it is the same words found nearest to where they
// were, or else what replaced them. It is empty when nothing is left.
func (r remap) passage(from, to int) (int, int) {
	shift := r.newEnd - r.oldEnd
	switch {
	case to <= r.head:
		return from, to
	case from >= r.oldEnd:
		return from + shift, to + shift
	}
	if at := nearest(r.cur, r.old[from:to], min(max(from, r.head), r.newEnd)); at >= 0 {
		return at, at + to - from
	}
	return min(from, r.head), r.newEnd
}

// nearest is where in text the words are found nearest to near, -1 if
// nowhere.
func nearest(text, words []uint16, near int) int {
	best := -1
	for i := 0; i+len(words) <= len(text) && len(words) > 0; i++ {
		if text[i] != words[0] || best >= 0 && abs(i-near) >= abs(best-near) && i > near {
			continue
		}
		if slices.Equal(text[i:i+len(words)], words) && (best < 0 || abs(i-near) < abs(best-near)) {
			best = i
		}
		if best >= 0 && i > near && i-near > abs(best-near) {
			break
		}
	}
	return best
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// runs are the parts of a passage that were not changed, carried to the new
// text.
func (r remap) runs(from, to int) [][2]int {
	var out [][2]int
	if a, b := from, min(to, r.head); a < b {
		out = append(out, [2]int{a, b})
	}
	if a, b := max(from, r.oldEnd), to; a < b {
		shift := r.newEnd - r.oldEnd
		out = append(out, [2]int{a + shift, b + shift})
	}
	return out
}

// span is an attribute over a passage.
type span struct {
	from, to int
	key, val string
}

// paint is the delta that gives a text of length n the attributes of spans.
func paint(spans []span, n int) ot.Delta {
	type event struct {
		at   int
		on   bool
		span int
	}
	var events []event
	for i, s := range spans {
		s.to = min(s.to, n)
		if s.from < s.to {
			events = append(events, event{s.from, true, i}, event{s.to, false, i})
		}
	}
	slices.SortStableFunc(events, func(a, b event) int { return a.at - b.at })
	var d ot.Delta
	active := map[int]bool{}
	at := 0
	for _, ev := range events {
		if ev.at > at {
			d = d.Push(ot.Op{Retain: ev.at - at, Attrs: attrsOf(spans, active)})
			at = ev.at
		}
		if ev.on {
			active[ev.span] = true
		} else {
			delete(active, ev.span)
		}
	}
	return d
}

func attrsOf(spans []span, active map[int]bool) ot.Attrs {
	if len(active) == 0 {
		return nil
	}
	a := ot.Attrs{}
	for i := range active {
		a[spans[i].key] = spans[i].val
	}
	return a
}
