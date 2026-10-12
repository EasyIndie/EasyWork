package cli

import "testing"

func TestLooksLikeEmail(t *testing.T) {
	valid := []string{"a@b.co", "first.last@example.com", "x+tag@sub.example.org"}
	invalid := []string{"", "nope", "@x.com", "a@", "a@b", "a@.com", "a@b."}
	for _, s := range valid {
		if !looksLikeEmail(s) {
			t.Errorf("expected valid: %q", s)
		}
	}
	for _, s := range invalid {
		if looksLikeEmail(s) {
			t.Errorf("expected invalid: %q", s)
		}
	}
}
