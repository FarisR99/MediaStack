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
    libplacebo and libdovi DLLs come from UCRT64/the prefix. The same DLLs as
    mpv, and FFmpeg is built only once.
  Route B: build a second, minimal FFmpeg with --toolchain=msvc
    (scripts/windows/build-ffmpeg-msvc.sh) into out\msvc\prefix, and use that.
    Use it if Route A won't link or crashes at runtime.

  Run from a "Developer PowerShell for VS 2022" so cl.exe, lib.exe, dumpbin
  and msbuild are on PATH. Record the route that works in
  docs/building-windows.md and docs/agents/build-windows.md.

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
foreach ($sdk in 'AVISYNTH_SDK', 'VAPOURSYNTH_SDK') {
    if (-not (Test-Path "env:$sdk")) { Write-Warning "$sdk is not set; NVEnc's project expects its headers (see docs/building-windows.md)" }
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
foreach ($dir in 'ass', 'libdovi') {
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
# NVEnc links dovi.lib (#pragma comment); point it at UCRT64's libdovi DLL.
$dovi = Get-ChildItem "$Ucrt\bin\*dovi*.dll" | Select-Object -First 1
if ($dovi) {
    New-ImportLib $dovi.FullName (Join-Path $StageLib 'dovi.lib')
    Copy-Item $dovi.FullName $StageLib
} else { Write-Warning 'libdovi DLL not found in UCRT64 (pacman -S mingw-w64-ucrt-x86_64-libdovi)' }

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
