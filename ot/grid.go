package ot

import (
	"bytes"
	"encoding/json"
	"slices"
	"strconv"
)

// A Grid is the cells of a sheet: sparse, addressed by row and column
// counted from 1, each cell a JSON object of fields. Row 0 holds the
// fields of whole columns, column 0 those of whole rows, so that inserting
// or removing rows and columns moves them along with the cells.
//
// Setting a field is last-writer-wins, like a node's attributes. Inserting
// and removing rows or columns shifts what comes after, and a cell set on a
// row that someone removed meanwhile is dropped with it.
type Grid struct {
	rows  []int32
	cells [][]gridCell // of each row, by column; never changed in place
	size  int
}

type gridCell struct {
	col    int32
	fields string
}

// Cell is a cell in a change: the fields it sets, a null removing one.
// It is written [row, column, {fields}].
type Cell struct {
	Row, Col int
	Fields   json.RawMessage
}

// The size of a sheet in Excel.
const (
	MaxRows = 1 << 20
	MaxCols = 1 << 14
)

const (
	OpCel = "cel"
	OpIns = "ins"
	OpRem = "rem"
)

// Dimensions of Change.Dim.
const (
	DimRows = "r"
	DimCols = "c"
)

func (c Cell) MarshalJSON() ([]byte, error) {
	b := []byte{'['}
	b = strconv.AppendInt(b, int64(c.Row), 10)
	b = append(b, ',')
	b = strconv.AppendInt(b, int64(c.Col), 10)
	b = append(b, ',')
	b = append(b, c.Fields...)
	return append(b, ']'), nil
}

func (c *Cell) UnmarshalJSON(data []byte) error {
	var parts []json.RawMessage
	if err := json.Unmarshal(data, &parts); err != nil {
		return err
	}
	if len(parts) != 3 || json.Unmarshal(parts[0], &c.Row) != nil || json.Unmarshal(parts[1], &c.Col) != nil {
		return ErrInvalid
	}
	c.Fields = parts[2]
	return nil
}

// fields reads a cell's object; set allows the nulls that remove fields.
func fields(raw json.RawMessage, set bool) (map[string]json.RawMessage, bool) {
	var f map[string]json.RawMessage
	if len(raw) == 0 || raw[0] != '{' || json.Unmarshal(raw, &f) != nil || f == nil {
		return nil, false
	}
	for k, v := range f {
		if k == "" || !set && bytes.Equal(v, null) {
			return nil, false
		}
	}
	return f, true
}

func checkCells(cells []Cell, set bool) bool {
	seen := make(map[[2]int]bool, len(cells))
	for _, c := range cells {
		at := [2]int{c.Row, c.Col}
		if c.Row < 0 || c.Row > MaxRows || c.Col < 0 || c.Col > MaxCols || seen[at] {
			return false
		}
		f, ok := fields(c.Fields, set)
		if !ok || set && len(f) == 0 {
			return false
		}
		seen[at] = true
	}
	return true
}

// NewGrid is a grid of cells, which only set fields.
func NewGrid(cells []Cell) (*Grid, error) {
	g := &Grid{}
	for _, c := range cells {
		f, ok := fields(c.Fields, false)
		if !ok {
			return nil, ErrInvalid
		}
		if len(f) > 0 {
			g.put(c.Row, c.Col, compact(f))
		}
	}
	return g, nil
}

// Len is the number of cells.
func (g *Grid) Len() int {
	return g.size
}

// Cell is the fields of a cell, nil when it has none.
func (g *Grid) Cell(row, col int) json.RawMessage {
	i, ok := slices.BinarySearch(g.rows, int32(row))
	if !ok {
		return nil
	}
	cells := g.cells[i]
	j, ok := slices.BinarySearchFunc(cells, int32(col), func(c gridCell, col int32) int { return int(c.col - col) })
	if !ok {
		return nil
	}
	return json.RawMessage(cells[j].fields)
}

