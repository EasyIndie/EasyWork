<#
EasyWork - bootstrap.ps1 end-to-end test (local mirror, no network).

Covers the three critical paths of the Windows install entry point:
  1. install a pinned version (EASYWORK_VERSION)
  2. resolve "latest" through the API and install it
  3. tampered archive must fail sha256 verification and must NOT overwrite
     an already installed binary

NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 parses
BOM-less scripts using the ANSI code page, so non-ASCII text here can break
the parser. bootstrap.ps1 itself may contain UTF-8, so we run a BOM-added
copy of it (see Invoke-Bootstrap).

Usage (Windows):
  # inside the repo (CI): builds the binary itself
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/bootstrap-e2e.ps1

  # no source tree (real machine check): pass a prebuilt exe
  powershell -NoProfile -ExecutionPolicy Bypass -File bootstrap-e2e.ps1 -Exe .\ew.exe

Parameters:
  -Exe              prebuilt ew.exe (omit to run "go build" from the repo root)
  -BootstrapScript  path to bootstrap.ps1 (default: next to this script / repo root)
#>
param(
    [string]$Exe = '',
    [string]$BootstrapScript = ''
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BootstrapScript) {
    $candidate = Join-Path $Root 'bootstrap.ps1'
    if (-not (Test-Path $candidate)) { $candidate = Join-Path $PSScriptRoot 'bootstrap.ps1' }
    $BootstrapScript = $candidate
}
if (-not (Test-Path $BootstrapScript)) { throw "bootstrap.ps1 not found: $BootstrapScript" }
$Ver = '0.9.9'
$Arch = switch -Regex ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    '^(X64|AMD64|x86_64)$' { 'amd64' }
    '^(Arm64|ARM64|aarch64)$' { 'arm64' }
    default { throw "unsupported architecture" }
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ("ew-e2e-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Job = $null

function Ok($m) { Write-Host "  OK $m" }
function Fail($m) { Write-Host "  FAIL $m" -ForegroundColor Red; exit 1 }

function New-Mirror($Dir) {
    $verDir = Join-Path $Dir $Ver
    New-Item -ItemType Directory -Force -Path $verDir, (Join-Path $Dir "repos/EasyIndie/EasyWork/releases") | Out-Null
    $asset = "easywork_${Ver}_windows_${Arch}.zip"
    Compress-Archive -Path (Join-Path $Work 'ew.exe') -DestinationPath (Join-Path $verDir $asset) -Force
    $hash = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $verDir $asset)).Hash.ToLower()
    "$hash  $asset" | Out-File -FilePath (Join-Path $verDir 'checksums.txt') -Encoding ascii
    '{"tag_name":"' + $Ver + '"}' | Out-File -FilePath (Join-Path $Dir 'repos/EasyIndie/EasyWork/releases/latest') -Encoding ascii
}

function Start-MirrorServer($Mirror, $Port) {
    $script = {
        param($root, $port)
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://127.0.0.1:$port/")
        $listener.Start()
        while ($listener.IsListening) {
            try { $ctx = $listener.GetContext() } catch { break }
            $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
            $file = Join-Path $root $rel
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                $bytes = [IO.File]::ReadAllBytes($file)
                $ctx.Response.ContentType = 'application/octet-stream'
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $ctx.Response.StatusCode = 404
            }
            $ctx.Response.Close()
        }
    }
    return Start-Job -ScriptBlock $script -ArgumentList $Mirror, $Port
}

function Free-Port {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $l.Start()
    $port = ($l.LocalEndpoint).Port
    $l.Stop()
    return $port
}

function Invoke-Bootstrap($Base, $BinDir, [switch]$Latest) {
    $env:EASYWORK_BIN_DIR = $BinDir
    $env:EASYWORK_DOWNLOAD_BASE = $Base
    $env:EASYWORK_SKIP_PATH = '1'
    if ($Latest) {
        Remove-Item Env:\EASYWORK_VERSION -ErrorAction SilentlyContinue
        $env:EASYWORK_API_BASE = $Base
    } else {
        $env:EASYWORK_VERSION = $Ver
        Remove-Item Env:\EASYWORK_API_BASE -ErrorAction SilentlyContinue
    }
    # PS 5.1 parses BOM-less UTF-8 scripts as ANSI; run a BOM-added copy instead
    $bootCopy = Join-Path $Work 'bootstrap.run.ps1'
    [IO.File]::WriteAllText($bootCopy, (Get-Content -Raw -Encoding UTF8 $BootstrapScript), (New-Object System.Text.UTF8Encoding($true)))
    # 用 Start-Process 重定向，避免子进程 stderr 触发 NativeCommandError
    $outFile = Join-Path $Work 'bootstrap.out'
    $errFile = Join-Path $Work 'bootstrap.err'
    $proc = Start-Process -FilePath 'powershell' -NoNewWindow -Wait -PassThru `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $bootCopy) `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $text = ''
    foreach ($f in @($outFile, $errFile)) {
        if (Test-Path $f) { $text += (Get-Content -Raw -Encoding UTF8 $f) }
    }
    return @{ Code = $proc.ExitCode; Log = $text }
}

