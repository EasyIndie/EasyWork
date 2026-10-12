package platform

import "testing"

func TestPackageNameMapping(t *testing.T) {
	cases := []struct {
		pm      string
		logical string
		want    string
	}{
		{"winget", "gh", "GitHub.cli"},
		{"choco", "gh", "gh"},
		{"scoop", "gh", "gh"},
		{"brew", "gh", "gh"},
		{"apt-get", "gh", "gh"},
		{"winget", "ripgrep", "BurntSushi.ripgrep.MSVC"},
		{"apt-get", "ripgrep", "ripgrep"},
		{"winget", "node", "OpenJS.NodeJS.LTS"},
		{"brew", "node", "node"},
		{"winget", "glow", "charmbracelet.glow"},
		{"brew", "glow", "glow"},
		{"apt-get", "glow", "glow"},
		{"unknown", "gh", "gh"},
	}
	for _, c := range cases {
		p := PackageManager{name: c.pm}
		if got := p.PackageName(c.logical); got != c.want {
			t.Errorf("%s/%s: got %q want %q", c.pm, c.logical, got, c.want)
		}
	}
}
