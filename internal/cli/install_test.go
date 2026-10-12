package cli

import (
	"reflect"
	"strings"
	"testing"
)

func TestParseTargetsComponentSelection(t *testing.T) {
	cases := []struct {
		name string
		args []string
		want map[string]*target
	}{
		{
			name: "module means all components",
			args: []string{"ai"},
			want: map[string]*target{"ai": {all: true}},
		},
		{
			name: "explicit component",
			args: []string{"ai/claude"},
			want: map[string]*target{"ai": {components: []string{"claude"}}},
		},
		{
			name: "component shorthand",
			args: []string{"claude"},
			want: map[string]*target{"ai": {components: []string{"claude"}}},
		},
		{
			name: "space separated subset",
			args: []string{"ai/codex", "ai/pi"},
			want: map[string]*target{"ai": {components: []string{"codex", "pi"}}},
		},
		{
			name: "space separated shorthand",
			args: []string{"claude", "pi"},
			want: map[string]*target{"ai": {components: []string{"claude", "pi"}}},
		},
		{
			name: "mixed targets",
			args: []string{"git", "ai/pi"},
			want: map[string]*target{
				"git": {all: true},
				"ai":  {components: []string{"pi"}},
			},
		},
		{
			name: "legacy alias resolves to canonical module",
			args: []string{"ai-tools"},
			want: map[string]*target{"ai": {all: true}},
		},
		{
			name: "legacy alias with component",
			args: []string{"ai-tools/claude"},
			want: map[string]*target{"ai": {components: []string{"claude"}}},
		},
		{
			name: "bare module wins over components",
			args: []string{"ai/claude", "ai"},
			want: map[string]*target{"ai": {all: true, components: []string{"claude"}}},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseTargets(tc.args)
			if err != nil {
				t.Fatalf("parseTargets(%v) error: %v", tc.args, err)
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("parseTargets(%v) = %#v, want %#v", tc.args, got, tc.want)
			}
		})
	}
}

func TestParseTargetsRejectsUnknown(t *testing.T) {
	for _, args := range [][]string{
		{"bogus"},
		{"ai/bogus"},
		{"ai/"},
		{"ai/claude,codex"}, // 逗号不再是分隔符 → 非法子工具名
		{"ai/x/y"},          // 子工具名不能含 '/'
		{"ai/bad\x01"},      // 控制字符
	} {
		if _, err := parseTargets(args); err == nil {
			t.Fatalf("parseTargets(%v) expected error", args)
		}
	}
}

// 名字原样保留：含空格的名字（引号作为单参数传入）必须在错误信息中完整回显。
func TestParseTargetsPreservesNamesWithSpaces(t *testing.T) {
	_, err := parseTargets([]string{"ai/my tool"})
	if err == nil {
		t.Fatal("expected error for unknown component with space")
	}
	if !strings.Contains(err.Error(), "my tool") {
		t.Fatalf("error should preserve spaces, got: %v", err)
	}
}
