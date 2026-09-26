package drawingml

import (
	"encoding/json"
	"errors"
)

func marshalPair(a, b any) ([]byte, error) {
	return json.Marshal([]any{a, b})
}

func unmarshalPair(data []byte, a, b any) error {
	var raw []json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	if len(raw) != 2 {
		return errors.New("drawingml: expected a pair")
	}
	if err := json.Unmarshal(raw[0], a); err != nil {
		return err
	}
	return json.Unmarshal(raw[1], b)
}
