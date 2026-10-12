package platform

import (
	"errors"
	"io"
	"net/http"
	"time"
)

// ErrOffline 在离线模式下请求网络时返回。
var ErrOffline = errors.New("easywork: 离线模式，已跳过网络请求")

var httpClient = &http.Client{Timeout: 30 * time.Second}

// Download 下载 url 到 path。离线判定由调用方负责。
func Download(url, path string) error {
	resp, err := httpClient.Get(url)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return errors.New("easywork: 下载失败 HTTP " + resp.Status)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	return AtomicWrite(path, data, 0o644)
}
