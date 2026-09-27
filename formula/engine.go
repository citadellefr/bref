package formula

import (
	"math/rand/v2"
	"slices"
	"strconv"
	"strings"
	"time"
)

// Pos is a cell of a workbook, its sheet given by the engine's handle.
type Pos struct{ Sheet, Row, Col int }

// Source is the workbook an engine calculates: the values its cells hold,
// the last calculated of those with a formula.
type Source interface {
	Value(p Pos) Value
	// Each calls f with the cells of an area that hold a value or a
	// formula, row by row, until f returns false.
	Each(a Area3, f func(row, col int, v Value) bool)
	Size(sheet int) (rows, cols int)
	Sheets(first, last string) ([]int, bool)
	// Name is the formula of a defined name, local to sheet or global.
	Name(name string, sheet int) (string, bool)
}

// Options tunes an engine.
type Options struct {
	Locale   *Locale
	Date1904 bool
	// Now is the time of NOW and TODAY, in the workbook's time zone.
	Now  func() time.Time
	Rand func() float64
}

// Engine keeps the formulas of a workbook and calculates again those a
// change reaches, in the order they depend on each other.
type Engine struct {
	src      Source
	opt      Options
	formulas map[Pos]*cellFormula
	// readers are the formulas reading a cell by itself; areas those
	// reading a range, by column, or in wide when it spans many.
	readers  map[Pos][]Pos
	areas    map[[2]int][]areaReader
	wide     map[int][]areaReader
	volatile map[Pos]bool
	// arrays gives each cell of an array formula its anchor.
	arrays map[Pos]Pos

	// what a calculation knows
	dirty  map[Pos]bool
	values map[Pos]Value
	busy   map[Pos]bool
	names  map[string]Expr
	// bounds are, by sheet, the area of the formulas calculated, which
	// ranges outside read the source alone.
	bounds map[int]Area
}

type cellFormula struct {
	expr  Expr
	array *Area // the cells an array formula fills, from its anchor
	reads []Area3
}

type areaReader struct {
	area Area3
	pos  Pos
}

// wideColumns is how many columns an area may span and still be indexed
// column by column.
const wideColumns = 64

func NewEngine(src Source, opt Options) *Engine {
	if opt.Locale == nil {
		opt.Locale = French
	}
	if opt.Now == nil {
		opt.Now = time.Now
	}
	if opt.Rand == nil {
		opt.Rand = rand.Float64
	}
	return &Engine{src: src, opt: opt, formulas: map[Pos]*cellFormula{}, readers: map[Pos][]Pos{},
		areas: map[[2]int][]areaReader{}, wide: map[int][]areaReader{}, volatile: map[Pos]bool{}, arrays: map[Pos]Pos{}}
}

// Len is the number of formulas.
func (e *Engine) Len() int {
	return len(e.formulas)
}

// Set gives a cell a formula, or takes it away when f is "". An array
// formula fills array, its anchor the cell. A formula that does not read
// is kept with none.
func (e *Engine) Set(p Pos, f string, array *Area) {
	if old := e.formulas[p]; old != nil {
		e.unindex(p, old)
		delete(e.formulas, p)
	}
	if f == "" {
		return
	}
	x, err := Parse(f)
	if err != nil {
		return
	}
	cf := &cellFormula{expr: e.bind(x, p.Sheet), array: array}
	volatile := false
	e.reads(x, p.Sheet, 0, func(a Area3) { cf.reads = append(cf.reads, a) }, &volatile)
	e.formulas[p] = cf
	if volatile {
		e.volatile[p] = true
	}
	for _, a := range cf.reads {
		if a.R1 == a.R2 && a.C1 == a.C2 {
			q := Pos{a.Sheet, a.R1, a.C1}
			e.readers[q] = append(e.readers[q], p)
			continue
		}
		r := areaReader{a, p}
		if a.C2-a.C1 >= wideColumns {
			e.wide[a.Sheet] = append(e.wide[a.Sheet], r)
			continue
		}
		for c := a.C1; c <= a.C2; c++ {
			k := [2]int{a.Sheet, c}
			e.areas[k] = append(e.areas[k], r)
		}
	}
	if array != nil {
		for r := array.R1; r <= array.R2; r++ {
			for c := array.C1; c <= array.C2; c++ {
				e.arrays[Pos{p.Sheet, r, c}] = p
			}
		}
	}
}

