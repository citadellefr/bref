package bref

import (
	"bytes"
	"strings"
	"unicode/utf8"

	"github.com/citadellefr/bref/ot"
)

// textFile is a plain text file, one paragraph per line. It is written back
// with the byte order mark and the line endings it was read with, in UTF-8:
// a file that was not UTF-8 is read as Windows-1252, as Notepad does.
type textFile struct {
	bom  bool
	crlf bool
}

var bom = []byte{0xEF, 0xBB, 0xBF}

func openText(data []byte) (*ot.Doc, format, error) {
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
	doc, err := ot.NewDoc(ot.Delta{{Insert: text + "\n"}})
	return doc, f, err
}

func (f textFile) encode(doc *ot.Doc) []byte {
	var b bytes.Buffer
	if f.bom {
		b.Write(bom)
	}
	for i, p := range doc.Paragraphs() {
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
	return b.Bytes()
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
