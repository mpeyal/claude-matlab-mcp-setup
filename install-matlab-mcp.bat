@echo off
rem ===========================================================================
rem  install-matlab-mcp.bat - ONE-CLICK installer
rem  Connects Claude Desktop to MATLAB via the official MathWorks MCP server.
rem  Downloads the server from GitHub, registers it in Claude's config,
rem  and handles failures (Claude running, download errors, bad config).
rem
rem  If Windows blocks this file: right-click -> Properties -> Unblock -> OK
rem  Source: https://github.com/mpeyal/claude-matlab-mcp-setup
rem ===========================================================================
setlocal
set "PS1=%TEMP%\matlab-mcp-install.ps1"
for /f "delims=:" %%a in ('findstr /n /b /c":::PS:::" "%~f0"') do set start=%%a
more +%start% "%~f0" > "%PS1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
del "%PS1%" >nul 2>&1
exit /b
:::PS:::
# ---- PowerShell payload (extracted and run by the .bat above) --------------
$ErrorActionPreference = 'Stop'
function Fail($msg) {
    Write-Host ''
    Write-Host "ERROR: $msg" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}

try {
Write-Host '====================================================='
Write-Host '  Claude + MATLAB MCP - one-click installer'
Write-Host '====================================================='
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 1. Claude must be closed (offer to close it) ---------------------------
$procs = Get-Process | Where-Object { $_.ProcessName -match '^claude' }
if ($procs) {
    Write-Host 'Claude is currently running and must be closed to install.' -ForegroundColor Yellow
    $a = Read-Host 'Close Claude automatically now? (y/n)'
    if ($a -eq 'y') {
        $procs | Stop-Process -Force
        Start-Sleep -Seconds 3
        Write-Host 'Claude closed.'
    } else {
        Fail 'Please quit Claude (tray icon -> Quit) and run this installer again.'
    }
}

# --- 2. Locate the Claude config file ----------------------------------------
$candidates = @()
$pkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg) { $candidates += Join-Path $pkg.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json' }
$candidates += Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
$configPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $configPath) {
    Fail 'Could not find Claude Desktop''s config file. Is Claude Desktop installed and has it been run at least once?'
}
Write-Host "Claude config: $configPath"

# --- 3. Get the MCP server binary (reuse if present, else download) ----------
$installDir = Join-Path $env:USERPROFILE 'matlab-mcp'
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$exePath = Get-ChildItem $installDir -Filter 'matlab-mcp*.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if ($exePath) {
    Write-Host "Server binary already present: $exePath"
} else {
    Write-Host 'Downloading the official MathWorks MCP server from GitHub...'
    $urls = @()
    try {
        $rel = Invoke-RestMethod 'https://api.github.com/repos/matlab/matlab-mcp-core-server/releases/latest' -UseBasicParsing
        $asset = $rel.assets | Where-Object { $_.name -match 'win' -and $_.name -match '\.exe$' } | Select-Object -First 1
        if ($asset) { $urls += ,@($asset.browser_download_url, $asset.name) }
    } catch { Write-Host '  (GitHub API not reachable, using direct links)' }
    $urls += ,@('https://github.com/matlab/matlab-mcp-core-server/releases/latest/download/matlab-mcp-core-server-win64.exe', 'matlab-mcp-core-server-win64.exe')
    $urls += ,@('https://github.com/matlab/matlab-mcp-server/releases/latest/download/matlab-mcp-server-windows-x64.exe', 'matlab-mcp-server-windows-x64.exe')

    $ok = $false
    foreach ($u in $urls) {
        $try = Join-Path $installDir $u[1]
        for ($i = 1; $i -le 2; $i++) {
            try {
                Write-Host "  trying: $($u[0])"
                Invoke-WebRequest $u[0] -OutFile $try -UseBasicParsing
                if ((Get-Item $try).Length -gt 5MB) { $exePath = $try; $ok = $true; break }
            } catch { Write-Host "  attempt $i failed" -ForegroundColor Yellow }
        }
        if ($ok) { break }
    }
    if (-not $ok) {
        Fail "Download failed. Check your internet connection, or download the Windows .exe manually from https://github.com/matlab/matlab-mcp-core-server/releases/latest into $installDir and run this installer again."
    }
    Unblock-File $exePath -ErrorAction SilentlyContinue
    Write-Host "Downloaded: $exePath"
}

