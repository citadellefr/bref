package md

import (
	"bytes"
	"encoding/json"
	"flag"
	"math/rand/v2"
	"os"
	"strings"
	"testing"
	"unicode/utf8"
)

var update = flag.Bool("update", false, "rewrite the vectors in testdata/md")

// TestBref checks the extensions of Bref, whose cases are in bref.json.
func TestBref(t *testing.T) {
	examples := readExamples(t, "bref.json")
	for i, e := range examples {
		got := HTML(Parse(e.Markdown))
		if *update {
			examples[i].HTML = got
		} else if got != e.HTML {
			t.Errorf("example %d\n%q\ngot  %q\nwant %q", e.Example, e.Markdown, got, e.HTML)
		}
	}
	if *update {
		writeJSON(t, "bref.json", examples)
	}
}

type vector struct {
	Dialect  string `json:"dialect"`
	Markdown string `json:"md"`
	Tree     any    `json:"tree"`
}

// TestVectors checks the trees the Dart parser must find, offsets counted
// in UTF-16 as Dart strings do.
func TestVectors(t *testing.T) {
	var vectors []vector
	for _, set := range []struct {
		file, dialect string
		ext           extensions
	}{{"commonmark.json", "commonmark", 0}, {"gfm.json", "gfm", gfm}, {"bref.json", "bref", bref}} {
		for _, e := range readExamples(t, set.file) {
			vectors = append(vectors, vector{set.dialect, e.Markdown, dump(parse(e.Markdown, set.ext), utf16Offsets(e.Markdown))})
		}
	}
	for _, src := range mixed(t, 400) {
		vectors = append(vectors, vector{"bref", src, dump(Parse(src), utf16Offsets(src))})
	}
	var b bytes.Buffer
	b.WriteString("[\n")
	for i, v := range vectors {
		if i > 0 {
			b.WriteString(",\n")
		}
		b.Write(bytes.TrimSuffix(compactJSON(t, v), []byte("\n")))
	}
	b.WriteString("\n]\n")
	if *update {
		if err := os.WriteFile("../testdata/md/vectors.json", b.Bytes(), 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile("../testdata/md/vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(b.Bytes(), want) {
		t.Fatal("the trees differ from testdata/md/vectors.json: run go test ./md -update and review the change")
	}
}

// mixed are documents made of lines of the examples, cut and spliced with
// syntax, characters beyond ASCII and beyond the basic plane.
func mixed(t *testing.T, n int) []string {
	var lines []string
	for _, set := range []string{"commonmark.json", "gfm.json", "bref.json"} {
		for _, e := range readExamples(t, set) {
			lines = append(lines, strings.Split(strings.TrimSuffix(e.Markdown, "\n"), "\n")...)
		}
	}
	bits := []string{"*", "**", "_", "~~", "==", "$", "$$", "[", "]", "[[", "]]", "(", ")", "<", ">", "!", "`", "|", "#", "- ", "1. ", "> ", "\\", "&amp;", "\t", "    ", "é", "😀", "\u00a0", "www.a.b", "https://x.y", "a@b.co", "\r\n"}
	r := rand.New(rand.NewPCG(1, 2))
	docs := make([]string, n)
	for i := range docs {
		var b strings.Builder
		for range 2 + r.IntN(8) {
			line := lines[r.IntN(len(lines))]
			for range r.IntN(3) {
				at := r.IntN(len(line) + 1)
				for at > 0 && at < len(line) && !utf8.RuneStart(line[at]) {
					at--
				}
				line = line[:at] + bits[r.IntN(len(bits))] + line[at:]
			}
			b.WriteString(line)
			b.WriteString("\n")
		}
		docs[i] = b.String()
	}
	return docs
}

func utf16Offsets(s string) []int {
	offsets := make([]int, len(s)+1)
	n := 0
	for i, r := range s {
		for j := i; j < i+utf8.RuneLen(r) && j < len(s); j++ {
			offsets[j] = n
		}
		if r >= 0x10000 {
			n += 2
		} else {
			n++
		}
	}
	offsets[len(s)] = n
	return offsets
}

func dump(n *Node, u []int) map[string]any {
	span := func(s Span) []int { return []int{u[s.Start], u[s.End]} }
	d := map[string]any{"k": n.Kind.String(), "s": u[n.Start], "e": u[n.End]}
	if len(n.Marks) > 0 {
		marks := [][]int{}
		for _, m := range n.Marks {
			marks = append(marks, span(m))
		}
		d["m"] = marks
	}
	if n.Literal != "" {
		d["lit"] = n.Literal
	}
	if n.Level != 0 {
		d["level"] = n.Level
	}
	if n.Info != "" {
		d["info"] = n.Info
	}
	if n.Kind == List {
		d["ordered"], d["number"], d["tight"], d["marker"] = n.Ordered, n.Number, n.Tight, string(n.Marker)
	}
	if n.Task != TaskNone {
		d["task"] = int(n.Task)
	}
	if n.Align != nil {
		align := []int{}
		for _, a := range n.Align {
			align = append(align, int(a))
		}
		d["align"] = align
	}
	if n.Header {
		d["header"] = true
	}
	if n.Kind == Link || n.Kind == Image || n.Kind == Definition {
		d["dest"], d["title"], d["form"], d["url"] = n.Dest, n.Title, int(n.Form), span(n.URL)
		if n.Label != "" {
			d["label"] = n.Label
		}
	}
	if n.Display {
		d["display"] = true
	}
	if len(n.Children) > 0 {
		var c []any
		for _, child := range n.Children {
			c = append(c, dump(child, u))
		}
		d["c"] = c
	}
	return d
}

func compactJSON(t *testing.T, v any) []byte {
	t.Helper()
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func encodeJSON(t *testing.T, v any) []byte {
	t.Helper()
	b := compactJSON(t, v)
	var out bytes.Buffer
	if err := json.Indent(&out, b, "", " "); err != nil {
		t.Fatal(err)
	}
	return out.Bytes()
}

func writeJSON(t *testing.T, name string, v any) {
	t.Helper()
	if err := os.WriteFile("../testdata/md/"+name, encodeJSON(t, v), 0o644); err != nil {
		t.Fatal(err)
	}
}
