package formula

import (
	"fmt"
	"strings"
	"testing"
)

// show writes a tree with every operation in parentheses.
func show(e Expr) string {
	switch e := e.(type) {
	case numberExpr:
		return fmt.Sprint(float64(e))
	case textExpr:
		return fmt.Sprintf("%q", string(e))
	case boolExpr:
		return fmt.Sprint(bool(e))
	case errorExpr:
		return string(e)
	case refExpr:
		return e.ref.String()
	case nameExpr:
		if e.sheet != "" {
			return e.sheet + "!" + e.name
		}
		return e.name
	case unaryExpr:
		return "(" + string(e.op) + show(e.x) + ")"
	case percentExpr:
		return "(" + show(e.x) + "%)"
	case spillExpr:
		return "(" + show(e.x) + "#)"
	case binaryExpr:
		return "(" + show(e.x) + e.op + show(e.y) + ")"
	case callExpr:
		var args []string
		for _, a := range e.args {
			args = append(args, show(a))
		}
		return e.name + "(" + strings.Join(args, ";") + ")"
	case arrayExpr:
		var cells []string
		for _, c := range e.cells {
			cells = append(cells, show(c))
		}
		return fmt.Sprintf("{%dx%d:%s}", e.rows, e.cols, strings.Join(cells, ","))
	case missingExpr:
		return "_"
	}
	return "?"
}

func TestParse(t *testing.T) {
	for f, want := range map[string]string{
		`1+2*3`:                        "(1+(2*3))",
		`-2^2`:                         "((-2)^2)",
		`2^3^2`:                        "((2^3)^2)",
		`2^50%`:                        "(2^(50%))",
		`A1&"x"="y"`:                   `((A1&"x")="y")`,
		`SUM(A1:B2, Sheet2!C3)`:        "SUM(A1:B2;Sheet2!C3)",
		`IF(A1,,2)`:                    "IF(A1;_;2)",
		`PI()`:                         "PI()",
		`_xlfn.XLOOKUP(1,A:A,B:B)`:     "XLOOKUP(1;A:A;B:B)",
		`SUM((A1,B2))`:                 "SUM((A1,B2))",
		`SUM(A1:B5 B2:C3)`:             "SUM((A1:B5 B2:C3))",
		`A1 + B1`:                      "(A1+B1)",
		`{1,2;-3,"a"}`:                 `{2x2:1,2,-3,"a"}`,
		`A1:INDEX(B:B,2)`:              "(A1:INDEX(B:B;2))",
		`Total*Data!Rate`:              "(Total*Data!Rate)",
		`@A1:A3+A1#`:                   "((@A1:A3)+(A1#))",
		`"say ""hi"""`:                 `"say \"hi\""`,
		`1<=2`:                         "(1<=2)",
		`#DIV/0!+1`:                    "(#DIV/0!+1)",
		`'Q1 ''24'!A1*-B2`:             "('Q1 ''24'!A1*(-B2))",
		`SUM(1,2)-MAX(IF(A1>0,1,0),3)`: "(SUM(1;2)-MAX(IF((A1>0);1;0);3))",
	} {
		e, err := Parse(f)
		if err != nil {
			t.Errorf("%s: %v", f, err)
			continue
		}
		if got := show(e); got != want {
			t.Errorf("%s: %s, want %s", f, got, want)
		}
	}
	for _, f := range []string{``, `1+`, `SUM(1`, `(1`, `{1,2;3}`, `1 2`, `)`} {
		if _, err := Parse(f); err == nil {
			t.Errorf("%s: no error", f)
		}
	}
}
