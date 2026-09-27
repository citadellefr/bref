package bref

import (
	"os"
	"testing"

	"github.com/citadellefr/bref/xlsx"
)

func TestWorkbooksAreCalculatedAndSaved(t *testing.T) {
	data, err := os.ReadFile("testdata/xlsx/blank.xlsx")
	if err != nil {
		t.Fatal(err)
	}
	store := newMemStore()
	store.data["book.xlsx"] = data
	h := NewHub(store, fastOptions())
	a, _, _ := join(t, h, "book.xlsx", Peer{ID: "1"})
	b, _, _ := join(t, h, "book.xlsx", Peer{ID: "2"})
	a.expect("join")

	a.send(`{"t":"op","n":1,"v":0,"d":[{"o":"cel","id":"S1","c":[[1,1,{"v":2}],[2,1,{"f":"A1*3"}],[3,1,{"f":"TEXT(A2,\"0,00\")"}]]}]}`)
	a.expect("ack")
	// the server follows with the values, for everyone
	for _, c := range []*client{a, b} {
		if c == b {
			c.expect("op")
		}
		f := c.expect("op")
		if f.SID != 0 || string(f.D) != `[{"o":"cel","id":"S1","c":[[2,1,{"v":6}],[3,1,{"v":"6,00"}]]}]` {
			t.Fatalf("follow-up: %+v %s", f, f.D)
		}
	}
	b.send(`{"t":"op","n":1,"v":2,"d":[{"o":"cel","id":"S1","c":[[1,1,{"v":5}]]}]}`)
	b.expect("ack")
	if f := b.expect("op"); string(f.D) != `[{"o":"cel","id":"S1","c":[[2,1,{"v":15}],[3,1,{"v":"15,00"}]]}]` {
		t.Fatalf("follow-up: %s", f.D)
	}
	<-store.saves
	_, tree, err := xlsx.Open([]byte(store.file("book.xlsx")))
	if err != nil {
		t.Fatal(err)
	}
	cells := map[[2]int]string{}
	for _, c := range tree.Node("S1").Grid.Cells() {
		cells[[2]int{c.Row, c.Col}] = string(c.Fields)
	}
	if cells[[2]int{2, 1}] != `{"f":"A1*3","v":15}` || cells[[2]int{3, 1}] != `{"f":"TEXT(A2,\"0,00\")","v":"15,00"}` {
		t.Fatalf("saved cells: %v", cells)
	}
	a.leave()
	b.leave()
}
