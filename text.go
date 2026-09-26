package bref

import (
	"bytes"
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/citadellefr/bref/ot"
)

// textFile is a plain text file: a single node, "body", whose text has one
// paragraph per line. It is written back with the byte order mark and the
// line endings it was read with, in UTF-8: a file that was not UTF-8 is read
// as Windows-1252, as Notepad does.
type textFile struct {
	bom  bool
	crlf bool
}

const textBody = "body"

var (
	bom          = []byte{0xEF, 0xBB, 0xBF}
	errTextNodes = errors.New("a text file only has its text")
)

func openText(data []byte) (*ot.Tree, format, error) {
	var f textFile
	data, f.bom = bytes.CutPrefix(data, bom)
	text := string(data)
	if !utf8.Valid(data) {
		text = windows1252(data)
	}
	if i := strings.IndexByte(text, '\n'); i > 0 && text[i-1] == '\r' {
		f.crlf = true
		text = strings.ReplaceAll(text, "\r\n", "\n")
	}
	doc, err := ot.NewTree(ot.Edit{{Op: ot.OpNew, ID: textBody, Type: "text", Key: "V", Text: ot.Delta{{Insert: text + "\n"}}}})
	return doc, f, err
}

func (textFile) check(_ *ot.Tree, e ot.Edit) error {
	for _, c := range e {
		if c.Op != ot.OpTxt || c.ID != textBody {
			return errTextNodes
		}
	}
	return nil
}

func (textFile) media(string) ([]byte, string, error) {
	return nil, "", ErrNoMedia
}

func (f textFile) encode(doc *ot.Tree) ([]byte, error) {
	var b bytes.Buffer
	if f.bom {
		b.Write(bom)
	}
	for i, p := range doc.Node(textBody).Text.Paragraphs() {
		if i > 0 {
			if f.crlf {
				b.WriteByte('\r')
			}
			b.WriteByte('\n')
		}
		for j, o := range p {
			if j == len(p)-1 {
				o.Insert = strings.TrimSuffix(o.Insert, "\n")
			}
			b.WriteString(o.Insert)
		}
	}
	return b.Bytes(), nil
}

// windows1252 differs from Latin-1 in 0x80–0x9F.
var windows1252High = [32]rune{
	'€', 0x81, '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', 0x8D, 'Ž', 0x8F,
	0x90, '‘', '’', '“', '”', '•', '–', '—', '˜', '™', 'š', '›', 'œ', 0x9D, 'ž', 'Ÿ',
}

func windows1252(data []byte) string {
	var b strings.Builder
	for _, c := range data {
		if 0x80 <= c && c < 0xA0 {
			b.WriteRune(windows1252High[c-0x80])
		} else {
			b.WriteRune(rune(c))
		}
	}
	return b.String()
}
