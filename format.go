package bref

import (
	"fmt"
	"path"
	"strings"

	"github.com/citadellefr/bref/ot"
)

// format writes a document back into the kind of file it was read from.
type format interface {
	encode(doc *ot.Doc) []byte
}

// open reads a file into a document, in the format its key's extension
// names.
func open(key string, data []byte) (*ot.Doc, format, error) {
	switch ext := strings.ToLower(path.Ext(key)); ext {
	case ".txt":
		return openText(data)
	default:
		return nil, nil, fmt.Errorf("bref: %q files are not supported", ext)
	}
}