# Sanity-check the binary actually runs
try {
    $v = (& $exePath --version 2>&1 | Out-String).Trim()
    Write-Host "Server check OK (version: $v)"
} catch {
    Write-Host 'Warning: could not verify the binary, continuing anyway.' -ForegroundColor Yellow
}

# --- 4. Locate MATLAB ---------------------------------------------------------
$matlabRoot = $null
$matlabDirs = Get-ChildItem 'C:\Program Files\MATLAB' -Directory -Filter 'R20*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending
if ($matlabDirs) {
    $matlabRoot = $matlabDirs[0].FullName
    Write-Host "MATLAB found: $matlabRoot"
    if ($matlabDirs[0].Name -lt 'R2021a') {
        Write-Host 'Warning: the server requires MATLAB R2021a or later.' -ForegroundColor Yellow
    }
} else {
    Write-Host 'MATLAB not found under C:\Program Files\MATLAB.' -ForegroundColor Yellow
    $matlabRoot = Read-Host 'Enter your MATLAB root folder (e.g. C:\Program Files\MATLAB\R2023b), or press Enter to let the server search the system PATH'
}

# --- 5. Merge the MCP entry into the config (backup + rollback on failure) ----
Copy-Item -LiteralPath $configPath -Destination "$configPath.backup" -Force
try {
    $j = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $matlab = New-Object PSObject
    $matlab | Add-Member NoteProperty command $exePath
    if ($matlabRoot) { $matlab | Add-Member NoteProperty args @('--matlab-root', $matlabRoot) }
    else             { $matlab | Add-Member NoteProperty args @() }
    if ($j.PSObject.Properties['mcpServers']) {
        $j.mcpServers | Add-Member -MemberType NoteProperty -Name MATLAB -Value $matlab -Force
    } else {
        $servers = New-Object PSObject
        $servers | Add-Member NoteProperty MATLAB $matlab
        $j | Add-Member -MemberType NoteProperty -Name mcpServers -Value $servers -Force
    }
    $out = $j | ConvertTo-Json -Depth 50
    $null = $out | ConvertFrom-Json   # validate before writing
    [System.IO.File]::WriteAllText($configPath, $out, (New-Object System.Text.UTF8Encoding($false)))
} catch {
    Copy-Item -LiteralPath "$configPath.backup" -Destination $configPath -Force
    Fail "Failed to update the config ($($_.Exception.Message)). Your original config was restored."
}

Write-Host ''
Write-Host 'SUCCESS: MATLAB MCP server installed and registered.' -ForegroundColor Green
Write-Host "  Server : $exePath"
Write-Host "  Config : $configPath (backup: $configPath.backup)"
Write-Host ''
Write-Host 'After Claude starts: Settings -> Developer should list MATLAB.'
Write-Host 'Then try in a chat:  "Run 2+2 in MATLAB"  (first call takes ~30 s)'
Write-Host ''
$a = Read-Host 'Start Claude now? (y/n)'
if ($a -eq 'y') {
    if ($pkg -and $configPath.StartsWith($pkg.FullName)) {
        $appId = (Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1).AppID
        if ($appId) { Start-Process 'explorer.exe' "shell:AppsFolder\$appId" }
    } else {
        Start-Process "$env:LOCALAPPDATA\AnthropicClaude\Claude.exe" -ErrorAction SilentlyContinue
    }
}
} catch {
    Fail "Unexpected error: $($_.Exception.Message)"
}
