# fix-matlab-mcp.ps1
# Registers the MATLAB MCP Core Server as a local MCP server in Claude Desktop.
# Works with both the Microsoft Store and standard versions of Claude Desktop.
#
# IMPORTANT: Run this ONLY while Claude Desktop is fully closed (tray icon -> Quit).
# The Store version of Claude rewrites its config from memory, so edits made
# while it runs are silently wiped.
#
# Usage: double-click fix-matlab-mcp.bat (recommended), or run this file
#        with: powershell -ExecutionPolicy Bypass -File fix-matlab-mcp.ps1

$ErrorActionPreference = 'Stop'

# --- 1. Refuse to run while Claude is open --------------------------------
$claudeProcs = Get-Process | Where-Object { $_.ProcessName -match '^claude' }
if ($claudeProcs) {
    Write-Host ''
    Write-Host 'ERROR: Claude is still running.' -ForegroundColor Red
    Write-Host 'Quit Claude completely (right-click the Claude icon in the system tray near the clock, choose Quit), then run this script again.'
    Read-Host 'Press Enter to close'
    exit 1
}

# --- 2. Locate the Claude config file --------------------------------------
$candidates = @()
# Microsoft Store install (virtualized AppData)
$pkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg) {
    $candidates += Join-Path $pkg.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json'
}
# Standard install
$candidates += Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'

$configPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $configPath) {
    Write-Host 'ERROR: Could not find claude_desktop_config.json. Checked:' -ForegroundColor Red
    $candidates | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Is Claude Desktop installed and has it been run at least once?'
    Read-Host 'Press Enter to close'
    exit 1
}
Write-Host "Config found: $configPath"

# --- 3. Locate the MCP server binary ----------------------------------------
$exeCandidates = @(
    (Join-Path $PSScriptRoot 'matlab-mcp-core-server-win64.exe'),
    (Join-Path $PSScriptRoot 'matlab-mcp-server-windows-x64.exe'),
    "$env:USERPROFILE\matlab-mcp\matlab-mcp-core-server-win64.exe",
    "$env:USERPROFILE\matlab-mcp\matlab-mcp-server-windows-x64.exe",
    "$env:USERPROFILE\Downloads\matlab-mcp-core-server-win64.exe",
    "$env:USERPROFILE\Downloads\matlab-mcp-server-windows-x64.exe"
)
$exePath = $exeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $exePath) {
    Write-Host 'MATLAB MCP server binary not found in the usual places.' -ForegroundColor Yellow
    Write-Host 'Download it from: https://github.com/matlab/matlab-mcp-core-server/releases/latest'
    $exePath = Read-Host 'Enter the full path to the server .exe'
    if (-not (Test-Path -LiteralPath $exePath)) {
        Write-Host "ERROR: $exePath does not exist." -ForegroundColor Red
        Read-Host 'Press Enter to close'
        exit 1
    }
}
Write-Host "Server binary: $exePath"

# --- 4. Locate MATLAB --------------------------------------------------------
$matlabRoot = $null
$matlabDirs = Get-ChildItem 'C:\Program Files\MATLAB' -Directory -Filter 'R20*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending
if ($matlabDirs) {
    $matlabRoot = $matlabDirs[0].FullName   # newest release
    Write-Host "MATLAB found: $matlabRoot"
} else {
    Write-Host 'MATLAB not found under C:\Program Files\MATLAB.' -ForegroundColor Yellow
    $matlabRoot = Read-Host 'Enter your MATLAB root folder (e.g. C:\Program Files\MATLAB\R2023b), or press Enter to skip (server will search the system PATH)'
}

# --- 5. Merge the MCP server entry into the config ---------------------------
Copy-Item -LiteralPath $configPath -Destination "$configPath.backup" -Force

$j = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$matlab = New-Object PSObject
$matlab | Add-Member NoteProperty command $exePath
if ($matlabRoot) {
    $matlab | Add-Member NoteProperty args @('--matlab-root', $matlabRoot)
} else {
    $matlab | Add-Member NoteProperty args @()
}

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

Write-Host ''
Write-Host 'SUCCESS: MATLAB MCP server added to the Claude config.' -ForegroundColor Green
Write-Host "Backup saved as: $configPath.backup"
Write-Host ''
Write-Host 'Start Claude, then check Settings -> Developer for the MATLAB server.'
$answer = Read-Host 'Start Claude now? (y/n)'
if ($answer -eq 'y') {
    if ($pkg -and $configPath.StartsWith($pkg.FullName)) {
        # Store version
        $appId = (Get-StartApps | Where-Object { $_.Name -eq 'Claude' } | Select-Object -First 1).AppID
        if ($appId) { Start-Process 'explorer.exe' "shell:AppsFolder\$appId" }
    } else {
        Start-Process "$env:LOCALAPPDATA\AnthropicClaude\Claude.exe" -ErrorAction SilentlyContinue
    }
}
