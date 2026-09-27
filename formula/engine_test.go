package formula

import (
	"fmt"
	"testing"
	"time"
)

// sheetSource is a workbook of values and formulas for an engine, on the
// sheets of mapBook, whose formulas' values it keeps up to date.
type sheetSource struct {
	*mapBook
	formulas map[Pos]string
}

func (s *sheetSource) Value(p Pos) Value {
	return s.cells[[3]int{p.Sheet, p.Row, p.Col}]
}

func (s *sheetSource) Each(a Area3, f func(row, col int, v Value) bool) {
	s.Cells(a, f)
}

func (s *sheetSource) Name(name string, sheet int) (string, bool) {
	f, ok := s.names[name]
	return f, ok
}

func (s *sheetSource) set(e *Engine, cell string, v any) []Result {
	r, c, _ := ParseCell(cell)
	p := Pos{0, r, c}
	switch v := v.(type) {
	case string:
		if len(v) > 0 && v[0] == '=' {
			s.formulas[p] = v[1:]
			e.Set(p, v[1:], nil)
		} else {
			s.cells[[3]int{0, r, c}] = Str(v)
		}
	case int:
		s.cells[[3]int{0, r, c}] = Num(float64(v))
	}
	out := e.Recalc([]Pos{p})
	for _, x := range out {
		s.cells[[3]int{x.Sheet, x.Row, x.Col}] = x.Value
	}
	return out
}

func newSource() (*sheetSource, *Engine) {
	s := &sheetSource{mapBook: book(nil), formulas: map[Pos]string{}}
	e := NewEngine(s, Options{Now: func() time.Time { return time.Date(2024, 12, 25, 12, 0, 0, 0, time.UTC) }})
	return s, e
}

func results(out []Result) string {
	var b []string
	for _, r := range out {
		b = append(b, fmt.Sprintf("%s=%s", CellName(r.Row, r.Col), r.Value.show()))
	}
	return fmt.Sprint(b)
}

func TestEngine(t *testing.T) {
	s, e := newSource()
	s.set(e, "A1", 1)
	if got := results(s.set(e, "B1", "=A1*2")); got != "[B1=2]" {
		t.Fatal(got)
	}
	if got := results(s.set(e, "C1", "=SUM(A1:B1)")); got != "[C1=3]" {
		t.Fatal(got)
	}
	if got := results(s.set(e, "A1", 5)); got != "[B1=10 C1=15]" {
		t.Fatal(got)
	}
	// a change that leaves a value alone reports nothing for it
	s.set(e, "D1", "=IF(A1>0,1,0)")
	if got := results(s.set(e, "A1", 6)); got != "[B1=12 C1=18]" {
		t.Fatal(got)
	}
	// a formula taken away is no longer calculated
	delete(s.formulas, Pos{0, 1, 2})
	e.Set(Pos{0, 1, 2}, "", nil)
	if got := results(s.set(e, "A1", 7)); got != "[C1=19]" {
		t.Fatal(got)
	}
	// circles end, reading 0
	s.set(e, "E1", "=F1+1")
	s.set(e, "F1", "=E1+1")
	if got := results(s.set(e, "A1", 8)); got != "[C1=20]" {
		t.Fatal(got)
	}
	// unknown functions keep their values
	s.cells[[3]int{0, 1, 7}] = Num(42)
	s.set(e, "G1", "=NOSUCH(A1)+1")
	s.set(e, "H1", "=G1*2")
	if got := s.Value(Pos{0, 1, 8}).show(); got != "84" {
		t.Fatalf("H1 = %s", got)
	}
	// volatile functions are calculated each time
	s.set(e, "I1", "=NOW()")
	if got := results(s.set(e, "Z9", 1)); got != "[]" {
		t.Fatal(got)
	}
}

func TestEngineArray(t *testing.T) {
	s, e := newSource()
	for i, v := range []int{1, 2, 3} {
		s.set(e, fmt.Sprintf("A%d", i+1), v)
	}
	e.Set(Pos{0, 1, 2}, "A1:A3*10", &Area{R1: 1, C1: 2, R2: 3, C2: 2})
	out := e.Recalc([]Pos{{0, 1, 2}})
	if got := results(out); got != "[B1=10 B2=20 B3=30]" {
		t.Fatal(got)
	}
	for _, r := range out {
		s.cells[[3]int{r.Sheet, r.Row, r.Col}] = r.Value
	}
	s.set(e, "C1", "=SUM(B1:B3)")
	if got := results(s.set(e, "A2", 5)); got != "[C1=90 B2=50]" {
		t.Fatal(got)
	}
}

// A chain of formulas, each reading the one before, is calculated in order
// whatever its length.
func TestEngineChain(t *testing.T) {
	s, e := newSource()
	s.set(e, "A1", 1)
	const n = 20000
	for i := 2; i <= n; i++ {
		p := Pos{0, i, 1}
		e.Set(p, fmt.Sprintf("A%d+1", i-1), nil)
		s.cells[[3]int{0, i, 1}] = Num(float64(i))
	}
	start := time.Now()
	out := s.set(e, "A1", 10)
	if len(out) != n-1 || out[len(out)-1].Value.Num != n+9 {
		t.Fatalf("%d results, last %v", len(out), out[len(out)-1])
	}
	t.Logf("%d formulas in %v", n, time.Since(start))
}

// gridSource finds the cells of an area as the grid of a sheet does, row
// by row.
type gridSource struct {
	*sheetSource
}

func (g gridSource) Each(a Area3, f func(row, col int, v Value) bool) {
	rows, cols := g.Size(a.Sheet)
	for r := a.R1; r <= min(a.R2, rows); r++ {
		for c := a.C1; c <= min(a.C2, cols); c++ {
			if v, ok := g.cells[[3]int{a.Sheet, r, c}]; ok && !f(r, c, v) {
				return
			}
		}
	}
}

func (g gridSource) Size(int) (int, int) {
	return 10000, 2
}

// 10 000 formulas read the cell changed.
func BenchmarkRecalc(b *testing.B) {
	s, _ := newSource()
	e := NewEngine(gridSource{s}, Options{})
	s.cells[[3]int{0, 1, 1}] = Num(1)
	for i := 1; i <= 10000; i++ {
		s.cells[[3]int{0, i, 1}] = Num(float64(i))
		e.Set(Pos{0, i, 2}, fmt.Sprintf("$A$1*%d+SUM(A1:A%d)", i, min(i, 50)), nil)
	}
	for b.Loop() {
		s.cells[[3]int{0, 1, 1}] = Num(float64(b.N))
		if len(e.Recalc([]Pos{{0, 1, 1}})) != 10000 {
			b.Fatal("not all calculated")
		}
	}
}
