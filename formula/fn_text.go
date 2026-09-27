package formula

import (
	"math"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf16"
)

// maxText is the longest text a cell holds.
const maxText = 32767

func init() {
	add(map[string]*function{
		"CONCATENATE": fn(1, 255, func(c *Context, v []Value) Value {
			var b strings.Builder
			for _, x := range v {
				s, err := c.text(x)
				if err != nil {
					return *err
				}
				b.WriteString(s)
			}
			return textResult(b.String())
		}),
		"CONCAT": {min: 1, max: 253, call: func(c *Context, args []Expr) Value {
			var b strings.Builder
			var err *Value
			c.each(args, func(v Value, _ bool) bool {
				s, e := c.text(v)
				if e != nil {
					err = e
					return false
				}
				b.WriteString(s)
				return true
			})
			if err != nil {
				return *err
			}
			return textResult(b.String())
		}},
		"TEXTJOIN": {min: 3, max: 252, call: func(c *Context, args []Expr) Value {
			sep, err := c.text(c.Eval(args[0]))
			if err != nil {
				return *err
			}
			skip, err := c.boolean(c.Eval(args[1]))
			if err != nil {
				return *err
			}
			var parts []string
			c.each(args[2:], func(v Value, _ bool) bool {
				s, e := c.text(v)
				if e != nil {
					err = e
					return false
				}
				if s != "" || !skip {
					parts = append(parts, s)
				}
				return true
			})
			if err != nil {
				return *err
			}
			return textResult(strings.Join(parts, sep))
		}},
		"LEFT":  cut(func(u []uint16, n int) []uint16 { return u[:min(n, len(u))] }),
		"RIGHT": cut(func(u []uint16, n int) []uint16 { return u[len(u)-min(n, len(u)):] }),
		"MID": fn(3, 3, func(c *Context, v []Value) Value {
			s, err := c.text(v[0])
			if err != nil {
				return *err
			}
			start, err := c.number(v[1])
			if err != nil {
				return *err
			}
			n, err := c.number(v[2])
			if err != nil {
				return *err
			}
			if start < 1 || n < 0 {
				return ErrValue
			}
			u := utf16.Encode([]rune(s))
			i := min(int(start)-1, len(u))
			return Str(decode(u[i:min(i+int(n), len(u))]))
		}),
		"LEN": fn(1, 1, func(c *Context, v []Value) Value {
			return c.mapValues(v[0], func(x Value) Value {
				s, err := c.text(x)
				if err != nil {
					return *err
				}
				return Num(float64(len(utf16.Encode([]rune(s)))))
			})
		}),
		"LOWER": text1(strings.ToLower),
		"UPPER": text1(strings.ToUpper),
		"PROPER": text1(func(s string) string {
			var b strings.Builder
			after := false
			for _, r := range s {
				if unicode.IsLetter(r) {
					if after {
						r = unicode.ToLower(r)
					} else {
						r = unicode.ToUpper(r)
					}
					after = true
				} else {
					after = false
				}
				b.WriteRune(r)
			}
			return b.String()
		}),
		"TRIM": text1(func(s string) string {
			return strings.Join(strings.FieldsFunc(s, func(r rune) bool { return r == ' ' }), " ")
		}),
		"CLEAN": text1(func(s string) string {
			return strings.Map(func(r rune) rune {
				if r < 32 {
					return -1
				}
				return r
			}, s)
		}),
		"SUBSTITUTE": fn(3, 4, func(c *Context, v []Value) Value {
			var s [3]string
			for i := range s {
				t, err := c.text(v[i])
				if err != nil {
					return *err
				}
				s[i] = t
			}
			if s[1] == "" {
				return Str(s[0])
			}
			if len(v) < 4 {
				return textResult(strings.ReplaceAll(s[0], s[1], s[2]))
			}
			n, err := c.number(v[3])
			if err != nil {
				return *err
			}
			if n < 1 {
				return ErrValue
			}
			i, at := 0, -1
			for k := 0; k < int(n); k++ {
				j := strings.Index(s[0][i:], s[1])
				if j < 0 {
					return Str(s[0])
				}
				at = i + j
				i = at + len(s[1])
			}
			return textResult(s[0][:at] + s[2] + s[0][at+len(s[1]):])
		}),
		"REPLACE": fn(4, 4, func(c *Context, v []Value) Value {
			s, err := c.text(v[0])
			if err != nil {
				return *err
			}
			start, err := c.number(v[1])
			if err != nil {
				return *err
			}
			n, err := c.number(v[2])
			if err != nil {
				return *err
			}
			with, err := c.text(v[3])
			if err != nil {
				return *err
			}
			if start < 1 || n < 0 {
				return ErrValue
			}
			u := utf16.Encode([]rune(s))
			i := min(int(start)-1, len(u))
			j := min(i+int(n), len(u))
			return textResult(decode(u[:i]) + with + decode(u[j:]))
		}),
		"FIND":   find(false),
		"SEARCH": find(true),
		"REPT": fn(2, 2, func(c *Context, v []Value) Value {
			s, err := c.text(v[0])
			if err != nil {
				return *err
			}
			n, err := c.number(v[1])
			if err != nil {
				return *err
			}
			if n < 0 || len(s)*int(n) > maxText*4 {
				return ErrValue
			}
			return textResult(strings.Repeat(s, int(n)))
		}),
		"EXACT": fn(2, 2, func(c *Context, v []Value) Value {
			a, err := c.text(v[0])
			if err != nil {
				return *err
			}
			b, err := c.text(v[1])
			if err != nil {
				return *err
			}
			return Boolean(a == b)
		}),
		"CHAR": math1(func(n float64) Value {
			if n < 1 || n > 255 {
				return ErrValue
			}
			return Str(string(ansi(byte(n))))
		}),
		"UNICHAR": math1(func(n float64) Value {
			if n < 1 || n > unicode.MaxRune || n >= 0xD800 && n <= 0xDFFF {
				return ErrValue
			}
			return Str(string(rune(n)))
		}),
		"CODE": text1Value(func(s string) Value {
			if s == "" {
				return ErrValue
			}
			r := []rune(s)[0]
			for b := 1; b < 256; b++ {
				if ansi(byte(b)) == r {
					return Num(float64(b))
				}
			}
			return Num(63)
		}),
		"UNICODE": text1Value(func(s string) Value {
			if s == "" {
				return ErrValue
			}
			return Num(float64([]rune(s)[0]))
		}),
		"T": fn(1, 1, func(c *Context, v []Value) Value {
			x := c.scalar(v[0])
			switch x.Type {
			case TypeText, TypeError:
				return x
			}
			return Str("")
		}),
		"TEXT": fn(2, 2, func(c *Context, v []Value) Value {
			code, err := c.text(v[1])
			if err != nil {
				return *err
			}
			f := ParseFormat(c.Locale.invariant(code))
			x := c.scalar(v[0])
			switch x.Type {
			case TypeError:
				return x
			case TypeText:
				if n, ok := c.parseNumber(x.Str); ok {
					return textResult(c.Locale.Format(n, f, c.Date1904))
				}
				return textResult(c.Locale.FormatText(x.Str, f))
			case TypeBool:
				s, _ := c.text(x)
				return Str(s)
			}
			return textResult(c.Locale.Format(x.Num, f, c.Date1904))
		}),
		"NUMBERVALUE": fn(1, 3, func(c *Context, v []Value) Value {
			s, err := c.text(v[0])
			if err != nil {
				return *err
			}
			l := &Locale{Decimal: c.Locale.Decimal, Groups: c.Locale.Groups}
			if len(v) > 1 && v[1].Type != TypeBlank {
				d, err := c.text(v[1])
				if err != nil || d == "" {
					return ErrValue
				}
				l.Decimal = d[:1]
			}
			if len(v) > 2 && v[2].Type != TypeBlank {
				g, err := c.text(v[2])
				if err != nil {
					return ErrValue
				}
				l.Groups = []string{g}
			}
			n, ok := number(strings.ReplaceAll(s, " ", ""), l)
			if !ok {
				return ErrValue
			}
			return Num(n)
		}),
		"FIXED": fn(1, 3, func(c *Context, v []Value) Value {
			n, err := c.number(v[0])
			if err != nil {
				return *err
			}
			d := 2.0
			if len(v) > 1 && v[1].Type != TypeBlank {
				if d, err = c.number(v[1]); err != nil {
					return *err
				}
			}
			plain := false
			if len(v) > 2 {
				if plain, err = c.boolean(v[2]); err != nil {
					return *err
				}
			}
			code := "#,##0"
			if plain {
				code = "0"
			}
			if d > 0 {
				code += "." + strings.Repeat("0", min(int(d), 127))
			}
			n = roundWith(n, int(d), math.Round)
			return Str(c.Locale.Format(n, ParseFormat(code), c.Date1904))
		}),
		"DOLLAR": fn(1, 2, func(c *Context, v []Value) Value {
			n, err := c.number(v[0])
			if err != nil {
				return *err
			}
			d := 2.0
			if len(v) > 1 {
				if d, err = c.number(v[1]); err != nil {
					return *err
				}
			}
			code := "#,##0"
			if d > 0 {
				code += "." + strings.Repeat("0", min(int(d), 127))
			}
			n = roundWith(n, int(d), math.Round)
			if c.Locale.Decimal == "," {
				code = code + ` "` + c.Locale.Currency + `";-` + code + ` "` + c.Locale.Currency + `"`
			} else {
				code = `"` + c.Locale.Currency + `"` + code + `;("` + c.Locale.Currency + `"` + code + ")"
			}
			return Str(c.Locale.Format(n, ParseFormat(code), c.Date1904))
		}),
		"TEXTBEFORE": around(true),
		"TEXTAFTER":  around(false),
	})
	functions["VALUE"] = fn(1, 1, func(c *Context, v []Value) Value {
		x := c.scalar(v[0])
		switch x.Type {
		case TypeNumber, TypeError:
			return x
		case TypeBlank:
			return Num(0)
		case TypeBool:
			return ErrValue
		}
		s := strings.TrimSpace(x.Str)
		s = strings.TrimSpace(strings.TrimSuffix(strings.TrimPrefix(s, c.Locale.Currency), c.Locale.Currency))
		if n, ok := c.parseNumber(s); ok {
			return Num(n)
		}
		return ErrValue
	})
}

