package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

type Schema struct {
	ID          string             `json:"$id"`
	Schema      string             `json:"$schema"`
	Title       string             `json:"title"`
	Description string             `json:"description"`
	Type        jsonschemaType     `json:"type"`
	Properties  map[string]*Schema `json:"properties"`
	Items       *Schema            `json:"items"`

	AdditionalProperties bool      `json:"additionalProperties"`
	MinLength            int       `json:"minLength"`
	Enum                 []*string `json:"enum"`
	MinItems             int       `json:"minItems"`
	Required             []string  `json:"required"`
	UniqueItems          bool      `json:"uniqueItems"`

	// Extra fields for template args.
	Path string `json:"-"`
}

// RequiredStr returns "required" or "optional" if the given
// field is in the list of required fields for this schema.
func (s *Schema) RequiredStr(field string) string {
	for _, req := range s.Required {
		if req == field {
			return "required"
		}
	}
	return "optional"
}

// EnumStr joins the enum list for this schema into human-readable markdown, such as
// "Must be one of `local`, `remote`, or `none`."  If this schema has no enum field,
// an empty string is returned.
func (s *Schema) EnumStr() string {
	result := ""
	for i, val := range s.Enum {
		if len(s.Enum) > 2 && i > 0 {
			result += ", "
			if i == len(s.Enum)-1 {
				result += "or"
			}
		}

		if val == nil {
			result += "`null`"
		} else {
			result += "`" + *val + "`"
		}
	}
	if len(result) > 0 {
		result = "Must be one of " + result + "."
	}
	return result
}

// PropertyAnchor returns the markdown/html anchor for a field in a table, if the field
// is an object or array type. The anchor links to another section in the page describing
// that field so that users can navigate the page more easily.
//
// This will return an empty string if the field has no suitable link.
func (t *Schema) PropertyAnchor(field string) string {
	propSchema := t.Properties[field]

	var fieldProperties map[string]*Schema
	switch propSchema.Type[0] {
	case "object":
		fieldProperties = propSchema.Properties
	case "array":
		fieldProperties = propSchema.Items.Properties
	default:
		return ""
	}

	if len(fieldProperties) == 0 {
		// If the type has no properties documented, there's no section in the markdown describing those properties,
		// so there's nothing to link to. This is the case for, e.g. the `meta` field, which has arbitrary data.
		return ""
	}
	// Convert from e.g. `proxy.upstreams.meshGateway` -> `proxy-upstreams-meshgateway` to
	// match markdown/html anchors.
	anchor := strings.Trim(t.Path+"."+field, ".")
	anchor = strings.ReplaceAll(anchor, ".", "-")
	return strings.ToLower(anchor)
}

// Special parsing for the `type` field, which can be a string or []string.
// Normalize the "type" to []string.
type jsonschemaType []string

func (t *jsonschemaType) UnmarshalJSON(data []byte) error {
	var array []string
	if err := json.Unmarshal(data, &array); err == nil {
		*t = append(*t, array...)
		return nil
	}

	var str string
	if err := json.Unmarshal(data, &str); err == nil {
		*t = append(*t, str)
		return nil
	}

	return fmt.Errorf("cannot unmarshal type field as string or []string: %s", string(data))
}
