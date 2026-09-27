package bref

import (
	"fmt"
	"path"
	"strings"

	"github.com/citadellefr/bref/formula"
	"github.com/citadellefr/bref/ot"
	"github.com/citadellefr/bref/pptx"
	"github.com/citadellefr/bref/xlsx"
)

// format writes a document back into the kind of file it was read from,
// tells which edits it can take, and serves its pictures.
type format interface {
	check(doc *ot.Tree, e ot.Edit) error
	encode(doc *ot.Tree) ([]byte, error)
	media(name string) ([]byte, string, error)
}

// follower is a format that follows an edit with changes of its own,
// which every peer receives as the server's: the formulas of a workbook
// calculated again. since are the edits the edit was rebased over.
type follower interface {
	follow(doc *ot.Tree, e ot.Edit, since []ot.Edit) ot.Edit
}

// formats read files into documents, by extension.
var formats = map[string]func(data []byte) (*ot.Tree, format, error){
	".txt":  openText,
	".pptx": openPresentation,
	".pptm": openPresentation,
	".ppsx": openPresentation,
	".xlsx": openWorkbook,
	".xlsm": openWorkbook,
	".xltx": openWorkbook,
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

// workbook is an Excel file, whose formulas the hub calculates.
type workbook struct {
	doc  *xlsx.Document
	calc *xlsx.Calc
}

func openWorkbook(data []byte) (*ot.Tree, format, error) {
	doc, tree, err := xlsx.Open(data)
	if err != nil {
		return nil, nil, err
	}
	return tree, &workbook{doc: doc, calc: xlsx.NewCalc(tree, formula.Options{})}, nil
}

func (w *workbook) check(doc *ot.Tree, e ot.Edit) error {
	return w.doc.Check(doc, e)
}

func (w *workbook) encode(doc *ot.Tree) ([]byte, error) {
	return w.doc.Save(doc)
}

func (w *workbook) media(string) ([]byte, string, error) {
	return nil, "", ErrNoMedia
}

// follow calculates again what the edit reaches. A failure of the
// calculation leaves the values as they are rather than the hub down.
func (w *workbook) follow(doc *ot.Tree, e ot.Edit, since []ot.Edit) (out ot.Edit) {
	defer func() {
		if recover() != nil {
			out = nil
		}
	}()
	return w.calc.Follow(e, since)
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
