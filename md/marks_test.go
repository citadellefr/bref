package md

import (
	"strings"
	"testing"
)

// TestMarks checks what an editor relies on: marks lie on one line, never
// on text, and are the syntax of their node.
func TestMarks(t *testing.T) {
	sets := []struct {
		file string
		ext  extensions
	}{{"commonmark.json", 0}, {"gfm.json", gfm}, {"bref.json", bref}}
	for _, set := range sets {
		for _, e := range readExamples(t, set.file) {
			src := e.Markdown
			var marks, texts []Span
			parse(src, set.ext).Walk(func(n *Node) bool {
				for _, m := range n.Marks {
					if m.Start > m.End || m.End > len(src) || strings.ContainsAny(src[m.Start:m.End], "\r\n") {
						t.Errorf("%s %d: %s mark %v", set.file, e.Example, n.Kind, m)
						continue
					}
					marks = append(marks, m)
					if !markFits(n, src[m.Start:m.End]) {
						t.Errorf("%s %d: %s mark %q", set.file, e.Example, n.Kind, src[m.Start:m.End])
					}
				}
				switch n.Kind {
				case Text:
					if src[n.Start:n.End] != n.Literal && !strings.Contains(src[n.Start:n.End], "\x00") {
						t.Errorf("%s %d: text %q at %q", set.file, e.Example, n.Literal, src[n.Start:n.End])
					}
					texts = append(texts, n.Span)
				case Escape:
					if src[n.Start:n.End] != `\`+n.Literal {
						t.Errorf("%s %d: escape %q at %q", set.file, e.Example, n.Literal, src[n.Start:n.End])
					}
				}
				return !(n.Kind == Link && n.Form == LinkAngle)
			})
			for _, m := range marks {
				for _, x := range texts {
					if m.Start < x.End && x.Start < m.End {
						t.Errorf("%s %d: mark %q over text %q", set.file, e.Example, src[m.Start:m.End], src[x.Start:x.End])
					}
				}
			}
		}
	}
}

func markFits(n *Node, s string) bool {
	switch n.Kind {
	case Quote:
		return s[0] == '>'
	case Emphasis, Strong:
		return strings.Trim(s, "*") == "" || strings.Trim(s, "_") == ""
	case Strike:
		return strings.Trim(s, "~") == ""
	case Highlight:
		return s == "=="
	case Code:
		return strings.Trim(s, "`") == ""
	case Math:
		return s == "$" || s == "$$"
	case Escape:
		return s == `\`
	case Heading:
		return strings.Trim(s, "#=- \t") == ""
	case Item:
		return s == "[ ]" || s == "[x]" || s == "[X]" || strings.Trim(s, "0123456789-+*.)") == ""
	case Link, Image:
		return true
	case Row:
		return s == "|"
	}
	return s != ""
}