func (e *Engine) unindex(p Pos, cf *cellFormula) {
	delete(e.volatile, p)
	for _, a := range cf.reads {
		if a.R1 == a.R2 && a.C1 == a.C2 {
			q := Pos{a.Sheet, a.R1, a.C1}
			e.readers[q] = slices.DeleteFunc(e.readers[q], func(x Pos) bool { return x == p })
			if len(e.readers[q]) == 0 {
				delete(e.readers, q)
			}
			continue
		}
		drop := func(list []areaReader) []areaReader {
			return slices.DeleteFunc(list, func(r areaReader) bool { return r.pos == p })
		}
		if a.C2-a.C1 >= wideColumns {
			e.wide[a.Sheet] = drop(e.wide[a.Sheet])
			continue
		}
		for c := a.C1; c <= a.C2; c++ {
			k := [2]int{a.Sheet, c}
			if e.areas[k] = drop(e.areas[k]); len(e.areas[k]) == 0 {
				delete(e.areas, k)
			}
		}
	}
	if cf.array != nil {
		for r := cf.array.R1; r <= cf.array.R2; r++ {
			for c := cf.array.C1; c <= cf.array.C2; c++ {
				if e.arrays[Pos{p.Sheet, r, c}] == p {
					delete(e.arrays, Pos{p.Sheet, r, c})
				}
			}
		}
	}
}

// reads calls f with the areas a formula reads, those of the names it
// uses included, and tells whether it calls a volatile function.
func (e *Engine) reads(x Expr, sheet, depth int, f func(Area3), volatile *bool) {
	switch x := x.(type) {
	case refExpr:
		r := x.ref
		if r.Invalid || r.Book != "" {
			return
		}
		sheets := []int{sheet}
		if r.Sheet != "" {
			var ok bool
			if sheets, ok = e.src.Sheets(r.Sheet, r.LastSheet); !ok {
				return
			}
		}
		for _, s := range sheets {
			f(Area3{s, r.Area})
		}
	case nameExpr:
		s := sheet
		if x.sheet != "" {
			if ss, ok := e.src.Sheets(x.sheet, ""); ok {
				s = ss[0]
			}
		}
		if text, ok := e.src.Name(x.name, s); ok && depth < maxDepth {
			if y, err := Parse(text); err == nil {
				e.reads(y, s, depth+1, f, volatile)
			}
		}
	case unaryExpr:
		e.reads(x.x, sheet, depth, f, volatile)
	case percentExpr:
		e.reads(x.x, sheet, depth, f, volatile)
	case spillExpr:
		e.reads(x.x, sheet, depth, f, volatile)
	case binaryExpr:
		e.reads(x.x, sheet, depth, f, volatile)
		e.reads(x.y, sheet, depth, f, volatile)
	case callExpr:
		if fn := functions[x.name]; fn != nil && fn.volatile {
			*volatile = true
		}
		for _, a := range x.args {
			e.reads(a, sheet, depth, f, volatile)
		}
	}
}

// bind resolves the sheets of the references of a formula on sheet, so
// that calculating it does not.
func (e *Engine) bind(x Expr, sheet int) Expr {
	switch x := x.(type) {
	case refExpr:
		r := x.ref
		if r.Invalid || r.Book != "" {
			return boundExpr{}
		}
		sheets := []int{sheet}
		if r.Sheet != "" {
			var ok bool
			if sheets, ok = e.src.Sheets(r.Sheet, r.LastSheet); !ok {
				return boundExpr{}
			}
		}
		refs := make([]Area3, len(sheets))
		for i, s := range sheets {
			refs[i] = Area3{s, r.Area}
		}
		return boundExpr{refs}
	case unaryExpr:
		x.x = e.bind(x.x, sheet)
		return x
	case percentExpr:
		x.x = e.bind(x.x, sheet)
		return x
	case spillExpr:
		x.x = e.bind(x.x, sheet)
		return x
	case binaryExpr:
		x.x, x.y = e.bind(x.x, sheet), e.bind(x.y, sheet)
		return x
	case callExpr:
		args := make([]Expr, len(x.args))
		for i, a := range x.args {
			args[i] = e.bind(a, sheet)
		}
		x.args = args
		return x
	}
	return x
}

