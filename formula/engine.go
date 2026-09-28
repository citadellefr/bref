package formula

import (
	"math"
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
	readers  map[Pos][]*cellFormula
	areas    map[[2]int][]areaReader
	wide     map[int][]areaReader
	volatile map[Pos]bool
	// arrays gives each cell of an array formula its anchor.
	arrays map[Pos]Pos

	// what a calculation knows, besides what its formulas hold
	dirty []*cellFormula
	// filled are the values of the cells of the array formulas calculated.
	filled map[Pos]Value
	names  map[string]Expr
	// bounds are, by sheet, the area of the formulas calculated, which
	// ranges outside read the source alone.
	bounds map[int]Area
	// ranges are the cells of the areas outside bounds read more than
	// once, kept up to cachedCells in all: many formulas read the same.
	ranges map[Area3][]cachedCell
	cached int
}

type cachedCell struct {
	row, col int32
	typ      Type
	num      float64
	str      string
}

// cachedCells bounds what a calculation keeps of the areas it reads.
const cachedCells = 1 << 18

type cellFormula struct {
	pos   Pos
	expr  Expr
	array *Area // the cells an array formula fills, from its anchor
	reads []Area3
	calc
}

// calc is what a calculation knows of a formula, cleared once it is over.
type calc struct {
	dirty, busy, done bool
	// readers are the formulas reading this one, pending those not
	// calculated yet among the formulas it reads.
	readers []*cellFormula
	pending int
	value   Value
}

