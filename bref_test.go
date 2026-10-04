package bref

import (
	"context"
	"testing"
	"time"

	"github.com/citadellefr/trame"
	"github.com/citadellefr/trame/trametest"
)

func join(t *testing.T, h *trame.Hub, key string, info trame.Peer) (*trametest.Client, trametest.Frame, trametest.Frame) {
	t.Helper()
	return trametest.Join(t, func(c *trametest.Conn) error { return h.Serve(context.Background(), c, key, info) })
}

func TestNotesAreEditedAndSavedAsTheyWereRead(t *testing.T) {
	store := trametest.NewStore()
	store.Data["n.md"] = []byte("# Title\r\n\r\nSome *text*")
	h := NewHub(store, trame.Options{SaveDelay: 20 * time.Millisecond, SaveMaxDelay: 100 * time.Millisecond})

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

func TestNotesRefuseAttributes(t *testing.T) {
	store := trametest.NewStore()
	h := NewHub(store, trame.Options{})
	c, _, _ := join(t, h, "n.md", trame.Peer{ID: "1"})
	for _, op := range []string{
		`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"i":"a","a":{"b":"1"}}]}]}`,
		`{"t":"op","n":2,"v":0,"d":[{"o":"txt","id":"body","x":[{"r":1,"a":{"b":"1"}}]}]}`,
		`{"o":"set","id":"body","a":{"x":1}}`,
	} {
		c.Send(op)
	}
	for range 2 {
		if f := c.Expect("nack"); f.Error == "" {
			t.Fatalf("nack = %+v", f)
		}
	}
	c.Quiet()
}
