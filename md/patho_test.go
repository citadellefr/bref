//go:build !race

package md

import (
	"strings"
	"testing"
	"time"
)

// TestPathological parses inputs made to take quadratic time from a naive
// parser.
func TestPathological(t *testing.T) {
	r := strings.Repeat
	var lists strings.Builder
	for i := range 1000 {
		lists.WriteString(r("  ", i) + "* a\n")
	}
	var ticks strings.Builder
	for i := 1; i < 2500; i++ {
		ticks.WriteString("e" + r("`", i))
	}
	cases := map[string]string{
		"nested strong emph":   r("*a **a ", 30000) + "b" + r(" a** a*", 30000),
		"emph closers":         r("a_ ", 30000),
		"emph openers":         r("_a ", 30000),
		"link closers":         r("a]", 30000),
		"link openers":         r("[a", 30000),
		"mismatched":           r("*a_ ", 30000),
		"multiple of 3":        "a**b" + r("c* ", 30000),
		"link openers emph":    r("[ a_", 30000),
		"brackets parens":      r("[ (](", 30000),
		"nested brackets":      r("[", 30000) + "a" + r("]", 30000),
		"nested quotes":        r("> ", 30000) + "a",
		"nested lists":         lists.String(),
		"backticks":            ticks.String(),
		"unclosed angle links": r("[a](<b", 30000),
		"unclosed links":       r("[a](b", 30000),
		"unclosed comments":    "</" + r("<!--", 100000),
		"wiki openers":         r("[[a", 30000),
		"dollars":              r("$a ", 30000),
		"strike":               r("~a ", 30000),
		"highlight":            r("==a ", 30000),
		"emails":               r("a@", 30000),
		"www":                  r("www.", 30000),
		"table rows":           "| a |\n|---|\n" + r("| b |\n", 30000),
		"table header":         r("a", 30000) + "\n" + r("|-", 30000) + "\n",
		"definitions":          r("[a]: /b\n", 30000),
		"emph in links":        r("[*a](b) ", 30000),
		"quote lazy":           "> a\n" + r("b\n", 30000),
	}
	for name, src := range cases {
		t.Run(strings.ReplaceAll(name, " ", "_"), func(t *testing.T) {
			start := time.Now()
			Parse(src)
			if d := time.Since(start); d > time.Second {
				t.Errorf("%v", d)
			}
		})
	}
}
