package chart

import (
	"encoding/json"
	"os"
	"testing"
)

func TestRead(t *testing.T) {
	data, err := os.ReadFile("testdata/bar.xml")
	if err != nil {
		t.Fatal(err)
	}
	c, err := Read(data)
	if err != nil {
		t.Fatal(err)
	}
	if c.Style != 10 || c.Blanks != "gap" || c.Text["sz"] != "900" {
		t.Errorf("chart space: %+v", c)
	}
	if c.Title == nil || c.Title.Text != "Ventes\n2026" || c.Title.Props["sz"] != "1400" || c.Title.Props["b"] != "1" {
		t.Errorf("title: %+v", c.Title)
	}
	if len(c.Plots) != 1 {
		t.Fatalf("plots: %+v", c.Plots)
	}
	p := c.Plots[0]
	if p.Kind != "bar" || p.Dir != "col" || p.Grouping != "clustered" || p.Vary || *p.Gap != 219 || p.Overlap != -27 {
		t.Errorf("plot: %+v", p)
	}
	if len(p.Axes) != 2 || p.Axes[0] != -2068027336 || p.Labels == nil || !p.Labels.Val || p.Labels.Key {
		t.Errorf("plot axes and labels: %+v %+v", p.Axes, p.Labels)
	}
	s := p.Series[0]
	if s.Name.Str[0] != "soap" || s.Name.Ref != "Sheet1!$A$1" || !s.Invert {
		t.Errorf("series name: %+v", s)
	}
	if got, _ := json.Marshal(s.Cat.Str); string(got) != `["T1","T2","","T4"]` {
		t.Errorf("categories: %s", got)
	}
	if got, _ := json.Marshal(s.Val.Num); string(got) != `[1,2.5,null,-4]` || s.Val.Format != "0.0" || s.Val.Ref != "Sheet1!$B$1:$E$1" {
		t.Errorf("values: %s %+v", got, s.Val)
	}
	if string(s.Shape["fill"]) != `{"solid":{"scheme":"accent2"}}` || len(s.Points) != 1 || s.Points[0].Idx != 2 {
		t.Errorf("series shape: %s %+v", s.Shape["fill"], s.Points)
	}
	s2 := p.Series[1]
	if s2.Name.Str[0] != "shampoo" || s2.Val.Num[1] != nil || *s2.Val.Num[0] != 3 {
		t.Errorf("literal series: %+v", s2)
	}
	if len(c.Axes) != 2 {
		t.Fatalf("axes: %+v", c.Axes)
	}
	cat, val := c.Axes[0], c.Axes[1]
	if cat.Kind != "cat" || cat.Pos != "b" || cat.Delete || cat.Cross != 2 || cat.Grid != nil {
		t.Errorf("category axis: %+v", cat)
	}
	if val.Kind != "val" || val.Cross != -2068027336 || !val.Reverse || *val.Max != 10 || val.Min != nil || val.Major != 2 || val.Grid == nil || len(*val.Grid) != 1 || !val.Linked || val.Between != "between" {
		t.Errorf("value axis: %+v", val)
	}
	if c.Legend == nil || c.Legend.Pos != "b" || len(c.Legend.Hidden) != 1 || c.Legend.Hidden[0] != 1 {
		t.Errorf("legend: %+v", c.Legend)
	}
}

func TestReadRefusesOtherParts(t *testing.T) {
	if _, err := Read([]byte(`<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"/>`)); err != ErrNotChart {
		t.Errorf("got %v", err)
	}
}
