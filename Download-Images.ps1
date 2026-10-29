<#
.SYNOPSIS
    Download images from direct image URLs or from all <img> tags on web pages.

.EXAMPLE
    .\Download-Images.ps1 -Url https://example.com/photo.jpg
    .\Download-Images.ps1 -Url https://example.com/gallery -OutDir .\pics
    .\Download-Images.ps1 -ListFile urls.txt -OutDir .\pics -MinBytes 5000
#>
[CmdletBinding()]
param(
    [string[]]$Url,
    [string]$ListFile,
    [string]$OutDir = (Join-Path $PWD 'images'),
    [int]$MinBytes = 0,
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ImageDownloader/1.0'
$Blocked = @('sellercentral.amazon.com')
$ExtByType = @{
    'image/jpeg' = '.jpg'; 'image/png' = '.png'; 'image/gif' = '.gif'
    'image/webp' = '.webp'; 'image/svg+xml' = '.svg'; 'image/bmp' = '.bmp'
    'image/avif' = '.avif'; 'image/x-icon' = '.ico'
}

function Test-Blocked([string]$u) {
    $h = ([uri]$u).Host.ToLower()
    foreach ($b in $Blocked) { if ($h -eq $b -or $h.EndsWith(".$b")) { return $true } }
    return $false
}

function Get-PageImages([string]$html, [uri]$base) {
    $found = [System.Collections.Generic.List[string]]::new()
    $patterns = @(
        '<img\b[^>]*?\bsrc\s*=\s*["'']([^"'']+)["'']',
        '<img\b[^>]*?\bdata-src\s*=\s*["'']([^"'']+)["'']',
        '<meta\b[^>]*?property\s*=\s*["'']og:image["''][^>]*?content\s*=\s*["'']([^"'']+)["'']'
    )
    foreach ($p in $patterns) {
        foreach ($m in [regex]::Matches($html, $p, 'IgnoreCase')) { $found.Add($m.Groups[1].Value) }
    }
    # srcset: take the last (usually largest) candidate
    foreach ($m in [regex]::Matches($html, '\bsrcset\s*=\s*["'']([^"'']+)["'']', 'IgnoreCase')) {
        $last = ($m.Groups[1].Value -split ',')[-1].Trim() -split '\s+' | Select-Object -First 1
        if ($last) { $found.Add($last) }
    }
    foreach ($raw in $found) {
        if ($raw -like 'data:*') { continue }
        $abs = $null
        if ([uri]::TryCreate($base, [System.Net.WebUtility]::HtmlDecode($raw), [ref]$abs)) { $abs.AbsoluteUri }
    }
}

function Get-SafeName([uri]$u, [string]$contentType) {
    $name = [IO.Path]::GetFileName($u.AbsolutePath)
    if (-not $name) { $name = 'image' }
    $name = ($name -replace '[^\w\.\-]', '_')
    $ext = $ExtByType[($contentType -split ';')[0].Trim().ToLower()]
    if ($ext -and -not [IO.Path]::HasExtension($name)) { $name += $ext }
    $path = Join-Path $OutDir $name
    $i = 1
    while (Test-Path $path) {
        $path = Join-Path $OutDir ("{0}_{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($name), $i++, [IO.Path]::GetExtension($name))
    }
    $path
}

function Save-Image([string]$imageUrl) {
    $resp = Invoke-WebRequest -Uri $imageUrl -UseBasicParsing -UserAgent $UserAgent -TimeoutSec $TimeoutSec
    $type = [string]$resp.Headers['Content-Type']
    if ($type -notlike 'image/*') { Write-Warning "Skipped (not an image: $type): $imageUrl"; return $false }
    $bytes = $resp.Content
    if ($bytes.Length -lt $MinBytes) { Write-Warning "Skipped (under $MinBytes bytes): $imageUrl"; return $false }
    $path = Get-SafeName ([uri]$imageUrl) $type
    [IO.File]::WriteAllBytes($path, $bytes)
    Write-Host "Saved $path ($($bytes.Length) bytes)"
    return $true
}

$inputs = @($Url)
if ($ListFile) { $inputs += Get-Content $ListFile | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } }
if (-not $inputs) { throw 'Provide -Url and/or -ListFile.' }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$saved = 0; $failed = 0

foreach ($target in $inputs) {
    try {
        if (Test-Blocked $target) { Write-Warning "Blocked by policy: $target"; $failed++; continue }
        $resp = Invoke-WebRequest -Uri $target -UseBasicParsing -UserAgent $UserAgent -TimeoutSec $TimeoutSec
        $type = [string]$resp.Headers['Content-Type']
        if ($type -like 'image/*') {
            if (Save-Image $target) { $saved++ }
        }
        else {
            $images = Get-PageImages $resp.Content ([uri]$target) | Select-Object -Unique
            Write-Host "$target -> $(@($images).Count) image(s) found"
            foreach ($img in $images) {
                try {
                    if (Test-Blocked $img) { continue }
                    if (Save-Image $img) { $saved++ }
                }
                catch { Write-Warning "Failed $img : $($_.Exception.Message)"; $failed++ }
            }
        }
    }
    catch { Write-Warning "Failed $target : $($_.Exception.Message)"; $failed++ }
}

Write-Host "Done. Saved: $saved, failed/skipped: $failed. Output: $OutDir"
