<#
.SYNOPSIS
Auto Flutter + Android Install Script for Windows
#>

# ---------------- Admin check (must be first) ----------------
function Err($msg) { Write-Host "[ERR] $msg" -ForegroundColor Red; exit 1 }

if (-not ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Err "Please run this script as Administrator."
}

# ---------------- Helpers ----------------
function Log($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

function Refresh-Path {
    $env:Path =
        [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Require-Command($cmd) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Err "Missing command: $cmd"
    }
}

function Add-ToPath($value) {
    if (-not ($env:Path -split ";" | Where-Object { $_ -eq $value })) {
        $env:Path = "$value;$env:Path"
    }
}

# ---------------- Paths ----------------
$UserHome = [Environment]::GetFolderPath("UserProfile")
$FlutterHome = Join-Path $UserHome "flutter"
$AndroidSdkRoot = Join-Path $UserHome "AppData\Local\Android\Sdk"
$CmdlineTools = Join-Path $AndroidSdkRoot "cmdline-tools\latest"

# ---------------- Install Git if missing ----------------
$GitCmd = Get-Command git -ErrorAction SilentlyContinue

if (-not $GitCmd) {
    Log "Git not found. Installing via Chocolatey..."

    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Log "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
    }

    choco install git -y
    Refresh-Path
}

# Re-detect Git AFTER install
$GitCmd = Get-Command git -ErrorAction SilentlyContinue

if ($GitCmd) {
    $GitExe = $GitCmd.Source
}
elseif (Test-Path "C:\Program Files\Git\cmd\git.exe") {
    $GitExe = "C:\ProgramData\chocolatey\bin\git.exe"
}
else {
    Err "Git installation failed. Git executable not found."
}

Log "Using Git at $GitExe"
& $GitExe --version || Err "Git verification failed"
# ---------------- Install Android Studio ----------------
if (-not (Test-Path "C:\Program Files\Android\Android Studio\bin\studio64.exe")) {
    Log "Installing Android Studio via Chocolatey..."
    choco install androidstudio -y
} else {
    Log "Android Studio already installed."
}

# ---------------- Install JDK 17 ----------------
Write-Host "[INFO] Installing JDK 17..."
choco install temurin17 -y
Refresh-Path

$JavaFolder = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory |
    Where-Object { $_.Name -match '^jdk-17.*' } |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $JavaFolder) {
    Err "JDK 17 not found. Check Temurin17 installation."
}

$JavaHome = $JavaFolder.FullName
$env:JAVA_HOME = $JavaHome
$env:Path = "$JavaHome\bin;$env:Path"

# Set system-wide environment variables
[Environment]::SetEnvironmentVariable("JAVA_HOME", $JavaHome, "Machine")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $AndroidSdkRoot, "Machine")
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $AndroidSdkRoot, "Machine")

Write-Host "[INFO] JAVA_HOME set to $JavaHome"

# ---------------- Android SDK Command-line Tools ----------------
if (-not (Test-Path $CmdlineTools)) {
    Log "Downloading Android command-line tools..."
    $TmpZip = "$env:TEMP\cmdline-tools.zip"
    Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-9477386_latest.zip" -OutFile $TmpZip
    Expand-Archive $TmpZip -DestinationPath (Join-Path $AndroidSdkRoot "cmdline-tools")
    Rename-Item (Join-Path $AndroidSdkRoot "cmdline-tools\cmdline-tools") "latest"
}

$env:Path = "$CmdlineTools\bin;$AndroidSdkRoot\platform-tools;$env:Path"
Require-Command sdkmanager

# ---------------- Install latest Android SDK ----------------
Log "Installing Android SDK..."
$LatestPlatform = & sdkmanager --list | Select-String -Pattern 'platforms;android-(\d+)' | ForEach-Object {
    [PSCustomObject]@{
        Text = $_.Matches[0].Value
        Version = [int]($_.Matches[0].Groups[1].Value)
    }
} | Sort-Object Version -Descending | Select-Object -First 1

$LatestBuildTools = & sdkmanager --list | Select-String -Pattern 'build-tools;([0-9.]+)' | ForEach-Object {
    [PSCustomObject]@{
        Text = $_.Matches[0].Value
        VersionParts = $_.Matches[0].Groups[1].Value -split '\.' | ForEach-Object {[int]$_}
    }
} | Sort-Object -Property @{Expression={$_.VersionParts[0]};Descending=$true}, @{Expression={$_.VersionParts[1]};Descending=$true}, @{Expression={$_.VersionParts[2]};Descending=$true} | Select-Object -First 1

Log "Installing platform-tools, $($LatestPlatform.Text), $($LatestBuildTools.Text)..."
& sdkmanager "platform-tools" $LatestPlatform.Text $LatestBuildTools.Text

# ---------------- Install Flutter ----------------
if (-not (Test-Path "$FlutterHome\bin\flutter.bat")) {
    Log "Installing Flutter SDK..."
    & $GitExe clone https://github.com/flutter/flutter.git -b stable $FlutterHome
} else {
    Log "Flutter already installed."
}

$FlutterExe = Join-Path $FlutterHome "bin\flutter.bat"
Add-ToPath "$FlutterHome\bin"

# ---------------- Flutter setup ----------------
Log "Accepting Android licenses..."
1..20 | ForEach-Object { "y" } | & $FlutterExe doctor --android-licenses

& $FlutterExe config --android-sdk $AndroidSdkRoot

Log "Installation completed!"
Write-Host "Run 'flutter doctor' to verify your setup."
