package ot

import (
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"reflect"
	"testing"
)

// cells are a few cells of a small sheet, row 0 and column 0 included, so
// that changes meet on the same ones.
func (g *treeGen) cells(set bool) []Cell {
	out := []Cell{}
	seen := map[[2]int]bool{}
	for range g.IntN(4) {
		r, c := g.IntN(6), g.IntN(4)
		if seen[[2]int{r, c}] {
			continue
		}
		seen[[2]int{r, c}] = true
		f := map[string]json.RawMessage{}
		for _, k := range []string{"v", "f", "s"} {
			switch g.IntN(3) {
			case 0:
				f[k] = g.value()
			case 1:
				if set {
					f[k] = json.RawMessage("null")
				}
			}
		}
		if len(f) == 0 {
			f["v"] = g.value()
		}
		out = append(out, Cell{r, c, json.RawMessage(compact(f))})
	}
	return out
}

func (g *treeGen) gridChange(id string) Change {
	switch g.IntN(4) {
	case 0:
		return Change{Op: OpIns, ID: id, Dim: []string{DimRows, DimCols}[g.IntN(2)], At: 1 + g.IntN(5), N: 1 + g.IntN(2)}
	case 1:
		return Change{Op: OpRem, ID: id, Dim: []string{DimRows, DimCols}[g.IntN(2)], At: 1 + g.IntN(5), N: 1 + g.IntN(2)}
	}
	cells := g.cells(true)
	if len(cells) == 0 {
		cells = []Cell{{1, 1, json.RawMessage(`{"v":1}`)}}
	}
	return Change{Op: OpCel, ID: id, Cells: cells}
}

func cell(r, c int, f string) Cell {
	return Cell{r, c, json.RawMessage(f)}
}

func TestGridApply(t *testing.T) {
	tree := mustTree(t, Edit{{Op: OpNew, ID: "s", Type: "sheet", Key: "V", Cells: []Cell{
		cell(0, 2, `{"w":20}`), cell(1, 1, `{"v":1}`), cell(2, 2, `{"f":"A1+1","v":2}`), cell(3, 0, `{"h":30}`), cell(4, 3, `{"v":"x"}`),
	}}})
	for _, e := range []Edit{
		{{Op: OpCel, ID: "s", Cells: []Cell{cell(1, 1, `{"v":null}`), cell(5, 1, `{"v":true}`), cell(2, 2, `{"s":"x1"}`)}}},
		{{Op: OpIns, ID: "s", Dim: DimRows, At: 2, N: 2}},
		{{Op: OpRem, ID: "s", Dim: DimCols, At: 1, N: 1}},
	} {
		if err := tree.Apply(e); err != nil {
			t.Fatal(err)
		}
	}
	want := []Cell{cell(0, 1, `{"w":20}`), cell(4, 1, `{"f":"A1+1","s":"x1","v":2}`), cell(5, 0, `{"h":30}`), cell(6, 2, `{"v":"x"}`)}
	if got := tree.Node("s").Grid.Cells(); !reflect.DeepEqual(got, want) || tree.Len() != 5 {
		t.Fatalf("got %v, size %d", got, tree.Len())
	}
	out, _ := json.Marshal(tree.Edit())
	if string(out) != `[{"o":"new","id":"s","t":"sheet","k":"V","c":[[0,1,{"w":20}],[4,1,{"f":"A1+1","s":"x1","v":2}],[5,0,{"h":30}],[6,2,{"v":"x"}]]}]` {
		t.Fatalf("encoded %s", out)
	}

	empty := mustTree(t, Edit{{Op: OpNew, ID: "e", Type: "sheet", Key: "V", Cells: []Cell{}}})
	if out, _ := json.Marshal(empty.Edit()); string(out) != `[{"o":"new","id":"e","t":"sheet","k":"V","c":[]}]` {
		t.Fatalf("empty grid encoded %s", out)
	}
	if err := empty.Apply(Edit{{Op: OpIns, ID: "e", Dim: DimRows, At: MaxRows, N: 1}}); err != nil {
		t.Fatal(err)
	}
	if err := empty.Apply(Edit{{Op: OpCel, ID: "e", Cells: []Cell{cell(MaxRows, 1, `{"v":1}`)}}, {Op: OpIns, ID: "e", Dim: DimRows, At: 1, N: 1}}); err != nil {
		t.Fatal(err)
	}
	if empty.Len() != 1 {
		t.Fatalf("a cell pushed past the last row stayed: %v", empty.Edit())
	}
}