// Cells are all the cells, row by row.
func (g *Grid) Cells() []Cell {
	out := make([]Cell, 0, g.size)
	for i, r := range g.rows {
		for _, c := range g.cells[i] {
			out = append(out, Cell{Row: int(r), Col: int(c.col), Fields: json.RawMessage(c.fields)})
		}
	}
	return out
}

// Each calls f with every cell of rows from lo to hi, in order, until f
// returns false.
func (g *Grid) Each(lo, hi int, f func(row, col int, fields json.RawMessage) bool) {
	i, _ := slices.BinarySearch(g.rows, int32(lo))
	for ; i < len(g.rows) && int(g.rows[i]) <= hi; i++ {
		for _, c := range g.cells[i] {
			if !f(int(g.rows[i]), int(c.col), json.RawMessage(c.fields)) {
				return
			}
		}
	}
}

// Clone is a copy that later edits of g leave alone.
func (g *Grid) Clone() *Grid {
	return &Grid{rows: slices.Clone(g.rows), cells: slices.Clone(g.cells), size: g.size}
}

// put sets the fields of a cell, "" removing it.
func (g *Grid) put(row, col int, f string) {
	i, found := slices.BinarySearch(g.rows, int32(row))
	if !found {
		if f == "" {
			return
		}
		g.rows = slices.Insert(g.rows, i, int32(row))
		g.cells = slices.Insert(g.cells, i, nil)
	}
	cells := g.cells[i]
	j, ok := slices.BinarySearchFunc(cells, int32(col), func(c gridCell, col int32) int { return int(c.col - col) })
	switch {
	case ok && f == "":
		cells = slices.Delete(slices.Clone(cells), j, j+1)
		g.size--
	case ok:
		cells = slices.Clone(cells)
		cells[j].fields = f
	case f != "":
		cells = slices.Insert(slices.Clone(cells), j, gridCell{int32(col), f})
		g.size++
	}
	if len(cells) == 0 {
		g.rows = slices.Delete(g.rows, i, i+1)
		g.cells = slices.Delete(g.cells, i, i+1)
		return
	}
	g.cells[i] = cells
}

func (g *Grid) set(cells []Cell) {
	for _, c := range cells {
		set, _ := fields(c.Fields, true)
		old, _ := fields(g.Cell(c.Row, c.Col), false)
		if old == nil {
			old = map[string]json.RawMessage{}
		}
		for k, v := range set {
			if bytes.Equal(v, null) {
				delete(old, k)
			} else {
				old[k] = v
			}
		}
		if len(old) == 0 {
			g.put(c.Row, c.Col, "")
		} else {
			g.put(c.Row, c.Col, compact(old))
		}
	}
}

func compact(f map[string]json.RawMessage) string {
	b, _ := json.Marshal(f)
	return string(b)
}

// shift inserts n rows or columns at at, or removes them when n is
// negative; what is pushed past the end of the sheet is dropped.
func (g *Grid) shift(dim string, at, n int) {
	if dim == DimRows {
		var rows []int32
		var cells [][]gridCell
		for i, r := range g.rows {
			m, ok := moved(int(r), at, n, MaxRows)
			if !ok {
				g.size -= len(g.cells[i])
				continue
			}
			rows = append(rows, int32(m))
			cells = append(cells, g.cells[i])
		}
		g.rows, g.cells = rows, cells
		return
	}
	for i, row := range g.cells {
		changed := false
		out := make([]gridCell, 0, len(row))
		for _, c := range row {
			m, ok := moved(int(c.col), at, n, MaxCols)
			if !ok {
				g.size--
				changed = true
				continue
			}
			changed = changed || m != int(c.col)
			out = append(out, gridCell{int32(m), c.fields})
		}
		if changed {
			g.cells[i] = out
		}
	}
	g.dropEmptyRows()
}

