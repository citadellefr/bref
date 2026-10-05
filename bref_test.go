package bref

import (
	"context"
	"slices"
	"testing"
	"time"

	"github.com/citadellefr/bref/md"
	"github.com/citadellefr/trame"
	"github.com/citadellefr/trame/trametest"
)

func join(t *testing.T, h *trame.Hub, key string, info trame.Peer) (*trametest.Client, trametest.Frame, trametest.Frame) {
	t.Helper()
	return trametest.Join(t, func(c *trametest.Conn) error { return h.Serve(context.Background(), c, key, info) })
}

var fast = Options{Options: trame.Options{SaveDelay: 20 * time.Millisecond, SaveMaxDelay: 100 * time.Millisecond}}

func TestNotesAreEditedAndSavedAsTheyWereRead(t *testing.T) {
	store := trametest.NewStore()
	store.Data["n.md"] = []byte("# Title\r\n\r\nSome *text*")
	h := NewHub(store, fast)

	alice, _, doc := join(t, h, "n.md", trame.Peer{ID: "1", Client: "a"})
	if string(doc.D) != `[{"o":"new","id":"body","t":"text","k":"V","x":[{"i":"# Title\n\nSome *text*\n"}]}]` {
		t.Fatalf("doc = %s", doc.D)
	}
	alice.Send(`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"r":7},{"i":"!"}]}]}`)
	alice.Expect("ack")
	<-store.Saves
	if got := store.File("n.md"); got != "# Title!\r\n\r\nSome *text*" {
		t.Fatalf("saved %q", got)
	}
}

func TestNotesTakeNoAttributesButTheirAuthor(t *testing.T) {
	store := trametest.NewStore()
	h := NewHub(store, Options{})
	c, _, _ := join(t, h, "n.md", trame.Peer{ID: "1"})
	for _, op := range []string{
		`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"i":"a","a":{"b":"1"}}]}]}`,
		`{"t":"op","n":2,"v":0,"d":[{"o":"txt","id":"body","x":[{"i":"a","a":{"by":"1","b":"1"}}]}]}`,
		`{"t":"op","n":3,"v":0,"d":[{"o":"txt","id":"body","x":[{"r":1,"a":{"by":"1"}}]}]}`,
		`{"o":"set","id":"body","a":{"x":1}}`,
	} {
		c.Send(op)
	}
	for range 3 {
		if f := c.Expect("nack"); f.Error == "" {
			t.Fatalf("nack = %+v", f)
		}
	}
	c.Quiet()
}

func TestInsertionsAreSignedByTheirAuthor(t *testing.T) {
	store := trametest.NewStore()
	store.Data["n.md"] = []byte("ab")
	h := NewHub(store, Options{})
	alice, _, _ := join(t, h, "n.md", trame.Peer{ID: "1", Client: "a"})

	alice.Send(`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"i":"x","a":{"by":"1"}}]}]}`)
	alice.Expect("ack")
	alice.Send(`{"t":"op","n":2,"v":1,"d":[{"o":"txt","id":"body","x":[{"r":1},{"i":"y"},{"r":1},{"i":"z","a":{"by":"2"}}]}]}`)
	alice.Expect("ack")
	if f := alice.Expect("op"); f.SID != 0 || string(f.D) != `[{"o":"txt","id":"body","x":[{"r":1},{"r":1,"a":{"by":"1"}},{"r":1},{"r":1,"a":{"by":"1"}}]}]` {
		t.Fatalf("op = %s", f.D)
	}
	alice.Quiet()
}

func TestAddedLinksAreToldWithTheirAuthor(t *testing.T) {
	store := trametest.NewStore()
	store.Data["n.md"] = []byte("Ask [@Bob](user:2).\n")
	added := make(chan []Link, 4)
	opt := fast
	opt.OnLinks = func(key string, links []Link) {
		if key != "n.md" {
			t.Errorf("key %q", key)
		}
		added <- links
	}
	h := NewHub(store, opt)
	alice, _, _ := join(t, h, "n.md", trame.Peer{ID: "1", Client: "a"})
	bob, _, _ := join(t, h, "n.md", trame.Peer{ID: "2", Client: "b"})
	alice.Expect("join")

	// Alice mentions Bob before his mention, Bob links a note; the server
	// signs both
	alice.Send(`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"i":"[@Bob](user:2) "}]}]}`)
	alice.Expect("ack")
	alice.Expect("op")
	bob.Send(`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"r":19},{"i":" See [[Plan]]."}]}]}`)
	for _, f := range []string{"op", "op", "ack", "op"} {
		bob.Expect(f)
	}
	alice.Expect("op")
	alice.Expect("op")
	got := <-added
	want := []Link{
		{Dest: "user:2", Text: "@Bob", By: "1"},
		{Dest: "Plan", Text: "Plan", Form: md.LinkWiki, By: "2"},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("added %+v", got)
	}
	<-store.Saves
	alice.Expect("saved")

	// a mention moved is not added again
	alice.Send(`{"t":"op","n":2,"v":4,"d":[{"o":"txt","id":"body","x":[{"d":15},{"r":1},{"i":"[@Bob](user:2) "}]}]}`)
	alice.Expect("ack")
	<-store.Saves
	select {
	case links := <-added:
		t.Fatalf("added %+v", links)
	default:
	}
}
