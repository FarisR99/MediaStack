<#
.SYNOPSIS
  Build NVEncC64.exe with MSVC against the MediaStack FFmpeg.

.DESCRIPTION
  NVEnc's Visual Studio project links FFmpeg through nvenc\ffmpeg_lgpl\
  (include\ plus lib\x64\ with MSVC import libs and DLLs). This script fills
  that folder from one of two routes, runs MSBuild, and copies the result to
  out\ucrt64\nvencc\ for scripts/windows/package.sh.

  Route A (default): reuse the UCRT64 FFmpeg from out\ucrt64\prefix. FFmpeg's
    MinGW build already emits MSVC-compatible import libs (bin\*.lib); libass,
    libplacebo, libdovi and libhdr10plus-rs DLLs come from UCRT64/the prefix. The same DLLs as
    mpv, and FFmpeg is built only once.
  Route B: build a second, minimal FFmpeg with --toolchain=msvc
    (scripts/windows/build-ffmpeg-msvc.sh) into out\msvc\prefix, and use that.
    Use it if Route A won't link or crashes at runtime.

  Run from a "Developer PowerShell for VS 2022" so cl.exe, lib.exe, dumpbin
  and msbuild are on PATH. Record the route that works in
  docs/building-windows.md and docs/agents/build-windows.md.

  The AviSynth+/VapourSynth/OpenCL/Vship and ONNX Runtime headers are
  downloaded into out\ucrt64\build\nvenc-headers unless AVISYNTH_SDK,
  VAPOURSYNTH_SDK, OPENCL_HEADERS, VSHIP_DIR and ONNXRUNTIME_DIR are already set.

.PARAMETER Jobs
  How many source files compile at once (default: half the logical CPUs).
  NVEnc's CUDA files are huge: with every core busy, and nvcc's own -t 0
  fanning each file out per GPU architecture, cicc/cl run out of memory
  ("compiler is out of heap space", "LLVM error : out of memory"). Lower it
  further if that still happens. nvcc always runs single-threaded here.

.EXAMPLE
  .\scripts\windows\nvencc-spike.ps1
  .\scripts\windows\nvencc-spike.ps1 -Jobs 4
  .\scripts\windows\nvencc-spike.ps1 -Route B
#>
param(
    [ValidateSet('A', 'B')] [string] $Route = 'A',
    [string] $Msys2Root = 'C:\msys64',
    [string] $Configuration = 'RelStatic',
    [int] $Jobs = [math]::Max(1, [int]([Environment]::ProcessorCount / 2))
)
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
$Nvenc = Join-Path $Root 'nvenc'
$Ucrt = Join-Path $Msys2Root 'ucrt64'
$Stage = Join-Path $Nvenc 'ffmpeg_lgpl'     # ignored by NVEnc's .gitignore
$StageLib = Join-Path $Stage 'lib\x64'
$StageInc = Join-Path $Stage 'include'

function Need($cmd) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd not found: run this from a Developer PowerShell for VS 2022"
    }
}
Need cl.exe; Need lib.exe; Need dumpbin.exe; Need msbuild.exe
if (-not $env:CUDA_PATH) { throw 'CUDA_PATH is not set: install the CUDA Toolkit' }

