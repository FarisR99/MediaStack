<#
.SYNOPSIS
  Put the MediaStack portable build first on PATH, for this PowerShell session only.

.DESCRIPTION
  Prepends out\ucrt64\dist (made by scripts/windows/package.sh) to $env:Path, so
  mpv, ffmpeg, ffprobe and NVEncC64 from the stack win over any other copies.
  Nothing is written to the registry: closing the window undoes it.

.EXAMPLE
  D:\Documents\Programs\MediaStack\scripts\windows\activate.ps1
#>
$dist = Join-Path (Resolve-Path "$PSScriptRoot\..\..").Path 'out\ucrt64\dist'
if (-not (Test-Path "$dist\ffmpeg.exe")) {
    Write-Error "$dist has no ffmpeg.exe: run scripts/windows/package.sh in the UCRT64 shell first"
    return
}
# Environment variables are per process, so this reaches the calling session
# without dot-sourcing. Drop an existing entry first so reruns don't pile up.
$env:Path = (@($dist) + ($env:Path -split ';' | Where-Object { $_ -and $_ -ne $dist })) -join ';'
Write-Host "MediaStack first on PATH for this session: $dist"
Get-Command mpv, ffmpeg | Format-Table -AutoSize Name, Source
