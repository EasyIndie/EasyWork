<#
EasyWork — Windows 原生引导脚本（PowerShell 一行安装）

用法:
  irm https://raw.githubusercontent.com/EasyIndie/EasyWork/main/bootstrap.ps1 | iex

可覆盖（环境变量）:
  EASYWORK_VERSION       指定版本（tag，不含前导 v；默认取 latest）
  EASYWORK_REPO          仓库（默认 EasyIndie/EasyWork）
  EASYWORK_BIN_DIR       安装目录（默认 %USERPROFILE%\.local\bin）
  EASYWORK_DOWNLOAD_BASE 资产基址（默认 GitHub releases/download；可指向镜像）
  EASYWORK_API_BASE      API 基址（默认 https://api.github.com）
#>
$ErrorActionPreference = 'Stop'

# PS5.1 默认可能未启用 TLS1.2
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$Repo = if ($env:EASYWORK_REPO) { $env:EASYWORK_REPO } else { 'EasyIndie/EasyWork' }
$Version = $env:EASYWORK_VERSION
$BinDir = $env:EASYWORK_BIN_DIR
$DownloadBase = if ($env:EASYWORK_DOWNLOAD_BASE) { $env:EASYWORK_DOWNLOAD_BASE.TrimEnd('/') } else { "https://github.com/$Repo/releases/download" }
$ApiBase = if ($env:EASYWORK_API_BASE) { $env:EASYWORK_API_BASE.TrimEnd('/') } else { 'https://api.github.com' }

function Log($m) { Write-Host "  $m" }
function Die($m) { Write-Host "  x $m" -ForegroundColor Red; throw $m }

# ── 架构 ────────────────────────────────────────────────────
$rawArch = $env:PROCESSOR_ARCHITECTURE
try { $rawArch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() } catch {}
$arch = switch -Regex ($rawArch) {
    '^(X64|AMD64|x86_64)$' { 'amd64' }
    '^(Arm64|ARM64|aarch64)$' { 'arm64' }
    default { Die "不支持的架构: $rawArch" }
}

# ── 版本 ────────────────────────────────────────────────────
if (-not $Version) {
    try {
        $resp = Invoke-RestMethod -Headers @{ 'User-Agent' = 'easywork-bootstrap' } -Uri "$ApiBase/repos/$Repo/releases/latest"
        $Version = $resp.tag_name
    } catch {
        Die '无法获取最新版本，请设置 $env:EASYWORK_VERSION 后重试'
    }
}
if (-not $Version) { Die '无法获取最新版本，请设置 $env:EASYWORK_VERSION 后重试' }
$Version = $Version.TrimStart('v')

# ── 安装目录 ────────────────────────────────────────────────
if (-not $BinDir) { $BinDir = Join-Path $env:USERPROFILE '.local\bin' }
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$asset = "easywork_${Version}_windows_${arch}.zip"
$url = "$DownloadBase/$Version/$asset"

Log "EasyWork $Version (windows/$arch)"
Log "下载: $url"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ew-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile (Join-Path $tmp 'archive.zip')
    Expand-Archive -Path (Join-Path $tmp 'archive.zip') -DestinationPath $tmp -Force
    $exe = Join-Path $tmp 'ew.exe'
    if (-not (Test-Path $exe)) { Die '压缩包中未找到 ew.exe' }
    Copy-Item $exe (Join-Path $BinDir 'ew.exe') -Force
    Copy-Item $exe (Join-Path $BinDir 'easywork.exe') -Force
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ── PATH / PATHEXT（仅对新会话生效）─────────────────────────
$p = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $p) { $p = '' }
if (($p -split ';') -notcontains $BinDir) {
    [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ';' + $BinDir), 'User')
    Log "已加入用户 PATH: $BinDir"
} else {
    Log "用户 PATH 已包含: $BinDir"
}
$pe = [Environment]::GetEnvironmentVariable('PATHEXT', 'User')
if (-not $pe) { $pe = [Environment]::GetEnvironmentVariable('PATHEXT', 'Machine') }
if (-not $pe) { $pe = '.COM;.EXE;.BAT;.CMD' }
if (($pe.ToUpper() -split ';') -notcontains '.EXE') {
    [Environment]::SetEnvironmentVariable('PATHEXT', ($pe.TrimEnd(';') + ';.EXE'), 'User')
    Log '已补 PATHEXT: .EXE'
}

Log "已安装: $BinDir\ew.exe, $BinDir\easywork.exe"
Log '下一步: ew install --yes'
