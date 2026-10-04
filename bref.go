// Package bref serves Markdown notes to collaborative editors. The hub is
// trame's; this package is the format of the notes: the file is the text,
// edited as one flow, and written back exactly as it was read but for what
// was typed.
package bref

import (
	"errors"

	"github.com/citadellefr/trame"
	"github.com/citadellefr/trame/ot"
)

// Body is the node holding the text of a note, one paragraph per line.
const Body = trame.TextBody

var errFormatting = errors.New("a note is plain text: its characters carry no attributes")

// NewHub serves notes from store.
func NewHub(store trame.Store, opt trame.Options) *trame.Hub {
	return trame.NewHub(store, Open, opt)
}

// Open reads a note; it is the Format of a hub that serves notes among other
// documents.
func Open(key string, data []byte) (*ot.Tree, trame.File, error) {
	doc, f, err := trame.Text(key, data)
	return doc, note{f}, err
}

type note struct {
	trame.File
}

func (n note) Check(doc *ot.Tree, e ot.Edit, by trame.Peer) error {
	if err := n.File.Check(doc, e, by); err != nil {
		return err
	}
	for _, c := range e {
		for _, o := range c.Text {
			if o.Attrs != nil {
				return errFormatting
			}
		}
	}
	return nil
}