func textResult(s string) Value {
	if len(s) > maxText && len(utf16.Encode([]rune(s))) > maxText {
		return ErrValue
	}
	return Str(s)
}

func decode(u []uint16) string {
	return string(utf16.Decode(u))
}

func text1(f func(string) string) *function {
	return text1Value(func(s string) Value { return Str(f(s)) })
}

func text1Value(f func(string) Value) *function {
	return fn(1, 1, func(c *Context, v []Value) Value {
		return c.mapValues(v[0], func(x Value) Value {
			s, err := c.text(x)
			if err != nil {
				return *err
			}
			return f(s)
		})
	})
}

// cut is LEFT and RIGHT: n characters, 1 when left out.
func cut(f func(u []uint16, n int) []uint16) *function {
	return fn(1, 2, func(c *Context, v []Value) Value {
		s, err := c.text(v[0])
		if err != nil {
			return *err
		}
		n := 1.0
		if len(v) > 1 {
			if n, err = c.number(v[1]); err != nil {
				return *err
			}
		}
		if n < 0 {
			return ErrValue
		}
		return Str(decode(f(utf16.Encode([]rune(s)), int(n))))
	})
}

// find is FIND and SEARCH, which ignores case and takes wildcards.
func find(search bool) *function {
	return fn(2, 3, func(c *Context, v []Value) Value {
		what, err := c.text(v[0])
		if err != nil {
			return *err
		}
		in, err := c.text(v[1])
		if err != nil {
			return *err
		}
		start := 1.0
		if len(v) > 2 {
			if start, err = c.number(v[2]); err != nil {
				return *err
			}
		}
		u := utf16.Encode([]rune(in))
		if start < 1 || int(start) > len(u)+1 {
			return ErrValue
		}
		rest := decode(u[int(start)-1:])
		at := -1
		switch {
		case search && strings.ContainsAny(what, "*?~"):
			if loc := wildcardFind(what).FindStringIndex(rest); loc != nil {
				at = loc[0]
			}
		case search:
			at = strings.Index(strings.ToLower(rest), strings.ToLower(what))
		default:
			at = strings.Index(rest, what)
		}
		if at < 0 {
			return ErrValue
		}
		return Num(start + float64(len(utf16.Encode([]rune(rest[:at])))))
	})
}