func (g *Grid) dropEmptyRows() {
	var rows []int32
	var cells [][]gridCell
	for i, r := range g.rows {
		if len(g.cells[i]) > 0 {
			rows = append(rows, r)
			cells = append(cells, g.cells[i])
		}
	}
	g.rows, g.cells = rows, cells
}

// moved is where index i goes when n rows or columns are inserted at at,
// or removed when n is negative, and whether it is still there.
func moved(i, at, n, limit int) (int, bool) {
	switch {
	case i < at:
		return i, true
	case n < 0 && i < at-n:
		return 0, false
	case i+n > limit:
		return 0, false
	}
	return i + n, true
}

// transformGrid rebases two changes to the same grid over each other; a
// change left with nothing to do has no Op.
func transformGrid(a, b Change, aFirst bool) (Change, Change) {
	switch {
	case a.Op == OpCel && b.Op == OpCel:
		if aFirst {
			a.Cells = overriddenCells(a.Cells, b.Cells)
		} else {
			b.Cells = overriddenCells(b.Cells, a.Cells)
		}
	case a.Op == OpCel:
		a.Cells = shiftCells(a.Cells, b)
	case b.Op == OpCel:
		b.Cells = shiftCells(b.Cells, a)
	case a.Dim != b.Dim:
	case a.Op == OpIns && b.Op == OpIns:
		if a.At < b.At || a.At == b.At && aFirst {
			b.At += a.N
		} else {
			a.At += b.N
		}
	case a.Op == OpRem && b.Op == OpRem:
		a, b = removedOver(a, b), removedOver(b, a)
	case a.Op == OpIns:
		b, a = removalOverInsert(b, a)
	default:
		a, b = removalOverInsert(a, b)
	}
	for _, c := range []*Change{&a, &b} {
		if c.Op == OpCel && len(c.Cells) == 0 || (c.Op == OpIns || c.Op == OpRem) && c.N <= 0 {
			c.Op = ""
		}
	}
	return a, b
}

// overriddenCells are cells without the fields later sets.
func overriddenCells(cells, later []Cell) []Cell {
	sets := make(map[[2]int]map[string]json.RawMessage, len(later))
	for _, c := range later {
		sets[[2]int{c.Row, c.Col}], _ = fields(c.Fields, true)
	}
	var out []Cell
	for _, c := range cells {
		set := sets[[2]int{c.Row, c.Col}]
		if set == nil {
			out = append(out, c)
			continue
		}
		f, _ := fields(c.Fields, true)
		for k := range set {
			delete(f, k)
		}
		if len(f) > 0 {
			out = append(out, Cell{c.Row, c.Col, json.RawMessage(compact(f))})
		}
	}
	return out
}

// shiftCells moves cells where rows or columns inserted or removed by s
// put them, dropping those removed.
func shiftCells(cells []Cell, s Change) []Cell {
	n := s.N
	if s.Op == OpRem {
		n = -n
	}
	var out []Cell
	for _, c := range cells {
		var ok bool
		if s.Dim == DimRows {
			c.Row, ok = moved(c.Row, s.At, n, MaxRows)
		} else {
			c.Col, ok = moved(c.Col, s.At, n, MaxCols)
		}
		if ok {
			out = append(out, c)
		}
	}
	return out
}

// removedOver is the removal r once other is removed too.
func removedOver(r, other Change) Change {
	end, otherEnd := r.At+r.N, other.At+other.N
	before := max(0, min(otherEnd, r.At)-other.At)
	overlap := max(0, min(end, otherEnd)-max(r.At, other.At))
	r.At -= before
	r.N -= overlap
	return r
}

// removalOverInsert rebases a removal and an insertion over each other.
// Rows inserted inside the removed ones are removed with them.
func removalOverInsert(rem, ins Change) (Change, Change) {
	switch {
	case ins.At <= rem.At:
		rem.At += ins.N
	case ins.At >= rem.At+rem.N:
		ins.At -= rem.N
	default:
		rem.N += ins.N
		ins.N = 0
	}
	return rem, ins
}