// Result is a cell whose value a calculation changed.
type Result struct {
	Pos
	Value Value
}

// Recalc calculates again the formulas that read the cells changed, those
// that read them in turn, and the volatile ones, and returns the cells
// whose values changed. Cells whose formula was set count as changed.
// Formulas the engine cannot calculate keep their values.
func (e *Engine) Recalc(changed []Pos) []Result {
	e.dirty, e.values, e.busy = map[Pos]bool{}, map[Pos]Value{}, map[Pos]bool{}
	e.names = map[string]Expr{}
	e.bounds = map[int]Area{}
	defer func() { e.dirty, e.values, e.busy, e.names, e.bounds = nil, nil, nil, nil, nil }()

	edges := map[Pos][]Pos{}
	queue := slices.Clone(changed)
	for p := range e.volatile {
		queue = append(queue, p)
	}
	for _, p := range changed {
		if e.formulas[p] != nil {
			e.dirty[p] = true
		}
	}
	for p := range e.volatile {
		e.dirty[p] = true
	}
	seen := map[Pos]bool{}
	for len(queue) > 0 {
		p := queue[0]
		queue = queue[1:]
		if seen[p] {
			continue
		}
		seen[p] = true
		cells := []Pos{p}
		if cf := e.formulas[p]; cf != nil && cf.array != nil {
			cells = cells[:0]
			for r := cf.array.R1; r <= cf.array.R2; r++ {
				for c := cf.array.C1; c <= cf.array.C2; c++ {
					cells = append(cells, Pos{p.Sheet, r, c})
				}
			}
		}
		for _, q := range cells {
			e.readersOf(q, func(f Pos) {
				if e.formulas[p] != nil {
					edges[p] = append(edges[p], f)
				}
				if !e.dirty[f] {
					e.dirty[f] = true
					queue = append(queue, f)
				}
			})
		}
	}

	for p := range e.dirty {
		a := Area{R1: p.Row, C1: p.Col, R2: p.Row, C2: p.Col}
		if cf := e.formulas[p]; cf != nil && cf.array != nil {
			a = *cf.array
		}
		if b, ok := e.bounds[p.Sheet]; ok {
			a = Area{R1: min(a.R1, b.R1), C1: min(a.C1, b.C1), R2: max(a.R2, b.R2), C2: max(a.C2, b.C2)}
		}
		e.bounds[p.Sheet] = a
	}

	// the formulas in the order they read each other
	indegree := map[Pos]int{}
	for p := range e.dirty {
		indegree[p] += 0
		for _, f := range edges[p] {
			if f != p {
				indegree[f]++
			}
		}
	}
	var order, ready []Pos
	for p, n := range indegree {
		if n == 0 {
			ready = append(ready, p)
		}
	}
	slices.SortFunc(ready, comparePos)
	for len(ready) > 0 {
		p := ready[0]
		ready = ready[1:]
		order = append(order, p)
		for _, f := range edges[p] {
			if f == p {
				continue
			}
			if indegree[f]--; indegree[f] == 0 {
				ready = append(ready, f)
			}
		}
	}
	// what is left reads itself in a circle
	for p := range e.dirty {
		if indegree[p] > 0 {
			order = append(order, p)
		}
	}

	var out []Result
	for _, p := range order {
		e.compute(p)
	}
	for p, v := range e.values {
		if v.Type == TypeError && v.Str == ErrUnsupported.Str {
			continue
		}
		if !sameValue(v, e.src.Value(p)) {
			out = append(out, Result{p, v})
		}
	}
	slices.SortFunc(out, func(a, b Result) int { return comparePos(a.Pos, b.Pos) })
	return out
}

func comparePos(a, b Pos) int {
	switch {
	case a.Sheet != b.Sheet:
		return a.Sheet - b.Sheet
	case a.Row != b.Row:
		return a.Row - b.Row
	}
	return a.Col - b.Col
}

// readersOf calls f with the formulas reading a cell.
func (e *Engine) readersOf(p Pos, f func(Pos)) {
	for _, r := range e.readers[p] {
		f(r)
	}
	for _, r := range e.areas[[2]int{p.Sheet, p.Col}] {
		if r.area.Contains(p.Row, p.Col) {
			f(r.pos)
		}
	}
	for _, r := range e.wide[p.Sheet] {
		if r.area.Contains(p.Row, p.Col) {
			f(r.pos)
		}
	}
}

