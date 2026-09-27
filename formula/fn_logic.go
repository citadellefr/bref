package formula

import (
	"math"
)

func init() {
	add(map[string]*function{
		"IF": {min: 1, max: 3, call: func(c *Context, args []Expr) Value {
			cond := c.Eval(args[0])
			if cond.Type == TypeArray || cond.Type == TypeRange && !singleCell(cond) {
				return c.mapValues(cond, func(v Value) Value { return c.branch(v, args) })
			}
			return c.branch(cond, args)
		}},
		"IFS": {min: 2, max: 254, call: func(c *Context, args []Expr) Value {
			if len(args)%2 != 0 {
				return ErrNA
			}
			for i := 0; i < len(args); i += 2 {
				b, err := c.boolean(c.Eval(args[i]))
				if err != nil {
					return *err
				}
				if b {
					return c.Eval(args[i+1])
				}
			}
			return ErrNA
		}},
		"IFERROR": {min: 2, max: 2, call: func(c *Context, args []Expr) Value {
			return c.mapValues(c.Eval(args[0]), func(v Value) Value {
				if v.Type == TypeError {
					return c.Eval(args[1])
				}
				return v
			})
		}},
		"IFNA": {min: 2, max: 2, call: func(c *Context, args []Expr) Value {
			return c.mapValues(c.Eval(args[0]), func(v Value) Value {
				if v.Type == TypeError && v.Str == ErrNA.Str {
					return c.Eval(args[1])
				}
				return v
			})
		}},
		"AND": logical(func(n, t int) bool { return t == n }),
		"OR":  logical(func(n, t int) bool { return t > 0 }),
		"XOR": logical(func(n, t int) bool { return t%2 == 1 }),
		"NOT": fn(1, 1, func(c *Context, v []Value) Value {
			return c.mapValues(v[0], func(x Value) Value {
				b, err := c.boolean(x)
				if err != nil {
					return *err
				}
				return Boolean(!b)
			})
		}),
		"TRUE":  fn(0, 0, func(*Context, []Value) Value { return Boolean(true) }),
		"FALSE": fn(0, 0, func(*Context, []Value) Value { return Boolean(false) }),
		"SWITCH": {min: 3, max: 254, call: func(c *Context, args []Expr) Value {
			x := c.scalar(c.Eval(args[0]))
			if x.Type == TypeError {
				return x
			}
			rest := args[1:]
			for len(rest) >= 2 {
				v := c.scalar(c.Eval(rest[0]))
				if v.Type == TypeError {
					return v
				}
				if compare(x, v) == 0 && x.Type == v.Type {
					return c.Eval(rest[1])
				}
				rest = rest[2:]
			}
			if len(rest) == 1 {
				return c.Eval(rest[0])
			}
			return ErrNA
		}},
		"CHOOSE": {min: 2, max: 255, call: func(c *Context, args []Expr) Value {
			n, err := c.number(c.Eval(args[0]))
			if err != nil {
				return *err
			}
			i := int(math.Trunc(n))
			if i < 1 || i >= len(args) {
				return ErrValue
			}
			return c.Eval(args[i])
		}},
		"ISBLANK":   is(func(c *Context, v Value) bool { return v.Type == TypeBlank }),
		"ISERROR":   is(func(c *Context, v Value) bool { return v.Type == TypeError }),
		"ISERR":     is(func(c *Context, v Value) bool { return v.Type == TypeError && v.Str != ErrNA.Str }),
		"ISNA":      is(func(c *Context, v Value) bool { return v.Type == TypeError && v.Str == ErrNA.Str }),
		"ISNUMBER":  is(func(c *Context, v Value) bool { return v.Type == TypeNumber }),
		"ISTEXT":    is(func(c *Context, v Value) bool { return v.Type == TypeText }),
		"ISNONTEXT": is(func(c *Context, v Value) bool { return v.Type != TypeText }),
		"ISLOGICAL": is(func(c *Context, v Value) bool { return v.Type == TypeBool }),
		"ISEVEN":    parity(0),
		"ISODD":     parity(1),
		"ISREF": {min: 1, max: 1, call: func(c *Context, args []Expr) Value {
			return Boolean(c.Eval(args[0]).Type == TypeRange)
		}},
		"ISFORMULA": {min: 1, max: 1, call: func(c *Context, args []Expr) Value {
			v := c.Eval(args[0])
			if v.Type != TypeRange {
				return ErrValue
			}
			f, ok := c.Book.(interface {
				HasFormula(sheet, row, col int) bool
			})
			a := v.Refs[0]
			return Boolean(ok && f.HasFormula(a.Sheet, a.R1, a.C1))
		}},
		"NA": fn(0, 0, func(*Context, []Value) Value { return ErrNA }),
		"ERROR.TYPE": fn(1, 1, func(c *Context, v []Value) Value {
			x := c.scalar(v[0])
			if x.Type != TypeError {
				return ErrNA
			}
			for i, code := range []string{"#NULL!", "#DIV/0!", "#VALUE!", "#REF!", "#NAME?", "#NUM!", "#N/A", "#GETTING_DATA"} {
				if x.Str == code {
					return Num(float64(i + 1))
				}
			}
			return ErrNA
		}),
		"TYPE": fn(1, 1, func(c *Context, v []Value) Value {
			x := v[0]
			if x.Type == TypeRange && !singleCell(x) {
				return Num(64)
			}
			switch c.deref(x).Type {
			case TypeNumber, TypeBlank:
				return Num(1)
			case TypeText:
				return Num(2)
			case TypeBool:
				return Num(4)
			case TypeError:
				return Num(16)
			}
			return Num(64)
		}),
		"N": fn(1, 1, func(c *Context, v []Value) Value {
			x := c.scalar(v[0])
			switch x.Type {
			case TypeNumber, TypeBool:
				return Num(x.Num)
			case TypeError:
				return x
			}
			return Num(0)
		}),
	})
}

