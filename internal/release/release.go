// Package release 处理发布资产命名、校验与归档解包（update 自升级用）。
package release

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// AssetName 返回发布归档文件名（与 goreleaser/release.yml 命名一致）。
func AssetName(version, osName, arch string) string {
	ext := "tar.gz"
	if osName == "windows" {
		ext = "zip"
	}
	return fmt.Sprintf("easywork_%s_%s_%s.%s", version, osName, arch, ext)
}

// ParseChecksums 从 checksums.txt 内容中取出 asset 的 sha256（小写）；未找到返回空。
func ParseChecksums(text, asset string) string {
	for _, line := range strings.Split(text, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		name := strings.TrimPrefix(fields[1], "*")
		if name == asset {
			return strings.ToLower(fields[0])
		}
	}
	return ""
}

// SHA256File 计算文件 sha256（小写十六进制）。
func SHA256File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer func() { _ = f.Close() }()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// ExtractBinary 从归档中提取 ew / ew.exe 到 destDir，返回解包后的路径。
func ExtractBinary(archivePath, destDir string) (string, error) {
	if strings.HasSuffix(strings.ToLower(archivePath), ".zip") {
		return extractZip(archivePath, destDir)
	}
	return extractTarGz(archivePath, destDir)
}

func isBinaryName(name string) bool {
	b := filepath.Base(name)
	return b == "ew" || b == "ew.exe"
}

func writeEntry(destDir, srcName string, r io.Reader) (string, error) {
	target := filepath.Join(destDir, filepath.Base(srcName))
	out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(out, r); err != nil {
		_ = out.Close()
		return "", err
	}
	if err := out.Close(); err != nil {
		return "", err
	}
	return target, nil
}

func extractTarGz(archivePath, destDir string) (string, error) {
	f, err := os.Open(archivePath)
	if err != nil {
		return "", err
	}
	defer func() { _ = f.Close() }()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return "", err
	}
	defer func() { _ = gz.Close() }()
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", err
		}
		if hdr.Typeflag != tar.TypeReg {
			continue
		}
		if isBinaryName(hdr.Name) {
			return writeEntry(destDir, hdr.Name, tr)
		}
	}
	return "", fmt.Errorf("release: 归档中未找到 ew")
}

func extractZip(archivePath, destDir string) (string, error) {
	r, err := zip.OpenReader(archivePath)
	if err != nil {
		return "", err
	}
	defer func() { _ = r.Close() }()
	for _, f := range r.File {
		if !isBinaryName(f.Name) {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return "", err
		}
		path, werr := writeEntry(destDir, f.Name, rc)
		_ = rc.Close()
		return path, werr
	}
	return "", fmt.Errorf("release: 归档中未找到 ew.exe")
}
