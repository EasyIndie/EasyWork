package modules

import (
	"strings"
	"testing"

	"github.com/EasyIndie/EasyWork/internal/platform"
)

func TestVimrcContentPlaceholders(t *testing.T) {
	env := platform.Env{Home: "/home/tester"}
	got := vimrcContent(env)
	if strings.Contains(got, "{{") {
		t.Fatalf("unreplaced placeholder in vimrc:\n%s", got)
	}
	for _, want := range []string{
		"plug#begin(",
		"Plug 'preservim/nerdtree'",
		"Plug 'neoclide/coc.nvim'",
		"set undodir=",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("vimrc missing %q", want)
		}
	}
}

func TestVimrcUsesPlatformPluginDir(t *testing.T) {
	env := platform.Env{Home: "/home/tester"}
	got := vimrcContent(env)
	// Unix 上应为 ~/.vim/plugged（VimPluginDir 由平台决定）
	if !strings.Contains(got, "/plugged") {
		t.Errorf("vimrc missing plugged dir: %s", got)
	}
}
