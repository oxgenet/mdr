<#
.SYNOPSIS
    Boot an emulator, run the full instrumented suite, and summarise results.

.DESCRIPTION
    The Android counterpart of ios/build-app.sh: one command from a cold
    machine to a pass/fail verdict.

    Unlike the iOS script this does NOT build the Rust core. On a Windows host
    with Smart App Control enforced, Cargo cannot run at all (see
    android/README.md). Put a prebuilt libmdr.so in place first:

        android/app/src/main/jniLibs/x86_64/libmdr.so      (emulator)
        android/app/src/main/jniLibs/arm64-v8a/libmdr.so   (real devices)

    On a machine where Cargo does work, drop -PskipRustBuild and Gradle's
    :app:buildRustCore task produces both automatically.

    ASCII only on purpose: Windows PowerShell 5.1 reads a BOM-less script as
    ANSI, and any non-ASCII character here becomes a parse error.

.PARAMETER Avd
    Name of the AVD to boot. Defaults to the first one configured.

.PARAMETER TestClass
    Restrict the run to one class, e.g. net.oxge.mdr.MdrCoreInstrumentedTest.

.EXAMPLE
    ./run-device-tests.ps1
    ./run-device-tests.ps1 -TestClass net.oxge.mdr.MdrCoreInstrumentedTest
#>
[CmdletBinding()]
param(
    [string]$Avd,
    [string]$TestClass
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$booted = $false

if (-not (Test-Path $adb)) { throw "adb not found at $adb - set ANDROID_HOME" }

$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
if (-not $env:JAVA_HOME) {
    $jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Filter 'jdk-17*' -Directory -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($jdk) { $env:JAVA_HOME = $jdk.FullName }
}

# The native core has to be present; the suite is meaningless without it.
$abi = 'x86_64'
$so = Join-Path $root "app\src\main\jniLibs\$abi\libmdr.so"
if (Test-Path $so) {
    Write-Host "core: $so ($((Get-Item $so).Length) bytes)" -ForegroundColor Green
} else {
    Write-Warning "No libmdr.so for $abi at: $so"
    Write-Warning "MdrCoreInstrumentedTest and ViewerFlowTest will fail with UnsatisfiedLinkError."
    Write-Warning "See docs/mobile-test-handoff.md Task A for how to build it."
}

# Boot an emulator unless one is already attached.
$attached = @(& $adb devices | Select-String '\sdevice$').Count
if ($attached -eq 0) {
    if (-not $Avd) { $Avd = (& $emulator -list-avds | Select-Object -First 1) }
    if (-not $Avd) { throw 'No AVD configured - create one in Android Studio first.' }
    Write-Host "booting $Avd ..." -ForegroundColor Cyan
    Start-Process -FilePath $emulator `
        -ArgumentList '-avd', $Avd, '-no-window', '-no-audio', '-no-boot-anim', '-gpu', 'swiftshader_indirect' `
        -WindowStyle Hidden
    & $adb wait-for-device
    & $adb shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 2; done;'
    $booted = $true
}
& $adb devices

$gradleArgs = @(':app:connectedDebugAndroidTest', '-PskipRustBuild', '--no-daemon')
if ($TestClass) {
    $gradleArgs += "-Pandroid.testInstrumentationRunnerArguments.class=$TestClass"
}

Push-Location $root
try {
    & (Join-Path $root 'gradlew.bat') @gradleArgs
} finally {
    Pop-Location
}

# Summarise from the JUnit XML, which survives a failed Gradle run.
# Group by classname rather than trusting <testsuite name>: the runner emits a
# single suite covering every class and names it after whichever ran first.
$results = Join-Path $root 'app\build\outputs\androidTest-results\connected'
$cases = Get-ChildItem $results -Recurse -Filter *.xml -ErrorAction SilentlyContinue | ForEach-Object {
    ([xml](Get-Content $_.FullName)).testsuite.testcase
}
$total = 0
$failed = 0
$cases | Group-Object classname | Sort-Object Name | ForEach-Object {
    $bad = @($_.Group | Where-Object { $_.failure }).Count
    $total += $_.Count
    $failed += $bad
    '{0,-45} {1,3} run, {2} failed' -f $_.Name, $_.Count, $bad
}

if ($booted) { & $adb emu kill | Out-Null }

if ($total -eq 0) {
    Write-Host 'RESULT: FAIL - no tests ran' -ForegroundColor Red
    exit 1
}
if ($failed -gt 0) {
    Write-Host "RESULT: FAIL - $failed of $total tests failed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: PASS - $total tests" -ForegroundColor Green
exit 0