// around is TEXTBEFORE and TEXTAFTER: the text before or after the n-th
// delimiter, counted from the end when n is negative.
func around(before bool) *function {
	return fn(2, 6, func(c *Context, v []Value) Value {
		s, err := c.text(v[0])
		if err != nil {
			return *err
		}
		d, err := c.text(v[1])
		if err != nil {
			return *err
		}
		n := 1.0
		if len(v) > 2 && v[2].Type != TypeBlank {
			if n, err = c.number(v[2]); err != nil {
				return *err
			}
		}
		fold := false
		if len(v) > 3 && v[3].Type != TypeBlank {
			m, err := c.number(v[3])
			if err != nil {
				return *err
			}
			fold = m == 1
		}
		if n == 0 || d == "" {
			return ErrValue
		}
		hay, needle := s, d
		if fold {
			hay, needle = strings.ToLower(s), strings.ToLower(d)
		}
		var at []int
		for i := 0; ; {
			j := strings.Index(hay[i:], needle)
			if j < 0 {
				break
			}
			at = append(at, i+j)
			i += j + len(needle)
		}
		k := int(n)
		if k < 0 {
			k = len(at) + k + 1
		}
		if k < 1 || k > len(at) {
			if len(v) > 5 {
				return v[5]
			}
			return ErrNA
		}
		i := at[k-1]
		if before {
			return Str(s[:i])
		}
		return Str(s[i+len(d):])
	})
}