func TestGridCheck(t *testing.T) {
	for _, e := range []Edit{
		{{Op: OpCel, ID: "s"}},
		{{Op: OpCel, ID: "s", Cells: []Cell{cell(-1, 1, `{"v":1}`)}}},
		{{Op: OpCel, ID: "s", Cells: []Cell{cell(1, MaxCols+1, `{"v":1}`)}}},
		{{Op: OpCel, ID: "s", Cells: []Cell{cell(1, 1, `{}`)}}},
		{{Op: OpCel, ID: "s", Cells: []Cell{cell(1, 1, `[1]`)}}},
		{{Op: OpCel, ID: "s", Cells: []Cell{cell(1, 1, `{"v":1}`), cell(1, 1, `{"s":1}`)}}},
		{{Op: OpNew, ID: "s", Type: "sheet", Key: "V", Cells: []Cell{cell(1, 1, `{"v":null}`)}}},
		{{Op: OpNew, ID: "s", Type: "sheet", Key: "V", Cells: []Cell{}, Text: Delta{ins("\n")}}},
		{{Op: OpIns, ID: "s", Dim: "x", At: 1, N: 1}},
		{{Op: OpIns, ID: "s", Dim: DimRows, At: 0, N: 1}},
		{{Op: OpRem, ID: "s", Dim: DimCols, At: 1, N: 0}},
		{{Op: OpRem, ID: "s", Dim: DimCols, At: MaxCols + 1, N: 1}},
		{{Op: OpSet, ID: "s", Attrs: values("x", "1"), Dim: DimRows}},
	} {
		if e.Check() == nil {
			t.Errorf("%v passes", e)
		}
	}
	var c Cell
	if json.Unmarshal([]byte(`[1,2]`), &c) == nil || json.Unmarshal([]byte(`[1,"a",{}]`), &c) == nil {
		t.Error("malformed cell read")
	}
}

// TestGridConcurrent checks the cases people meet most: typing in rows that
// someone else is inserting or removing.
func TestGridConcurrent(t *testing.T) {
	nodes := Edit{{Op: OpNew, ID: "s", Type: "sheet", Key: "V", Cells: []Cell{cell(3, 1, `{"v":3}`), cell(5, 1, `{"v":5}`)}}}
	for _, c := range []struct {
		a, b Edit
		want []Cell
	}{
		{
			Edit{{Op: OpIns, ID: "s", Dim: DimRows, At: 2, N: 1}},
			Edit{{Op: OpCel, ID: "s", Cells: []Cell{cell(5, 2, `{"v":"b"}`)}}},
			[]Cell{cell(4, 1, `{"v":3}`), cell(6, 1, `{"v":5}`), cell(6, 2, `{"v":"b"}`)},
		},
		{
			Edit{{Op: OpRem, ID: "s", Dim: DimRows, At: 4, N: 2}},
			Edit{{Op: OpCel, ID: "s", Cells: []Cell{cell(5, 2, `{"v":"b"}`), cell(7, 1, `{"v":7}`)}}},
			[]Cell{cell(3, 1, `{"v":3}`), cell(5, 1, `{"v":7}`)},
		},
		{
			Edit{{Op: OpRem, ID: "s", Dim: DimRows, At: 2, N: 3}},
			Edit{{Op: OpIns, ID: "s", Dim: DimRows, At: 3, N: 1}, {Op: OpCel, ID: "s", Cells: []Cell{cell(3, 1, `{"v":"new"}`)}}},
			[]Cell{cell(2, 1, `{"v":5}`)},
		},
		{
			Edit{{Op: OpIns, ID: "s", Dim: DimCols, At: 1, N: 1}},
			Edit{{Op: OpIns, ID: "s", Dim: DimCols, At: 1, N: 2}, {Op: OpCel, ID: "s", Cells: []Cell{cell(3, 2, `{"v":"b"}`)}}},
			[]Cell{cell(3, 3, `{"v":"b"}`), cell(3, 4, `{"v":3}`), cell(5, 4, `{"v":5}`)},
		},
	} {
		ab := applied(t, nodes, c.a, TransformEdit(c.a, c.b, true))
		ba := applied(t, nodes, c.b, TransformEdit(c.b, c.a, false))
		if !reflect.DeepEqual(ab, ba) {
			t.Fatalf("a %v, b %v: %v then %v", c.a, c.b, ab, ba)
		}
		if !reflect.DeepEqual(ab[0].Cells, c.want) {
			t.Errorf("a %v, b %v: got %v, want %v", c.a, c.b, ab[0].Cells, c.want)
		}
	}
}

func BenchmarkGridSet(b *testing.B) {
	var cells []Cell
	for r := 1; r <= 100_000; r++ {
		for c := 1; c <= 20; c++ {
			cells = append(cells, cell(r, c, fmt.Sprintf(`{"v":%d}`, r*c)))
		}
	}
	tree, err := NewTree(Edit{{Op: OpNew, ID: "s", Type: "sheet", Key: "V", Cells: cells}})
	if err != nil {
		b.Fatal(err)
	}
	g := rand.New(rand.NewPCG(1, 2))
	for b.Loop() {
		e := Edit{{Op: OpCel, ID: "s", Cells: []Cell{cell(1+g.IntN(100_000), 1+g.IntN(20), `{"v":"typed"}`)}}}
		if err := tree.Apply(e); err != nil {
			b.Fatal(err)
		}
	}
}