// compute calculates a formula, once per calculation; a formula read
// while it is being calculated reads 0, as Excel does in a circle.
func (e *Engine) compute(p Pos) {
	if _, done := e.values[p]; done || e.busy[p] {
		return
	}
	cf := e.formulas[p]
	if cf == nil {
		return
	}
	e.busy[p] = true
	c := &Context{Book: (*engineBook)(e), Sheet: p.Sheet, Row: p.Row, Col: p.Col, Locale: e.opt.Locale,
		Now: e.opt.Now(), Rand: e.opt.Rand, Date1904: e.opt.Date1904}
	v := c.Eval(cf.expr)
	delete(e.busy, p)
	if cf.array == nil {
		e.values[p] = cellValue(c.scalar(v))
		return
	}
	a := cf.array
	var t *Table
	if v.Type == TypeArray || v.Type == TypeRange {
		t = c.array(v)
	} else {
		t = &Table{Rows: 1, Cols: 1, Cells: []Value{v}}
	}
	for r := a.R1; r <= a.R2; r++ {
		for k := a.C1; k <= a.C2; k++ {
			i, j := r-a.R1, k-a.C1
			if t.Rows == 1 {
				i = 0
			}
			if t.Cols == 1 {
				j = 0
			}
			x := ErrNA
			if i < t.Rows && j < t.Cols {
				x = cellValue(t.At(i, j))
			}
			e.values[Pos{p.Sheet, r, k}] = x
		}
	}
}

// cellValue is a value as a cell holds it: an empty cell read gives 0.
func cellValue(v Value) Value {
	switch v.Type {
	case TypeBlank:
		return Num(0)
	case TypeArray, TypeRange:
		return ErrValue
	}
	return v
}

func sameValue(a, b Value) bool {
	return a.Type == b.Type && a.Num == b.Num && a.Str == b.Str
}

// engineBook is the workbook as the formulas being calculated read it:
// the values just calculated over those the source holds.
type engineBook Engine

func (b *engineBook) value(p Pos) Value {
	e := (*Engine)(b)
	if anchor, ok := e.arrays[p]; ok && e.dirty[anchor] {
		e.compute(anchor)
	} else if e.dirty[p] {
		e.compute(p)
	}
	if v, ok := e.values[p]; ok {
		if v.Type == TypeError && v.Str == ErrUnsupported.Str {
			return e.src.Value(p)
		}
		return v
	}
	if e.busy[p] {
		return Num(0)
	}
	return e.src.Value(p)
}

func (b *engineBook) Cell(sheet, row, col int) Value {
	return b.value(Pos{sheet, row, col})
}

func (b *engineBook) Cells(a Area3, f func(row, col int, v Value) bool) {
	e := (*Engine)(b)
	if d, ok := e.bounds[a.Sheet]; !ok || d.R2 < a.R1 || d.R1 > a.R2 || d.C2 < a.C1 || d.C1 > a.C2 {
		e.src.Each(a, func(row, col int, v Value) bool {
			return v.Type == TypeBlank || f(row, col, v)
		})
		return
	}
	e.src.Each(a, func(row, col int, v Value) bool {
		p := Pos{a.Sheet, row, col}
		if _, array := e.arrays[p]; array || e.dirty[p] {
			v = b.value(p)
		} else if x, ok := e.values[p]; ok {
			v = x
		}
		if v.Type == TypeBlank {
			return true
		}
		return f(row, col, v)
	})
}

func (b *engineBook) Size(sheet int) (int, int) {
	return b.src.Size(sheet)
}

func (b *engineBook) Sheets(first, last string) ([]int, bool) {
	return b.src.Sheets(first, last)
}

func (b *engineBook) Name(name string, sheet int) (Expr, bool) {
	key := strings.ToUpper(name) + "!" + strconv.Itoa(sheet)
	if x, ok := b.names[key]; ok {
		return x, x != nil
	}
	text, ok := b.src.Name(name, sheet)
	var x Expr
	if ok {
		x, _ = Parse(text)
	}
	b.names[key] = x
	return x, x != nil
}

// HasFormula tells whether a cell holds a formula, for ISFORMULA.
func (b *engineBook) HasFormula(sheet, row, col int) bool {
	_, ok := b.formulas[Pos{sheet, row, col}]
	return ok
}
