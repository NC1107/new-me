package estimate

import "testing"

func TestTidySaved(t *testing.T) {
	cases := []struct{ name, brand, wantName, wantBrand string }{
		{"Totino's Cheese Party Pizza", "Totino's GENERAL MILLS SALES INC.", "Totino's Cheese Party Pizza", "Totino's"},
		{"TOTINO'S SAUSAGE PIZZA ROLLS", "GENERAL MILLS SALES INC.", "Totino's Sausage Pizza Rolls", "General Mills"},
		{"Apple", "", "Apple", ""},
		{"Greek Yogurt", "Chobani", "Greek Yogurt", "Chobani"},
	}
	for _, c := range cases {
		gotName, gotBrand := TidySaved(c.name, c.brand)
		if gotName != c.wantName || gotBrand != c.wantBrand {
			t.Errorf("TidySaved(%q, %q) = %q, %q; want %q, %q", c.name, c.brand, gotName, gotBrand, c.wantName, c.wantBrand)
		}
		again, againBrand := TidySaved(gotName, gotBrand)
		if again != gotName || againBrand != gotBrand {
			t.Errorf("TidySaved is not idempotent for %q, %q", c.name, c.brand)
		}
	}
}