type areaReader struct {
	area Area3
	f    *cellFormula
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
	return &Engine{src: src, opt: opt, formulas: map[Pos]*cellFormula{}, readers: map[Pos][]*cellFormula{},
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
	cf := &cellFormula{pos: p, expr: e.bind(x, p.Sheet), array: array}
	volatile := false
	e.reads(x, p.Sheet, 0, func(a Area3) { cf.reads = append(cf.reads, a) }, &volatile)
	e.formulas[p] = cf
	if volatile {
		e.volatile[p] = true
	}
	for _, a := range cf.reads {
		if a.R1 == a.R2 && a.C1 == a.C2 {
			q := Pos{a.Sheet, a.R1, a.C1}
			e.readers[q] = append(e.readers[q], cf)
			continue
		}
		r := areaReader{a, cf}
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
			e.readers[q] = slices.DeleteFunc(e.readers[q], func(x *cellFormula) bool { return x == cf })
			if len(e.readers[q]) == 0 {
				delete(e.readers, q)
			}
			continue
		}
		drop := func(list []areaReader) []areaReader {
			return slices.DeleteFunc(list, func(r areaReader) bool { return r.f == cf })
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
	e.filled, e.names = map[Pos]Value{}, map[string]Expr{}
	e.bounds = map[int]Area{}
	e.ranges, e.cached = map[Area3][]cachedCell{}, 0
	defer func() {
		for _, cf := range e.dirty {
			cf.calc = calc{}
		}
		e.dirty, e.filled, e.names, e.bounds, e.ranges = nil, nil, nil, nil, nil
	}()

	mark := func(cf *cellFormula) {
		if !cf.dirty {
			cf.dirty = true
			e.dirty = append(e.dirty, cf)
		}
	}
	for _, p := range changed {
		if cf := e.formulas[p]; cf != nil {
			mark(cf)
			continue
		}
		e.readersOf(p, mark)
	}
	for p := range e.volatile {
		mark(e.formulas[p])
	}
	// the formulas the dirty ones reach, which join them
	for i := 0; i < len(e.dirty); i++ {
		cf := e.dirty[i]
		e.cellsOf(cf, func(q Pos) {
			e.readersOf(q, func(f *cellFormula) {
				cf.readers = append(cf.readers, f)
				mark(f)
			})
		})
	}

	for _, cf := range e.dirty {
		p := cf.pos
		a := Area{R1: p.Row, C1: p.Col, R2: p.Row, C2: p.Col}
		if cf.array != nil {
			a = *cf.array
		}
		if b, ok := e.bounds[p.Sheet]; ok {
			a = Area{R1: min(a.R1, b.R1), C1: min(a.C1, b.C1), R2: max(a.R2, b.R2), C2: max(a.C2, b.C2)}
		}
		e.bounds[p.Sheet] = a
	}

	// the formulas in the order they read each other
	for _, cf := range e.dirty {
		for _, f := range cf.readers {
			if f != cf {
				f.pending++
			}
		}
	}
	var ready []*cellFormula
	for _, cf := range e.dirty {
		if cf.pending == 0 {
			ready = append(ready, cf)
		}
	}
	slices.SortFunc(ready, func(a, b *cellFormula) int { return comparePos(a.pos, b.pos) })
	for len(ready) > 0 {
		cf := ready[0]
		ready = ready[1:]
		e.compute(cf)
		for _, f := range cf.readers {
			if f == cf {
				continue
			}
			if f.pending--; f.pending == 0 {
				ready = append(ready, f)
			}
		}
	}
	// what is left reads itself in a circle
	for _, cf := range e.dirty {
		e.compute(cf)
	}

	var out []Result
	add := func(p Pos, v Value) {
		if v.Type == TypeError && v.Str == ErrUnsupported.Str {
			return
		}
		if !sameValue(v, e.src.Value(p)) {
			out = append(out, Result{p, v})
		}
	}
	for _, cf := range e.dirty {
		if cf.array == nil {
			add(cf.pos, cf.value)
		}
	}
	for p, v := range e.filled {
		add(p, v)
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

// cellsOf calls f with the cells a formula fills.
func (e *Engine) cellsOf(cf *cellFormula, f func(Pos)) {
	if cf.array == nil {
		f(cf.pos)
		return
	}
	for r := cf.array.R1; r <= cf.array.R2; r++ {
		for c := cf.array.C1; c <= cf.array.C2; c++ {
			f(Pos{cf.pos.Sheet, r, c})
		}
	}
}

// readersOf calls f with the formulas reading a cell.
func (e *Engine) readersOf(p Pos, f func(*cellFormula)) {
	for _, r := range e.readers[p] {
		f(r)
	}
	for _, r := range e.areas[[2]int{p.Sheet, p.Col}] {
		if r.area.Contains(p.Row, p.Col) {
			f(r.f)
		}
	}
	for _, r := range e.wide[p.Sheet] {
		if r.area.Contains(p.Row, p.Col) {
			f(r.f)
		}
	}
}

// compute calculates a formula, once per calculation; a formula read
// while it is being calculated reads 0, as Excel does in a circle.
func (e *Engine) compute(cf *cellFormula) {
	if cf.done || cf.busy {
		return
	}
	p := cf.pos
	cf.busy = true
	c := &Context{Book: (*engineBook)(e), Sheet: p.Sheet, Row: p.Row, Col: p.Col, Locale: e.opt.Locale,
		Now: e.opt.Now(), Rand: e.opt.Rand, Date1904: e.opt.Date1904}
	v := c.Eval(cf.expr)
	cf.busy, cf.done = false, true
	if cf.array == nil {
		cf.value = cellValue(c.scalar(v))
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
			e.filled[Pos{p.Sheet, r, k}] = x
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

// sameValue tells whether a value is the one a cell holds, numbers
// compared to the 15 digits Excel keeps: what a workbook saved, calculated
// again, stays the same.
func sameValue(a, b Value) bool {
	if a.Type == TypeNumber && b.Type == TypeNumber {
		if a.Num == b.Num {
			return true
		}
		if math.Abs(a.Num-b.Num) > 1e-14*max(math.Abs(a.Num), math.Abs(b.Num)) {
			return false
		}
		return strconv.FormatFloat(a.Num, 'g', 15, 64) == strconv.FormatFloat(b.Num, 'g', 15, 64)
	}
	return a.Type == b.Type && a.Num == b.Num && a.Str == b.Str
}

// engineBook is the workbook as the formulas being calculated read it:
// the values just calculated over those the source holds.
type engineBook Engine

func (b *engineBook) value(p Pos) Value {
	e := (*Engine)(b)
	v, ok := Value{}, false
	if anchor, array := e.arrays[p]; array {
		if cf := e.formulas[anchor]; cf != nil && cf.dirty {
			e.compute(cf)
			v, ok = e.filled[p]
			if !ok && cf.busy && anchor == p {
				return Num(0)
			}
		}
	} else if cf := e.formulas[p]; cf != nil && cf.dirty {
		e.compute(cf)
		if cf.busy {
			return Num(0)
		}
		v, ok = cf.value, true
	}
	if !ok || v.Type == TypeError && v.Str == ErrUnsupported.Str {
		return e.src.Value(p)
	}
	return v
}

func (b *engineBook) Cell(sheet, row, col int) Value {
	return b.value(Pos{sheet, row, col})
}

func (b *engineBook) Cells(a Area3, f func(row, col int, v Value) bool) {
	e := (*Engine)(b)
	if d, ok := e.bounds[a.Sheet]; !ok || d.R2 < a.R1 || d.R1 > a.R2 || d.C2 < a.C1 || d.C1 > a.C2 {
		b.sourceCells(a, f)
		return
	}
	e.src.Each(a, func(row, col int, v Value) bool {
		p := Pos{a.Sheet, row, col}
		if _, array := e.arrays[p]; array {
			v = b.value(p)
		} else if cf := e.formulas[p]; cf != nil && cf.dirty {
			v = b.value(p)
		}
		if v.Type == TypeBlank {
			return true
		}
		return f(row, col, v)
	})
}

// sourceCells calls f with the cells of an area no formula calculated
// reaches, kept from the second time it is read.
func (b *engineBook) sourceCells(a Area3, f func(row, col int, v Value) bool) {
	e := (*Engine)(b)
	cells, seen := e.ranges[a]
	if !seen || cells == nil && e.cached >= cachedCells {
		if !seen {
			e.ranges[a] = nil
		}
		e.src.Each(a, func(row, col int, v Value) bool {
			return v.Type == TypeBlank || f(row, col, v)
		})
		return
	}
	if cells == nil {
		cells = []cachedCell{}
		e.src.Each(a, func(row, col int, v Value) bool {
			if v.Type != TypeBlank {
				cells = append(cells, cachedCell{int32(row), int32(col), v.Type, v.Num, v.Str})
			}
			return true
		})
		e.ranges[a] = cells
		e.cached += len(cells)
	}
	for _, c := range cells {
		if !f(int(c.row), int(c.col), Value{Type: c.typ, Num: c.num, Str: c.str}) {
			return
		}
	}
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