// wildcardFind is the pattern of SEARCH, which finds text anywhere.
func wildcardFind(s string) *regexp.Regexp {
	return regexp.MustCompile("(?is)" + wildcardPattern(s))
}

// ansi is the character of a byte in Windows-1252, the code page CHAR
// and CODE count in.
func ansi(b byte) rune {
	if b >= 0x80 && b < 0xA0 {
		if r := cp1252[b-0x80]; r != 0 {
			return r
		}
	}
	return rune(b)
}

var cp1252 = [32]rune{
	0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
	0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178,
}

// invariant is a format code written in the locale made one of the file:
// "# ##0,00" and "jj/mm/aaaa" in French become "#,##0.00" and
// "dd/mm/yyyy".
func (l *Locale) invariant(code string) string {
	if l.Decimal != "," {
		return code
	}
	var b strings.Builder
	quoted := false
	for i := 0; i < len(code); i++ {
		c := code[i]
		switch {
		case c == '"':
			quoted = !quoted
			b.WriteByte(c)
		case quoted:
			b.WriteByte(c)
		case c == '\\' && i+1 < len(code):
			b.WriteByte(c)
			b.WriteByte(code[i+1])
			i++
		case c == '[':
			j := strings.IndexByte(code[i:], ']')
			if j < 0 {
				j = len(code) - i - 1
			}
			b.WriteString(code[i : i+j+1])
			i += j
		case c == ',':
			b.WriteByte('.')
		case c == '.':
			b.WriteByte(',')
		case c == ' ' && i > 0 && i+1 < len(code) && strings.IndexByte("#0?", code[i-1]) >= 0 && strings.IndexByte("#0?", code[i+1]) >= 0:
			b.WriteByte(',')
		case c == 'j' || c == 'J':
			b.WriteByte('d')
		case c == 'a' || c == 'A':
			if strings.HasPrefix(strings.ToLower(code[i:]), "am/pm") || strings.HasPrefix(strings.ToLower(code[i:]), "a/p") {
				b.WriteByte(c)
			} else {
				b.WriteByte('y')
			}
		default:
			b.WriteByte(c)
		}
	}
	return b.String()
}