function Get-InstalledVersion($BinDir) {
    $exe = Join-Path $BinDir 'ew.exe'
    if (-not (Test-Path $exe)) { return '' }
    $json = & $exe version --json --offline
    if ($json -match '"version":"([^"]+)"') { return $Matches[1] }
    return ''
}

try {
    Write-Host "== prepare binary $Ver =="
    $target = Join-Path $Work 'ew.exe'
    if ($Exe) {
        if (-not (Test-Path $Exe)) { Fail "-Exe not found: $Exe" }
        Copy-Item $Exe $target -Force
    } else {
        & go build -trimpath -ldflags "-X github.com/EasyIndie/EasyWork/internal/version.Version=$Ver" `
            -o $target "$Root/cmd/ew"
        if ($LASTEXITCODE -ne 0) { Fail 'go build failed' }
    }

    $mirror = Join-Path $Work 'mirror'
    New-Mirror $mirror
    $port = Free-Port
    $Job = Start-MirrorServer $mirror $port
    $base = "http://127.0.0.1:$port"
    Start-Sleep -Milliseconds 800

    $binDir = Join-Path $Work 'bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null

    Write-Host '== 1. pinned version install =='
    $r = Invoke-Bootstrap $base $binDir
    if ($r.Code -ne 0) { Write-Host $r.Log; Fail 'bootstrap failed (pinned)' }
    if ((Get-InstalledVersion $binDir) -ne $Ver) { Fail 'version mismatch (pinned)' }
    if (-not (Test-Path (Join-Path $binDir 'easywork.exe'))) { Fail 'easywork.exe alias missing' }
    & (Join-Path $binDir 'ew.exe') status --json --offline | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'ew status not working after install' }
    Ok 'pinned install + alias + status'

    Write-Host '== 2. no EASYWORK_VERSION (resolve latest via API) =='
    Remove-Item (Join-Path $binDir 'ew.exe') -Force
    $r = Invoke-Bootstrap $base $binDir -Latest
    if ($r.Code -ne 0) { Write-Host $r.Log; Fail 'bootstrap failed (latest)' }
    if ((Get-InstalledVersion $binDir) -ne $Ver) { Fail 'version mismatch (latest)' }
    if ($r.Log -notmatch 'sha256') { Fail 'sha256 verification not performed' }
    Ok 'latest install + sha256 verified'

    Write-Host '== 3. tampered archive must fail and not overwrite =='
    $tamper = Join-Path $Work 'tamper'
    Copy-Item -Recurse $mirror $tamper
    $asset = "easywork_${Ver}_windows_${Arch}.zip"
    Add-Content -Path (Join-Path $tamper "$Ver/$asset") -Value 'tampered' -NoNewline
    $port2 = Free-Port
    $Job2 = Start-MirrorServer $tamper $port2
    Start-Sleep -Milliseconds 800
    $r = Invoke-Bootstrap "http://127.0.0.1:$port2" $binDir
    if ($r.Code -eq 0) { Write-Host $r.Log; Fail 'tampered archive was installed (verification ineffective)' }
    if ($r.Log -notmatch 'checksum mismatch') { Write-Host $r.Log; Fail 'failure reason is not checksum mismatch' }
    if ((Get-InstalledVersion $binDir) -ne $Ver) { Fail 'corrupted download overwrote installed binary' }
    Stop-Job $Job2 -ErrorAction SilentlyContinue
    Remove-Job $Job2 -Force -ErrorAction SilentlyContinue
    Ok 'tampered archive rejected, installed binary untouched'

    Write-Host 'bootstrap.ps1 e2e passed (pinned / latest / tamper)'
} finally {
    if ($Job) {
        Stop-Job $Job -ErrorAction SilentlyContinue
        Remove-Job $Job -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
    Remove-Item Env:\EASYWORK_BIN_DIR, Env:\EASYWORK_DOWNLOAD_BASE, Env:\EASYWORK_SKIP_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\EASYWORK_API_BASE, Env:\EASYWORK_VERSION -ErrorAction SilentlyContinue
}
