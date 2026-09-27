package formula

import (
	"strings"
	"testing"
)

func TestFormat(t *testing.T) {
	nnbsp := string(rune(0x202f))
	for _, c := range []struct {
		l    *Locale
		n    float64
		code string
		want string
	}{
		{English, 1234.567, "#,##0.00", "1,234.57"},
		{English, -1234.567, "#,##0.00;[Red](#,##0.00)", "(1,234.57)"},
		{English, 0, `0.00;-0.00;"zero"`, "zero"},
		{English, -5, "0", "-5"},
		{English, -5, "0;0", "5"},
		{English, -0.001, "0.00", "0.00"},
		{English, 0.25, "0%", "25%"},
		{English, 0.1234, "0.0%", "12.3%"},
		{English, 12345.678, "0.00E+00", "1.23E+04"},
		{English, 0.000123, "0.00E+00", "1.23E-04"},
		{English, 12345, "##0.0E+0", "12.3E+3"},
		{English, 1.5, "# ?/?", "1 1/2"},
		{English, 0.75, "?/4", "3/4"},
		{English, 2, "# ?/?", "2    "},
		{English, 0.333, "# ??/??", "  1/3 "},
		{English, 5, "000", "005"},
		{English, 1234567, "#,##0,", "1,235"},
		{English, 1234567, "0.0,,", "1.2"},
		{English, 3.14159, "#.##", "3.14"},
		{English, 3, "#.##", "3."},
		{English, 0.5, "#.##", ".5"},
		{English, 0, "#", ""},
		{English, 1.5, "0.0?", "1.5 "},
		{English, 123, `"$"#,##0`, "$123"},
		{English, 1234, `[$€-40C] #,##0`, "€ 1,234"},
		{English, 1234.5, "General", "1234.5"},
		{English, 100, `[>=100]"big";"small"`, "big"},
		{English, 5, `[>=100]"big";"small"`, "small"},
		{English, 12, `0 "kg"`, "12 kg"},
		{English, 12, `0\ \k\g`, "12 kg"},
		{English, 1234, "0_);(0)", "1234 "},
		{English, 5551234, "000-0000", "555-1234"},
		{English, 45651, "dd/mm/yyyy", "25/12/2024"},
		{English, 45651, "mmm d, yyyy", "Dec 25, 2024"},
		{English, 45651, "dddd", "Wednesday"},
		{English, 45651.75, "hh:mm", "18:00"},
		{English, 45651.75, "h:mm AM/PM", "6:00 PM"},
		{English, 45651.0000115741, "h:mm:ss", "0:00:01"},
		{English, 0.5000057870, "hh:mm:ss.00", "12:00:00.50"},
		{English, 1.5, "[h]:mm", "36:00"},
		{English, 0.0625, "[mm]:ss", "90:00"},
		{English, 45651, "yy-m-d", "24-12-25"},
		{French, 1234.567, "#,##0.00", "1" + nnbsp + "234,57"},
		{French, 1234.5, `#,##0.00 "€"`, "1" + nnbsp + "234,50 €"},
		{French, 45651, "dddd d mmmm yyyy", "mercredi 25 décembre 2024"},
		{French, 45651, "d mmm yy", "25 déc. 24"},
		{French, 0.5, "0,00%", "50,00%"},
		{French, 1234.5, "General", "1234,5"},
	} {
		code := c.code
		if c.l == French {
			code = strings.ReplaceAll(code, "0,00%", "0.00%")
		}
		if got := c.l.Format(c.n, ParseFormat(code), false); got != c.want {
			t.Errorf("%v with %q = %q, want %q", c.n, c.code, got, c.want)
		}
	}
	for _, c := range []struct{ text, code, want string }{
		{"abc", `@ "x"`, "abc x"},
		{"abc", "0.00", "abc"},
		{"abc", `0;0;0;"<"@">"`, "<abc>"},
	} {
		if got := English.FormatText(c.text, ParseFormat(c.code)); got != c.want {
			t.Errorf("%q with %q = %q, want %q", c.text, c.code, got, c.want)
		}
	}
}
