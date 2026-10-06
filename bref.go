// Package bref serves Markdown notes to collaborative editors. The hub is
// trame's; this package is the format of the notes: the file is the text,
// edited as one flow, and written back exactly as it was read but for what
// was typed.
package bref

import (
	"errors"
	"maps"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/citadellefr/bref/md"
	"github.com/citadellefr/trame"
	"github.com/citadellefr/trame/ot"
)

// Body is the node holding the text of a note, one paragraph per line.
const Body = trame.TextBody

// By is the attribute of the characters of a note telling who wrote them:
// the ID of a trame.Peer. It is the server's to set, never written in the
// file.
const By = "by"

var errFormatting = errors.New("a note is plain text: its characters carry no attributes but their author")

// Options tunes a hub of notes.
type Options struct {
	trame.Options
	// OnLinks is told, as a note is saved, of the links, mentions and
	// pictures added to it since the last time: to tell @Alice she was
	// mentioned, or to index the links between notes. It is called on the
	// note's saving goroutine, which it should not hold up.
	OnLinks func(key string, added []Link)
	// OnSave is given the file of a note each time it is saved, with the IDs
	// of those who edited it since the last time: to keep its versions. A
	// save that failed is tried again, so the host may be given the same
	// file twice. It is called on the note's saving goroutine.
	OnSave func(key string, data []byte, authors []string)
}

// Link is a link, a mention or a picture of a note.
type Link struct {
	// Dest is what it leads to, as written: user:42, file:9f3c, an address,
	// or the name of a [[note]].
	Dest string
	// Text is what it reads as: @Alice, the description of a picture.
	Text  string
	Image bool
	Form  md.LinkForm
	// By is the ID of who wrote most of it, "" when nobody wrote any of it
	// since the note was opened: a link a definition gives a destination.
	By string
}

// NewHub serves notes from store.
func NewHub(store trame.Store, opt Options) *trame.Hub {
	return trame.NewHub(store, Format(opt), opt.Options)
}

// Format reads notes, for a hub that serves them among other documents;
// its trame.Options are not used.
func Format(opt Options) trame.Format {
	return func(key string, data []byte) (*ot.Tree, trame.File, error) {
		doc, f, err := trame.Text(key, data)
		if err != nil {
			return nil, nil, err
		}
		n := &note{File: f, key: key, onLinks: opt.OnLinks, onSave: opt.OnSave, now: time.Now}
		if n.onLinks != nil {
			text, _ := authors(doc)
			n.links = count(md.Links(md.Parse(text)))
		}
		return doc, n, nil
	}
}

type note struct {
	trame.File
	key     string
	onLinks func(string, []Link)
	onSave  func(string, []byte, []string)
	now     func() time.Time
	// kept tells that the host keeps what a note holds beside its file: it
	// takes comments, and the authors of its characters outlive the hub.
	kept bool

	mu sync.Mutex
	// editors are those who edited since the note was last saved.
	editors map[string]bool
	// links counts those of the note when it was last saved, by
	// destination.
	links map[linkKey]int
}

type linkKey struct {
	dest  string
	image bool
}

func keyOf(l *md.Node) linkKey {
	return linkKey{l.Dest, l.Kind == md.Image}
}

func count(links []*md.Node) map[linkKey]int {
	m := map[linkKey]int{}
	for _, l := range links {
		m[keyOf(l)]++
	}
	return m
}

func (n *note) Check(doc *ot.Tree, e ot.Edit, by trame.Peer) error {
	for _, c := range e {
		switch {
		case c.Op == ot.OpTxt && c.ID == Body:
			if err := n.File.Check(doc, ot.Edit{c}, by); err != nil {
				return err
			}
			if err := n.checkAttrs(c.Text); err != nil {
				return err
			}
		case !n.kept:
			return n.File.Check(doc, ot.Edit{c}, by)
		default:
			if err := comment(doc, e, c, by); err != nil {
				return err
			}
		}
	}
	n.mu.Lock()
	if n.editors == nil {
		n.editors = map[string]bool{}
	}
	n.editors[by.ID] = true
	n.mu.Unlock()
	return nil
}

// checkAttrs refuses attributes other than the author of what is inserted,
// and the passages of the threads, which are retained.
func (n *note) checkAttrs(d ot.Delta) error {
	for _, o := range d {
		for k, v := range o.Attrs {
			switch {
			case o.Insert != "" && k == By && len(o.Attrs) == 1:
			case o.Insert == "" && o.Delete == 0 && n.kept && isAnchor(k) && (v == "1" || v == ""):
			default:
				return errFormatting
			}
		}
	}
	return nil
}

