package bref

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/citadellefr/bref/ot"
)

// simClient is the client side of the protocol, as the Dart session runs
// it: its own edits show at once, one is in flight, the others wait
// composed, and all of them are rebased over what the hub hands out.
type simClient struct {
	t      *testing.T
	id     string
	p      *peer
	outbox [][]byte

	epoch    string // of the document it holds
	joined   string // of the connection
	rev      uint64
	synced   bool
	doc      ot.Delta
	n        uint64
	inflight ot.Delta
	pending  uint64 // n of the edit in flight, 0 when none
	sent     bool   // whether it went out on this connection
	buffer   ot.Delta
}

func (c *simClient) connect(r *room) {
	c.p = newPeer(newFakeConn(), Peer{ID: c.id, Client: c.id}, 1000)
	c.outbox = nil
	c.synced = false
	c.sent = false
	r.join(c.p)
}

func (c *simClient) send(v any) {
	msg, _ := json.Marshal(v)
	c.outbox = append(c.outbox, msg)
}

func (c *simClient) sendInflight() {
	c.sent = true
	c.send(map[string]any{"t": "op", "n": c.pending, "v": c.rev, "d": c.inflight})
}

func (c *simClient) edit(d ot.Delta) {
	c.doc = c.compose(c.doc, d)
	if c.pending == 0 && c.synced {
		c.n++
		c.pending, c.inflight = c.n, d
		c.sendInflight()
		return
	}
	c.buffer = c.compose(c.buffer, d)
}

func (c *simClient) flushBuffer() {
	if c.pending != 0 || c.buffer == nil {
		return
	}
	c.n++
	c.pending, c.inflight, c.buffer = c.n, c.buffer, nil
	c.sendInflight()
}

func (c *simClient) receive(raw []byte) {
	var f frame
	if err := json.Unmarshal(raw, &f); err != nil {
		c.t.Fatal(err)
	}
	var d ot.Delta
	if f.D != nil && f.T != "eph" {
		if err := json.Unmarshal(f.D, &d); err != nil {
			c.t.Fatal(err)
		}
	}
	switch f.T {
	case "hello":
		c.send(map[string]any{"t": "sync", "epoch": c.epoch, "v": c.rev})
		c.joined = f.Epoch
	case "doc":
		if c.pending != 0 || c.buffer != nil || c.doc != nil {
			c.t.Fatalf("%s: whole document sent while resuming", c.id)
		}
		c.doc, c.rev, c.synced, c.epoch = d, f.V, true, c.joined
		c.flushBuffer()
	case "ready":
		c.synced, c.epoch = true, c.joined
		if c.pending != 0 && !c.sent {
			c.sendInflight()
		}
		c.flushBuffer()
	case "op":
		if c.pending != 0 {
			c.inflight, d = ot.Transform(d, c.inflight, true), ot.Transform(c.inflight, d, false)
		}
		if c.buffer != nil {
			c.buffer, d = ot.Transform(d, c.buffer, true), ot.Transform(c.buffer, d, false)
		}
		c.doc = c.compose(c.doc, d)
		c.rev = f.V
	case "ack":
		if f.N != c.pending {
			c.t.Fatalf("%s: ack of %d, %d in flight", c.id, f.N, c.pending)
		}
		c.rev, c.pending, c.inflight = f.V, 0, nil
		if c.synced {
			c.flushBuffer()
		}
	case "nack":
		c.t.Fatalf("%s: edit refused: %s", c.id, f.Error)
	}
}

func (c *simClient) compose(a, b ot.Delta) ot.Delta {
	out, err := ot.Compose(a, b)
	if err != nil {
		c.t.Fatal(err)
	}
	return out
}

// randomEdit inserts, deletes or formats whole characters, never after the
// last paragraph mark nor that mark itself.
func randomEdit(g *rand.Rand, doc ot.Delta) ot.Delta {
	var units []rune
	for _, o := range doc {
		for _, r := range o.Insert {
			units = append(units, 1+min(r/0x10000, 1))
		}
	}
	units = units[:len(units)-1]
	offset := func(chars int) int {
		n := 0
		for _, u := range units[:chars] {
			n += int(u)
		}
		return n
	}
	at := g.IntN(len(units) + 1)
	span := min(len(units)-at, 1+g.IntN(4))
	d := ot.Delta{}.Push(ot.Op{Retain: offset(at)})
	switch {
	case g.IntN(3) > 0 || span == 0:
		words := []string{"a", "é", "😀", "\n", "bc", " "}
		var b strings.Builder
		for range 1 + g.IntN(3) {
			b.WriteString(words[g.IntN(len(words))])
		}
		return d.Push(ot.Op{Insert: b.String()})
	case g.IntN(2) == 0:
		return d.Push(ot.Op{Delete: offset(at+span) - offset(at)})
	default:
		v := []string{"", "1", "2"}[g.IntN(3)]
		return d.Push(ot.Op{Retain: offset(at+span) - offset(at), Attrs: ot.Attrs{"b": v}})
	}
}

func TestConvergence(t *testing.T) {
	for seed := range uint64(20) {
		t.Run(fmt.Sprint(seed), func(t *testing.T) { converge(t, seed) })
	}
}

func converge(t *testing.T, seed uint64) {
	g := rand.New(rand.NewPCG(seed, 7))
	store := newMemStore()
	store.data["c.txt"] = []byte("one\ntwo")
	h := NewHub(store, Options{SaveDelay: time.Hour, SaveMaxDelay: time.Hour, History: 10_000})
	r, err := h.acquire(context.Background(), "c.txt")
	if err != nil {
		t.Fatal(err)
	}
	defer r.stop()

	clients := make([]*simClient, 4)
	for i := range clients {
		clients[i] = &simClient{t: t, id: fmt.Sprint("c", i)}
		clients[i].connect(r)
	}
	reconnect := func(c *simClient) {
		r.leave(c.p)
		c.connect(r)
	}
	deliverDown := func(c *simClient) bool {
		select {
		case <-c.p.done:
			reconnect(c)
			return true
		default:
		}
		delivered := false
		for {
			select {
			case raw := <-c.p.out:
				c.receive(raw)
				delivered = true
			default:
				return delivered
			}
		}
	}
	deliverUp := func(c *simClient) bool {
		if len(c.outbox) == 0 {
			return false
		}
		msg := c.outbox[0]
		c.outbox = c.outbox[1:]
		r.handle(c.p, msg)
		return true
	}
	for range 3000 {
		c := clients[g.IntN(len(clients))]
		switch k := g.IntN(100); {
		case k < 35:
			if c.doc != nil {
				c.edit(randomEdit(g, c.doc))
			}
		case k < 65:
			deliverUp(c)
		case k < 98:
			deliverDown(c)
		default:
			reconnect(c)
		}
	}
	for busy := true; busy; {
		busy = false
		for _, c := range clients {
			for deliverUp(c) || deliverDown(c) {
				busy = true
			}
		}
	}

	r.mu.Lock()
	want := r.doc.Delta()
	r.mu.Unlock()
	for _, c := range clients {
		if c.pending != 0 || c.buffer != nil {
			t.Fatalf("%s still has edits to send", c.id)
		}
		if !reflect.DeepEqual(c.doc, want) {
			t.Fatalf("%s has %v, the hub %v", c.id, c.doc, want)
		}
	}
}
