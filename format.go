package bref

import (
	"fmt"
	"path"
	"strings"

	"github.com/citadellefr/bref/ot"
)

// format writes a document back into the kind of file it was read from,
// and tells which edits it can.
type format interface {
	check(e ot.Edit) error
	encode(doc *ot.Tree) []byte
}

// formats read files into documents, by extension.
var formats = map[string]func(data []byte) (*ot.Tree, format, error){
	".txt": openText,
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