func singleCell(v Value) bool {
	return len(v.Refs) == 1 && v.Refs[0].R1 == v.Refs[0].R2 && v.Refs[0].C1 == v.Refs[0].C2
}

func (c *Context) branch(cond Value, args []Expr) Value {
	b, err := c.boolean(cond)
	if err != nil {
		return *err
	}
	switch {
	case b && len(args) > 1:
		if _, missing := args[1].(missingExpr); missing {
			return Num(0)
		}
		return c.Eval(args[1])
	case b:
		return Boolean(true)
	case len(args) > 2:
		if _, missing := args[2].(missingExpr); missing {
			return Num(0)
		}
		return c.Eval(args[2])
	}
	return Boolean(false)
}

// logical is AND, OR and XOR: whether they hold for n values of which t
// are true. Text in ranges is passed over.
func logical(f func(n, t int) bool) *function {
	return &function{min: 1, max: 255, call: func(c *Context, args []Expr) Value {
		n, t := 0, 0
		var err *Value
		c.each(args, func(v Value, direct bool) bool {
			switch v.Type {
			case TypeError:
				err = &v
				return false
			case TypeNumber, TypeBool:
				n++
				if v.Num != 0 {
					t++
				}
			case TypeText:
				if direct {
					b, e := c.boolean(v)
					if e != nil {
						err = e
						return false
					}
					n++
					if b {
						t++
					}
				}
			}
			return true
		})
		if err != nil {
			return *err
		}
		if n == 0 {
			return ErrValue
		}
		return Boolean(f(n, t))
	}}
}

func is(f func(c *Context, v Value) bool) *function {
	return fn(1, 1, func(c *Context, v []Value) Value {
		return c.mapValues(v[0], func(x Value) Value { return Boolean(f(c, x)) })
	})
}

func parity(want int) *function {
	return fn(1, 1, func(c *Context, v []Value) Value {
		x := c.scalar(v[0])
		if x.Type == TypeBlank {
			return Boolean(want == 0)
		}
		n, err := c.number(x)
		if err != nil {
			return *err
		}
		return Boolean(int64(math.Abs(math.Trunc(n)))%2 == int64(want))
	})
}