// Follow signs what the edit inserted with its author, where it was not:
// text whose deletion is undone keeps the signature of who wrote it first.
// It also dates the comments the edit made.
func (n *note) Follow(doc *ot.Tree, e ot.Edit, _ []ot.Edit, by trame.Peer) ot.Edit {
	var edited ot.Delta
	for _, c := range e {
		var err error
		if edited, err = ot.Compose(edited, c.Text); err != nil {
			return nil
		}
	}
	var sign ot.Delta
	at, signed := 0, 0
	for _, o := range edited {
		switch {
		case o.Retain > 0:
			at += o.Retain
		case o.Insert != "":
			l := o.Len()
			if o.Attrs[By] != by.ID {
				sign = sign.Push(ot.Op{Retain: at - signed}).Push(ot.Op{Retain: l, Attrs: ot.Attrs{By: by.ID}})
				signed = at + l
			}
			at += l
		}
	}
	var more ot.Edit
	if sign != nil {
		more = append(more, ot.Change{Op: ot.OpTxt, ID: Body, Text: sign})
	}
	date := quote(n.now().Unix())
	for _, c := range e {
		if c.Op == ot.OpNew && c.Type == Msg && doc.Node(c.ID) != nil {
			more = append(more, ot.Change{Op: ot.OpSet, ID: c.ID, Attrs: ot.Values{"at": date}})
		}
	}
	if len(more) == 0 || doc.Apply(more) != nil {
		return nil
	}
	return more
}

func (n *note) Encode(doc *ot.Tree) ([]byte, error) {
	data, err := n.File.Encode(doc)
	if err != nil {
		return nil, err
	}
	if n.onLinks != nil {
		n.report(doc)
	}
	if n.onSave != nil {
		n.mu.Lock()
		editors := slices.Sorted(maps.Keys(n.editors))
		n.editors = nil
		n.mu.Unlock()
		n.onSave(n.key, data, editors)
	}
	return data, nil
}

// report tells the host the links added since the last save. When a
// destination is written more often than it was, the links to it someone
// wrote since the note was opened are the ones added.
func (n *note) report(doc *ot.Tree) {
	text, runs := authors(doc)
	links := md.Links(md.Parse(text))
	now := count(links)
	n.mu.Lock()
	seen := n.links
	n.links = now
	n.mu.Unlock()
	var added []Link
	done := map[linkKey]bool{}
	for i, l := range links {
		k := keyOf(l)
		if now[k] <= seen[k] || done[k] {
			continue
		}
		done[k] = true
		var written, others []Link
		for _, m := range links[i:] {
			if keyOf(m) != k {
				continue
			}
			link := Link{Dest: m.Dest, Text: md.Plain(m), Image: k.image, Form: m.Form, By: runs.author(m.Span)}
			if link.By != "" {
				written = append(written, link)
			} else {
				others = append(others, link)
			}
		}
		added = append(added, append(written, others...)[:now[k]-seen[k]]...)
	}
	if len(added) > 0 {
		n.onLinks(n.key, added)
	}
}

// run is a piece of a note written by one person, up to end, in bytes.
type run struct {
	end int
	by  string
}

type runs []run

// authors is the text of a note and who wrote it.
func authors(doc *ot.Tree) (string, runs) {
	var b strings.Builder
	var rs runs
	for _, p := range doc.Node(Body).Text.Paragraphs() {
		for _, o := range p {
			b.WriteString(o.Insert)
			if by := o.Attrs[By]; len(rs) > 0 && rs[len(rs)-1].by == by {
				rs[len(rs)-1].end = b.Len()
			} else {
				rs = append(rs, run{b.Len(), by})
			}
		}
	}
	return b.String(), rs
}

// author is who wrote most of span.
func (rs runs) author(s md.Span) string {
	written := map[string]int{}
	best := ""
	from := 0
	for _, r := range rs {
		if r.end > s.Start && from < s.End && r.by != "" {
			written[r.by] += min(r.end, s.End) - max(from, s.Start)
			if best == "" || written[r.by] > written[best] {
				best = r.by
			}
		}
		if r.end >= s.End {
			break
		}
		from = r.end
	}
	return best
}
