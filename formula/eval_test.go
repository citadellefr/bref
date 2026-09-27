package formula

import (
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

// mapBook is a workbook of values, sheets named in order.
type mapBook struct {
	sheets []string
	cells  map[[3]int]Value
	names  map[string]string
}

func (b *mapBook) Cell(s, r, c int) Value {
	return b.cells[[3]int{s, r, c}]
}

func (b *mapBook) Cells(a Area3, f func(row, col int, v Value) bool) {
	var keys [][3]int
	for k := range b.cells {
		if k[0] == a.Sheet && a.Contains(k[1], k[2]) {
			keys = append(keys, k)
		}
	}
	slices.SortFunc(keys, func(x, y [3]int) int {
		if x[1] != y[1] {
			return x[1] - y[1]
		}
		return x[2] - y[2]
	})
	for _, k := range keys {
		if !f(k[1], k[2], b.cells[k]) {
			return
		}
	}
}

func (b *mapBook) Size(s int) (int, int) {
	rows, cols := 0, 0
	for k := range b.cells {
		if k[0] == s {
			rows, cols = max(rows, k[1]), max(cols, k[2])
		}
	}
	return rows, cols
}

func (b *mapBook) Sheets(first, last string) ([]int, bool) {
	i := slices.IndexFunc(b.sheets, func(s string) bool { return strings.EqualFold(s, first) })
	if i < 0 {
		return nil, false
	}
	if last == "" {
		return []int{i}, true
	}
	j := slices.IndexFunc(b.sheets, func(s string) bool { return strings.EqualFold(s, last) })
	if j < 0 {
		return nil, false
	}
	var out []int
	for k := min(i, j); k <= max(i, j); k++ {
		out = append(out, k)
	}
	return out, true
}

func (b *mapBook) Name(name string, _ int) (Expr, bool) {
	f, ok := b.names[strings.ToUpper(name)]
	if !ok {
		return nil, false
	}
	e, err := Parse(f)
	return e, err == nil
}

// book is a workbook of the cells given by A1 names, on sheets "Feuil1"
// and "Data".
func book(cells map[string]any) *mapBook {
	b := &mapBook{sheets: []string{"Feuil1", "Data"}, cells: map[[3]int]Value{}, names: map[string]string{}}
	for name, v := range cells {
		sheet := 0
		if s, rest, ok := strings.Cut(name, "!"); ok {
			sheet = slices.Index(b.sheets, s)
			name = rest
		}
		r, c, ok := ParseCell(name)
		if !ok {
			panic(name)
		}
		var x Value
		switch v := v.(type) {
		case int:
			x = Num(float64(v))
		case float64:
			x = Num(v)
		case string:
			x = Str(v)
			if IsError(v) {
				x = Err(v)
			}
		case bool:
			x = Boolean(v)
		}
		b.cells[[3]int{sheet, r, c}] = x
	}
	return b
}

func eval(t *testing.T, b Book, l *Locale, f string) Value {
	t.Helper()
	e, err := Parse(f)
	if err != nil {
		t.Fatalf("%s: %v", f, err)
	}
	c := &Context{Book: b, Sheet: 0, Row: 20, Col: 10, Locale: l,
		Now: time.Date(2024, 12, 25, 18, 30, 0, 0, time.UTC), Rand: func() float64 { return 0.5 }}
	return c.scalar(c.Eval(e))
}

// show writes a value as a test expects it: numbers with 10 significant
// digits, text quoted.
func (v Value) show() string {
	switch v.Type {
	case TypeNumber:
		return strconv.FormatFloat(v.Num, 'g', 10, 64)
	case TypeText:
		return `"` + v.Str + `"`
	case TypeBool:
		if v.Num != 0 {
			return "TRUE"
		}
		return "FALSE"
	case TypeBlank:
		return "blank"
	}
	return v.Str
}

var sheet = map[string]any{
	"A1": 1, "A2": "2", "A3": true, "A4": 4, "A5": 5,
	"B1": "pomme", "B2": "poire", "B3": "abricot", "B4": "", "B5": "pomme",
	"C1": 10, "C2": 20, "C3": 30, "C4": 40, "C5": 50,
	"D1": 1, "D2": 3, "D3": 5, "D4": 7, "D5": 9,
	"E1":      "#N/A",
	"Data!A1": 100, "Data!A2": 200,
}

func TestEval(t *testing.T) {
	b := book(sheet)
	b.names["TAUX"] = "0.2"
	b.names["PRIX"] = "Feuil1!$C$1:$C$5"
	for f, want := range map[string]string{
		`1+2*3`:                               "7",
		`-2^2`:                                "4",
		`2^3^2`:                               "64",
		`10%`:                                 "0.1",
		`"a"&1.5`:                             `"a1,5"`,
		`"a"&TRUE`:                            `"aVRAI"`,
		`1/0`:                                 "#DIV/0!",
		`"1,5"*2`:                             "3",
		`"x"*2`:                               "#VALUE!",
		`A1+A2`:                               "3",
		`A3+1`:                                "2",
		`Z99+1`:                               "1",
		`Z99&"x"`:                             `"x"`,
		`1=1`:                                 "TRUE",
		`"a"="A"`:                             "TRUE",
		`"b">"A"`:                             "TRUE",
		`1<"a"`:                               "TRUE",
		`TRUE>"z"`:                            "TRUE",
		`Z99=0`:                               "TRUE",
		`Z99=""`:                              "TRUE",
		`Data!A1+Data!A2`:                     "300",
		`SUM(Feuil1:Data!A1)`:                 "101",
		`TAUX*C1`:                             "2",
		`SUM(PRIX)`:                           "150",
		`INCONNU+1`:                           "#NAME?",
		`SUM(A1:A5)`:                          "10",
		`SUM(1,"2",TRUE)`:                     "4",
		`SUM(A1:A5,E1)`:                       "#N/A",
		`SUM((A1,C1))`:                        "11",
		`SUM(A1:C5 C1:C3)`:                    "60",
		`SUM(A1:A2 C3:C4)`:                    "#NULL!",
		`SUM(A1:INDEX(A1:A5,2))`:              "1",
		`PRODUCT(C1:C2)`:                      "200",
		`AVERAGE(A1:A5)`:                      "3.333333333",
		`AVERAGEA(A1:A5)`:                     "2.2",
		`COUNT(A1:A5)`:                        "3",
		`COUNT(1,"2","x",TRUE)`:               "3",
		`COUNTA(A1:B5)`:                       "10",
		`COUNTBLANK(B1:B6)`:                   "2",
		`MAX(A1:A5)`:                          "5",
		`MIN(C1:C5,5)`:                        "5",
		`MAX(Z1:Z9)`:                          "0",
		`MEDIAN(C1:C4)`:                       "25",
		`LARGE(C1:C5,2)`:                      "40",
		`SMALL(C1:C5,2)`:                      "20",
		`RANK(C2,C1:C5)`:                      "4",
		`STDEV(C1:C5)`:                        "15.8113883",
		`VARP(C1:C5)`:                         "200",
		`PERCENTILE(C1:C5,0.3)`:               "22",
		`QUARTILE(C1:C5,1)`:                   "20",
		`MODE(1,2,2,3)`:                       "2",
		`CORREL(C1:C5,D1:D5)`:                 "1",
		`SLOPE(C1:C5,D1:D5)`:                  "5",
		`INTERCEPT(C1:C5,D1:D5)`:              "5",
		`COUNTIF(B1:B5,"pomme")`:              "2",
		`COUNTIF(B1:B5,"p*")`:                 "3",
		`COUNTIF(B1:B5,"?oire")`:              "1",
		`COUNTIF(C1:C5,">20")`:                "3",
		`COUNTIF(C1:C5,"<>20")`:               "4",
		`COUNTIF(B1:B6,"")`:                   "2",
		`COUNTIF(A1:A5,1)`:                    "1",
		`SUMIF(B1:B5,"pomme",C1:C5)`:          "60",
		`SUMIF(C1:C5,">=30")`:                 "120",
		`SUMIFS(C1:C5,B1:B5,"p*",D1:D5,">1")`: "70",
		`COUNTIFS(B1:B5,"pomme",C1:C5,">10")`: "1",
		`AVERAGEIF(B1:B5,"pomme",C1:C5)`:      "30",
		`MAXIFS(C1:C5,B1:B5,"p*")`:            "50",
		`MINIFS(C1:C5,B1:B5,"p*")`:            "10",
		`SUMPRODUCT(C1:C3,D1:D3)`:             "220",
		`SUMPRODUCT((B1:B5="pomme")*C1:C5)`:   "60",
		`SUBTOTAL(9,C1:C5)`:                   "150",
		`ABS(-3)`:                             "3",
		`ROUND(2.675,2)`:                      "2.68",
		`ROUND(-2.5,0)`:                       "-3",
		`ROUND(1234.5,-2)`:                    "1200",
		`ROUNDUP(2.01,1)`:                     "2.1",
		`ROUNDDOWN(-2.99,1)`:                  "-2.9",
		`MROUND(10,3)`:                        "9",
		`CEILING(2.1,0.5)`:                    "2.5",
		`FLOOR(2.9,0.5)`:                      "2.5",
		`CEILING.MATH(-5.5,2)`:                "-4",
		`FLOOR.MATH(-5.5,2)`:                  "-6",
		`INT(-2.5)`:                           "-3",
		`TRUNC(-2.5)`:                         "-2",
		`MOD(-3,2)`:                           "1",
		`MOD(3,-2)`:                           "-1",
		`EVEN(1.5)`:                           "2",
		`ODD(-1.5)`:                           "-3",
		`SQRT(-1)`:                            "#NUM!",
		`POWER(2,10)`:                         "1024",
		`LOG(8,2)`:                            "3",
		`LN(EXP(2))`:                          "2",
		`FACT(5)`:                             "120",
		`COMBIN(5,2)`:                         "10",
		`GCD(12,18)`:                          "6",
		`LCM(4,6)`:                            "12",
		`PI()`:                                "3.141592654",
		`RAND()`:                              "0.5",
		`RANDBETWEEN(1,10)`:                   "6",
		`IF(A1>0,"pos","neg")`:                `"pos"`,
		`IF(A1<0,"pos")`:                      "FALSE",
		`IF(A1>0,,1)`:                         "0",
		`IFERROR(1/0,"x")`:                    `"x"`,
		`IFNA(E1,"manque")`:                   `"manque"`,
		`IFS(A1>5,"a",A1>0,"b")`:              `"b"`,
		`AND(TRUE,1,A1:A5)`:                   "TRUE",
		`OR(FALSE,0)`:                         "FALSE",
		`XOR(TRUE,TRUE)`:                      "FALSE",
		`NOT(0)`:                              "TRUE",
		`AND("VRAI",TRUE)`:                    "TRUE",
		`SWITCH(2,1,"un",2,"deux","autre")`:   `"deux"`,
		`CHOOSE(2,"a","b","c")`:               `"b"`,
		`ISBLANK(Z1)`:                         "TRUE",
		`ISNUMBER(A2)`:                        "FALSE",
		`ISTEXT(A2)`:                          "TRUE",
		`ISERROR(E1)`:                         "TRUE",
		`ISNA(E1)`:                            "TRUE",
		`ISERR(E1)`:                           "FALSE",
		`ISEVEN(4)`:                           "TRUE",
		`ISREF(A1)`:                           "TRUE",
		`TYPE("a")`:                           "2",
		`N(TRUE)`:                             "1",
		`ERROR.TYPE(1/0)`:                     "2",
		`LEFT("Bonjour",3)`:                   `"Bon"`,
		`RIGHT("Bonjour",4)`:                  `"jour"`,
		`MID("Bonjour",4,2)`:                  `"jo"`,
		`LEN("é😀")`:                           "3",
		`UPPER("été")`:                        `"ÉTÉ"`,
		`PROPER("jean-pierre dupont")`:        `"Jean-Pierre Dupont"`,
		`TRIM("  a   b  ")`:                   `"a b"`,
		`SUBSTITUTE("a-b-c","-","+")`:         `"a+b+c"`,
		`SUBSTITUTE("a-b-c","-","+",2)`:       `"a-b+c"`,
		`REPLACE("abcdef",2,3,"X")`:           `"aXef"`,
		`FIND("o","Bonjour")`:                 "2",
		`FIND("O","Bonjour")`:                 "#VALUE!",
		`SEARCH("J*R","bonjour")`:             "4",
		`SEARCH("o","Bonjour",3)`:             "5",
		`REPT("ab",3)`:                        `"ababab"`,
		`EXACT("a","A")`:                      "FALSE",
		`CHAR(128)`:                           `"€"`,
		`CODE("€")`:                           "128",
		`UNICODE("😀")`:                        "128512",
		`CONCATENATE("a",1,TRUE)`:             `"a1VRAI"`,
		`CONCAT(B1:B3)`:                       `"pommepoireabricot"`,
		`TEXTJOIN(", ",TRUE,B1:B5)`:           `"pomme, poire, abricot, pomme"`,
		`TEXTBEFORE("a.b.c",".")`:             `"a"`,
		`TEXTAFTER("a.b.c",".",-1)`:           `"c"`,
		`VALUE("1 234,5")`:                    "1234.5",
		`VALUE("25/12/2024")`:                 "45651",
		`VALUE("12:30")`:                      "0.5208333333",
		`VALUE("50%")`:                        "0.5",
		`VALUE("abc")`:                        "#VALUE!",
		`NUMBERVALUE("1.234,5",",",".")`:      "1234.5",
		`T(1)`:                                `""`,
		`DATE(2024,1,1)`:                      "45292",
		`DATE(2024,2,30)`:                     "45352",
		`DATE(24,1,1)`:                        "8767",
		`DATE(1900,3,1)`:                      "61",
		`DATE(1900,2,28)`:                     "59",
		`TIME(12,30,0)`:                       "0.5208333333",
		`YEAR(45651)`:                         "2024",
		`MONTH(45651)`:                        "12",
		`DAY(60)`:                             "29",
		`DAY(61)`:                             "1",
		`HOUR(0.75)`:                          "18",
		`MINUTE(0.5208333333)`:                "30",
		`WEEKDAY(45651)`:                      "4",
		`WEEKDAY(45651,2)`:                    "3",
		`WEEKNUM(45651)`:                      "52",
		`ISOWEEKNUM(DATE(2024,12,30))`:        "1",
		`EDATE(DATE(2024,1,31),1)`:            "45351",
		`EDATE(DATE(2024,3,31),-13)`:          "44985",
		`EOMONTH(DATE(2024,1,15),1)`:          "45351",
		`EOMONTH(DATE(2024,1,15),-1)`:         "45291",
		`DATEDIF(DATE(2020,1,15),DATE(2024,3,10),"Y")`:                    "4",
		`DATEDIF(DATE(2020,1,15),DATE(2024,3,10),"M")`:                    "49",
		`DATEDIF(DATE(2020,1,15),DATE(2024,3,10),"MD")`:                   "24",
		`DATEDIF(DATE(2020,1,15),DATE(2024,3,10),"YD")`:                   "55",
		`DAYS(DATE(2024,3,1),DATE(2024,2,1))`:                             "29",
		`DAYS360(DATE(2024,1,31),DATE(2024,3,31))`:                        "60",
		`NETWORKDAYS(DATE(2024,12,23),DATE(2024,12,31),DATE(2024,12,25))`: "6",
		`WORKDAY(DATE(2024,12,20),3)`:                                     "45651",
		`YEARFRAC(DATE(2024,1,1),DATE(2024,7,1))`:                         "0.5",
		`DATEVALUE("25 déc. 2024")`:                                       "45651",
		`TODAY()`:                                                         "45651",
		`NOW()`:                                                           "45651.77083",
		`TEXT(1234.567,"# ##0,00")`:                                       `"1` + string(rune(0x202f)) + `234,57"`,
		`TEXT(0.5,"0%")`:                                                  `"50%"`,
		`TEXT(DATE(2024,12,25),"jj/mm/aaaa")`:                             `"25/12/2024"`,
		`TEXT(DATE(2024,12,25),"dddd d mmmm yyyy")`:                       `"mercredi 25 décembre 2024"`,
		`TEXT("12","0,0")`:                                                `"12,0"`,
		`FIXED(1234.567,1)`:                                               `"1` + string(rune(0x202f)) + `234,6"`,
		`VLOOKUP("poire",B1:C5,2,FALSE)`:                                  "20",
		`VLOOKUP("p*e",B1:C5,2,FALSE)`:                                    "10",
		`VLOOKUP(6,D1:D5,1)`:                                              "5",
		`VLOOKUP(0,D1:D5,1)`:                                              "#N/A",
		`VLOOKUP("kiwi",B1:C5,2,FALSE)`:                                   "#N/A",
		`VLOOKUP("poire",B1:C5,3,FALSE)`:                                  "#REF!",
		`HLOOKUP(20,C1:C5,1,FALSE)`:                                       "#N/A",
		`MATCH(5,D1:D5,0)`:                                                "3",
		`MATCH(6,D1:D5)`:                                                  "3",
		`MATCH(30,C1:C5,0)`:                                               "3",
		`MATCH("abricot",B1:B5,0)`:                                        "3",
		`INDEX(C1:C5,3)`:                                                  "30",
		`INDEX(B1:C5,2,2)`:                                                "20",
		`SUM(INDEX(C1:D5,0,2))`:                                           "25",
		`XLOOKUP("poire",B1:B5,C1:C5)`:                                    "20",
		`XLOOKUP("kiwi",B1:B5,C1:C5,"aucun")`:                             `"aucun"`,
		`XLOOKUP(6,D1:D5,C1:C5,,-1)`:                                      "30",
		`XLOOKUP(6,D1:D5,C1:C5,,1)`:                                       "40",
		`XLOOKUP("pomme",B1:B5,C1:C5,,0,-1)`:                              "50",
		`XMATCH(7,D1:D5)`:                                                 "4",
		`LOOKUP(6,D1:D5,C1:C5)`:                                           "30",
		`ROW(C3)`:                                                         "3",
		`ROW()`:                                                           "20",
		`COLUMN(C3)`:                                                      "3",
		`ROWS(A1:C5)`:                                                     "5",
		`COLUMNS(A1:C5)`:                                                  "3",
		`SUM(OFFSET(C1,1,0,2,1))`:                                         "50",
		`INDIRECT("C2")`:                                                  "20",
		`SUM(INDIRECT("Data!A1:A2"))`:                                     "300",
		`ADDRESS(2,3)`:                                                    `"$C$2"`,
		`ADDRESS(2,3,4,TRUE,"Ma feuille")`:                                `"'Ma feuille'!C2"`,
		`SUM(TRANSPOSE(C1:C3))`:                                           "60",
		`PMT(0.05/12,60,10000)`:                                           "-188.7123364",
		`ROUND(FV(0.06/12,10,-200,-500,1),2)`:                             "2581.4",
		`ROUND(PV(0.08/12,240,500),2)`:                                    "-59777.15",
		`ROUND(NPER(0.12/12,-100,-1000,10000,1),4)`:                       "59.6739",
		`ROUND(RATE(60,-188.7123364,10000)*12,6)`:                         "0.05",
		`IPMT(0.1/12,1,36,8000)`:                                          "-66.66666667",
		`ROUND(PPMT(0.1/12,1,24,2000),2)`:                                 "-75.62",
		`ROUND(NPV(0.1,-10000,3000,4200,6800),2)`:                         "1188.44",
		`ROUND(IRR({-70000,12000,15000,18000,21000,26000}),4)`:            "0.0866",
		`SLN(30000,7500,10)`:                                              "2250",
		`SUM({1,2;3,4})`:                                                  "10",
		`SUM({1,2}*{3,4})`:                                                "11",
		`NOSUCHFUNCTION(1)`:                                               "#UNSUPPORTED",
	} {
		if got := eval(t, b, French, f).show(); got != want {
			t.Errorf("%s = %s, want %s", f, got, want)
		}
	}
}
