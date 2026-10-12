package release

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"testing"
)

func TestAssetName(t *testing.T) {
	cases := []struct{ version, osName, arch, want string }{
		{"0.2.0", "darwin", "arm64", "easywork_0.2.0_darwin_arm64.tar.gz"},
		{"0.2.0", "linux", "amd64", "easywork_0.2.0_linux_amd64.tar.gz"},
		{"0.2.0", "windows", "amd64", "easywork_0.2.0_windows_amd64.zip"},
	}
	for _, c := range cases {
		if got := AssetName(c.version, c.osName, c.arch); got != c.want {
			t.Errorf("AssetName(%s,%s,%s)=%s want %s", c.version, c.osName, c.arch, got, c.want)
		}
	}
}

func TestParseChecksums(t *testing.T) {
	text := "abc123  easywork_0.2.0_darwin_amd64.tar.gz\n" +
		"def456 *easywork_0.2.0_windows_amd64.zip\n"
	if got := ParseChecksums(text, "easywork_0.2.0_darwin_amd64.tar.gz"); got != "abc123" {
		t.Errorf("got %q", got)
	}
	if got := ParseChecksums(text, "easywork_0.2.0_windows_amd64.zip"); got != "def456" {
		t.Errorf("star prefix not stripped: %q", got)
	}
	if got := ParseChecksums(text, "missing"); got != "" {
		t.Errorf("expected empty, got %q", got)
	}
}

func makeTarGz(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "a.tar.gz")
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	_ = tw.WriteHeader(&tar.Header{Name: name, Mode: 0o755, Size: int64(len(content))})
	_, _ = tw.Write([]byte(content))
	_ = tw.Close()
	_ = gz.Close()
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func makeZip(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "a.zip")
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, _ := zw.Create(name)
	_, _ = w.Write([]byte(content))
	_ = zw.Close()
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestExtractTarGz(t *testing.T) {
	dir := t.TempDir()
	archive := makeTarGz(t, "ew", "#!/bin/sh\necho new\n")
	out, err := ExtractBinary(archive, dir)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(out) != "ew" {
		t.Fatalf("unexpected name: %s", out)
	}
	data, _ := os.ReadFile(out)
	if string(data) != "#!/bin/sh\necho new\n" {
		t.Fatalf("content mismatch: %q", data)
	}
}

func TestExtractZip(t *testing.T) {
	dir := t.TempDir()
	archive := makeZip(t, "ew.exe", "MZ fake windows binary")
	out, err := ExtractBinary(archive, dir)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(out) != "ew.exe" {
		t.Fatalf("unexpected name: %s", out)
	}
	data, _ := os.ReadFile(out)
	if string(data) != "MZ fake windows binary" {
		t.Fatalf("content mismatch: %q", data)
	}
}

func TestExtractMissingBinary(t *testing.T) {
	dir := t.TempDir()
	archive := makeTarGz(t, "README.md", "no binary here")
	if _, err := ExtractBinary(archive, dir); err == nil {
		t.Fatal("expected error for missing binary")
	}
}

func TestSHA256File(t *testing.T) {
	path := filepath.Join(t.TempDir(), "f")
	if err := os.WriteFile(path, []byte("abc"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := SHA256File(path)
	if err != nil {
		t.Fatal(err)
	}
	// sha256("abc")
	want := "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	if got != want {
		t.Fatalf("got %s want %s", got, want)
	}
}
