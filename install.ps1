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
function Err($msg) { Write-Host "[ERR] $msg" -ForegroundColor Red; exit 1 }

# ---------------- Check for commands ----------------
function Require-Command($cmd) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Err "Missing command: $cmd"
    }
}

function Refresh-Path {
    $env:Path =
        [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# ---------------- Paths ----------------
$UserHome = [Environment]::GetFolderPath("UserProfile")
$FlutterHome = Join-Path $UserHome "flutter"
$AndroidSdkRoot = Join-Path $UserHome "AppData\Local\Android\Sdk"
$CmdlineTools = Join-Path $AndroidSdkRoot "cmdline-tools\latest"

# ---------------- Install Git if missing ----------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Log "Git not found. Installing Git..."
    # Requires Chocolatey
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Log "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    Log "Installing Git via Chocolatey..."
    choco install git -y
    Refresh-Path
} else {
    Log "Git already installed."
}

# ---------------- Refresh PowerShell to use Git ----------------
$GitPath = "C:\Program Files\Git\cmd"
if (-not ($env:Path -like "*$GitPath*")) {
    $env:Path += ";$GitPath"
}

# ---------------- Install Android Studio ----------------
if (-not (Test-Path "C:\Program Files\Android\Android Studio\bin\studio64.exe")) {
    Log "Installing Android Studio via Chocolatey..."
    choco install androidstudio -y
} else {
    Log "Android Studio already installed."
}

# ---------------- Set JAVA_HOME from Android Studio JDK ----------------
Write-Host "[INFO] Installing JDK 17..."
choco install temurin17 -y
Refresh-Path

# Refresh PATH so java is visible immediately
$env:Path =
    [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path","User")

$JavaHome = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory |
    Where-Object { $_.Name -like "jdk-17*" } |
    Sort-Object Name -Descending |
    Select-Object -First 1 |
    Select-Object -ExpandProperty FullName

if (-not $JavaHome) {
    Err "JDK 17 not found under Eclipse Adoptium"
}

# Set JAVA_HOME for current session
$env:JAVA_HOME = $JavaHome
$env:Path = "$JavaHome\bin;$env:Path"

# Set system-wide environment variables
[Environment]::SetEnvironmentVariable("JAVA_HOME", $JavaHome, "Machine")
[Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $AndroidSdkRoot, "Machine")
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $AndroidSdkRoot, "Machine")

Write-Host "[INFO] JAVA_HOME set to $JavaHome"

# ---------------- Install Android SDK command-line tools ----------------
if (-not (Test-Path $CmdlineTools)) {
    Log "Downloading Android command-line tools..."
    $TmpZip = "$env:TEMP\cmdline-tools.zip"
    Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-9477386_latest.zip" -OutFile $TmpZip
    Expand-Archive $TmpZip -DestinationPath (Join-Path $AndroidSdkRoot "cmdline-tools")
    Rename-Item (Join-Path $AndroidSdkRoot "cmdline-tools\cmdline-tools") "latest"
}

# Add SDK tools to PATH (current session)
$env:Path = "$CmdlineTools\bin;$AndroidSdkRoot\platform-tools;$env:Path"

Require-Command sdkmanager

# ---------------- Install latest Android SDK ----------------
Log "Installing Android SDK..."
# Get latest Android platform
$LatestPlatform = & sdkmanager --list | Select-String -Pattern 'platforms;android-(\d+)' | ForEach-Object {
    [PSCustomObject]@{
        Text = $_.Matches[0].Value
        Version = [int]($_.Matches[0].Groups[1].Value)
    }
} | Sort-Object Version -Descending | Select-Object -First 1

# Get latest Build Tools
$LatestBuildTools = & sdkmanager --list | Select-String -Pattern 'build-tools;([0-9.]+)' | ForEach-Object {
    [PSCustomObject]@{
        Text = $_.Matches[0].Value
        VersionParts = $_.Matches[0].Groups[1].Value -split '\.' | ForEach-Object {[int]$_}
    }
} | Sort-Object -Property @{Expression={$_.VersionParts[0]};Descending=$true}, @{Expression={$_.VersionParts[1]};Descending=$true}, @{Expression={$_.VersionParts[2]};Descending=$true} | Select-Object -First 1

# Install latest packages
Log "Installing platform-tools, $($LatestPlatform.Text), $($LatestBuildTools.Text)..."
& sdkmanager "platform-tools" $LatestPlatform.Text $LatestBuildTools.Text

# ---------------- Install Flutter SDK ----------------
if (-not (Test-Path "$FlutterHome\bin\flutter.bat")) {
    Log "Installing Flutter SDK..."
    git clone https://github.com/flutter/flutter.git -b stable $FlutterHome
} else {
    Log "Flutter already installed at $FlutterHome"
}

# Add Flutter to PATH (current session)
$env:Path = "$FlutterHome\bin;$env:Path"

# ---------------- Accept licenses ----------------
Log "Accepting all Android licenses..."
1..20 | ForEach-Object { echo y } | flutter doctor --android-licenses

# ---------------- Flutter config ----------------
flutter config --android-sdk $AndroidSdkRoot

Log "Installation completed!"
Write-Host "Run 'flutter doctor' to verify your setup."