# SDK headers NVEnc's project includes. Its release CI takes AviSynth+,
# VapourSynth, OpenCL and Vship from rigaya's hwenc_headers bundle; ONNX Runtime
# is loaded at runtime, so only its include\ is needed. Each URL is in stack.conf;
# a variable that is already set wins.
function Get-StackConf([string] $Key) {
    (Select-String -Path "$Root\stack.conf" -Pattern "^$Key=(.+)$").Matches[0].Groups[1].Value
}
# Get-Headers <url> [tar member patterns]: extract once into out\, return the dir.
function Get-Headers([string] $Url, [string[]] $Members = @()) {
    $file = [IO.Path]::GetFileName($Url)
    $dir = Join-Path $Root ('out\ucrt64\build\nvenc-headers\' + [IO.Path]::GetFileNameWithoutExtension($file))
    if (-not (Test-Path "$dir\.done")) {
        Write-Host "==> Fetching headers: $Url"
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force $dir | Out-Null
        $archive = Join-Path (Split-Path $dir) $file
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $archive
        & "$env:SystemRoot\System32\tar.exe" -xf $archive -C $dir @Members
        if ($LASTEXITCODE) { throw "could not extract $archive" }
        Remove-Item $archive
        New-Item -ItemType File "$dir\.done" | Out-Null
    }
    $dir
}
$HeaderDirs = [ordered]@{
    AVISYNTH_SDK = 'AviSynthPlus\avs_core'; VAPOURSYNTH_SDK = 'vapoursynth'
    OPENCL_HEADERS = 'openclheaders'; VSHIP_DIR = 'vship'
}
if ($HeaderDirs.Keys | Where-Object { -not (Test-Path "env:$_") }) {
    $hw = Get-Headers (Get-StackConf 'NVENC_HEADERS_URL')
    foreach ($var in $HeaderDirs.Keys) {
        if (-not (Test-Path "env:$var")) { Set-Item "env:$var" (Join-Path $hw $HeaderDirs[$var]) }
    }
}
if (-not $env:ONNXRUNTIME_DIR) {
    $ort = Get-Headers (Get-StackConf 'NVENC_ONNXRUNTIME_URL') '*/include/*'
    $env:ONNXRUNTIME_DIR = (Get-ChildItem -Directory $ort | Select-Object -First 1).FullName
}

# New-ImportLib <dll> <out.lib>: MSVC import lib from a DLL's export table.
function New-ImportLib([string] $Dll, [string] $OutLib) {
    $name = [IO.Path]::GetFileName($Dll)
    $exports = & dumpbin.exe /nologo /exports $Dll |
        Select-String '^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]{8}\s+(\S+)' |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
    $def = [IO.Path]::ChangeExtension($OutLib, '.def')
    @("LIBRARY $name", 'EXPORTS') + $exports | Set-Content -Encoding ascii $def
    & lib.exe /nologo /machine:x64 "/def:$def" "/out:$OutLib" | Out-Null
    if ($LASTEXITCODE) { throw "lib.exe failed for $Dll" }
}

if ($Route -eq 'B') {
    Write-Host '==> Route B: building FFmpeg with the MSVC toolchain'
    $bash = Join-Path $Msys2Root 'msys2_shell.cmd'
    & $bash -ucrt64 -use-full-path -defterm -no-start -here -c 'scripts/windows/build-ffmpeg-msvc.sh'
    if ($LASTEXITCODE) { throw 'build-ffmpeg-msvc.sh failed' }
    $Prefix = Join-Path $Root 'out\msvc\prefix'
} else {
    Write-Host '==> Route A: reusing the UCRT64 FFmpeg'
    $Prefix = Join-Path $Root 'out\ucrt64\prefix'
}
if (-not (Test-Path "$Prefix\bin\avcodec.lib")) {
    throw "$Prefix\bin\avcodec.lib missing: build FFmpeg first (scripts/windows/build.sh, or -Route B)"
}

Write-Host "==> Staging $Stage"
Remove-Item -Recurse -Force $Stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $StageLib, $StageInc | Out-Null
Copy-Item -Recurse "$Prefix\include\*" $StageInc
foreach ($dir in 'ass', 'libdovi', 'libhdr10plus-rs') {
    if (Test-Path "$Ucrt\include\$dir") { Copy-Item -Recurse -Force "$Ucrt\include\$dir" $StageInc }
}
foreach ($lib in 'avcodec', 'avformat', 'avutil', 'avfilter', 'avdevice', 'swresample', 'swscale') {
    Copy-Item "$Prefix\bin\$lib.lib" $StageLib
    Copy-Item "$Prefix\bin\$lib-*.dll" $StageLib
}
# Runtime-loaded DLLs (NVEnc's post-build step copies libass-*.dll and libplacebo-*.dll).
Copy-Item "$Ucrt\bin\libass-9.dll" $StageLib
$placebo = Get-ChildItem "$Root\out\ucrt64\prefix\bin\libplacebo-*.dll" -ErrorAction SilentlyContinue
if ($placebo) { Copy-Item $placebo.FullName $StageLib } else { Write-Warning 'libplacebo DLL not found; libplacebo filters will be unavailable' }
# NVEnc links dovi.lib and hdr10plus-rs.lib (#pragma comment); point them at
# UCRT64's DLLs (scripts/windows/deps.sh installs both).
foreach ($rs in @{ lib = 'dovi.lib'; dll = 'libdovi.dll' }, @{ lib = 'hdr10plus-rs.lib'; dll = 'libhdr10plus-rs.dll' }) {
    $dll = Join-Path "$Ucrt\bin" $rs.dll
    if (-not (Test-Path $dll)) { throw "$dll missing: run scripts/windows/deps.sh" }
    New-ImportLib $dll (Join-Path $StageLib $rs.lib)
    Copy-Item $dll $StageLib
}

# NVEnc's post-build step copies libplacebo-*.dll into the build output, which
# keeps DLLs of older libplacebo API versions; drop them so only the staged one
# reaches out\ucrt64\nvencc.
Remove-Item (Join-Path $Nvenc "_build\x64\$Configuration\libplacebo-*.dll") -ErrorAction SilentlyContinue
Write-Host "==> MSBuild NVEncC ($Configuration|x64, $Jobs jobs)"
# One project at a time, $Jobs files at a time, and nvcc without -t 0
# (cudaver.props sets CUDA_THREADS; a global property overrides it).
& msbuild.exe "$Nvenc\NVEnc.sln" /t:NVEncC /m:1 /nologo /v:minimal "/p:Configuration=$Configuration" /p:Platform=x64 `
    "/p:CL_MPCount=$Jobs" "/p:CUDA_THREADS=-t 1"
if ($LASTEXITCODE) { throw "MSBuild failed (route $Route). Try the other route, and note the error in docs/building-windows.md" }

$Built = Join-Path $Nvenc "_build\x64\$Configuration"
$Out = Join-Path $Root 'out\ucrt64\nvencc'
Remove-Item -Recurse -Force $Out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item "$Built\NVEncC64.exe", "$Built\*.dll" $Out
# UCRT64 runtime DLLs the MinGW-built FFmpeg/libass/libplacebo need.
$env:PATH = "$Ucrt\bin;$env:PATH"

Write-Host "==> Smoke test"
& "$Out\NVEncC64.exe" --version
& "$Out\NVEncC64.exe" --check-avcodec-dll
Write-Host "==> Built $Out\NVEncC64.exe with route $Route. Run scripts/windows/package.sh to bundle it."
