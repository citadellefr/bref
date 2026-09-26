package bref

import (
	"fmt"
	"path"
	"strings"

	"github.com/citadellefr/bref/ot"
	"github.com/citadellefr/bref/pptx"
)

// format writes a document back into the kind of file it was read from,
// tells which edits it can take, and serves its pictures.
type format interface {
	check(doc *ot.Tree, e ot.Edit) error
	encode(doc *ot.Tree) ([]byte, error)
	media(name string) ([]byte, string, error)
}

// formats read files into documents, by extension.
var formats = map[string]func(data []byte) (*ot.Tree, format, error){
	".txt":  openText,
	".pptx": openPresentation,
	".pptm": openPresentation,
	".ppsx": openPresentation,
}

// presentation is a PowerPoint file.
type presentation struct {
	doc *pptx.Document
}

func openPresentation(data []byte) (*ot.Tree, format, error) {
	doc, tree, err := pptx.Open(data)
	if err != nil {
		return nil, nil, err
	}
	return tree, presentation{doc}, nil
}

func (p presentation) check(doc *ot.Tree, e ot.Edit) error {
	return p.doc.Check(doc, e)
}

func (p presentation) encode(doc *ot.Tree) ([]byte, error) {
	return p.doc.Save(doc)
}

func (p presentation) media(name string) ([]byte, string, error) {
	data, typ, err := p.doc.Media(name)
	if err != nil {
		return nil, "", fmt.Errorf("%w: %v", ErrNoMedia, err)
	}
	return data, typ, nil
}

// open reads a file into a document, in the format its key's extension
// names.
func open(key string, data []byte) (*ot.Tree, format, error) {
	ext := strings.ToLower(path.Ext(key))
	read := formats[ext]
	if read == nil {
		return nil, nil, fmt.Errorf("bref: %q files are not supported", ext)
	}
	return read(data)
}
