[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$VideoPath,
    [string]$FfmpegPath = 'ffmpeg',
    [Parameter(Mandatory)]
    [ValidateSet('FuelMarker', 'PickupKey', 'Health', 'Motion')]
    [string]$Mode,
    [Parameter(Mandatory)]
    [ValidatePattern('^[1-9]\d*:[1-9]\d*:\d+:\d+$')]
    [string]$Crop,
    [Parameter(Mandatory)]
    [ValidateScript({ $_ -ge 0 })]
    [double[]]$AtSeconds,
    [ValidatePattern('^[1-9]\d*:[1-9]\d*$')]
    [string]$Resize
)

$ErrorActionPreference = 'Stop'
$video = (Resolve-Path -LiteralPath $VideoPath).ProviderPath
$ffmpeg = (Get-Command -Name $FfmpegPath -CommandType Application | Select-Object -First 1).Source
. (Join-Path $PSScriptRoot 'roblox-route-prototype.ps1') -SelfTest | Out-Null

$filter = "crop=$Crop"
if ($Resize) {
    $width, $height = $Crop.Split(':')[0..1]
    $filter += ",scale=$Resize,scale=${width}:$height"
}
$framePath = [IO.Path]::ChangeExtension([IO.Path]::Combine([IO.Path]::GetTempPath(), [Guid]::NewGuid().ToString('N')), 'png')
$previousMotion = $null
try {
    foreach ($time in $AtSeconds) {
        $timestamp = $time.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
        & $ffmpeg -nostdin -v error -ss $timestamp -i $video -an -vf $filter -frames:v 1 -y $framePath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $framePath)) {
            throw "Could not extract a frame at $timestamp seconds."
        }
        try {
            $frame = [Drawing.Bitmap]::new($framePath)
            try {
                switch ($Mode) {
                    'FuelMarker' {
                        $score, $x, $y = [RobloxRouteNative]::FindFuelMarker($frame)
                        [pscustomobject]@{ Seconds = $time; Detected = $score -eq 0; X = $x; Y = $y }
                    }
                    'PickupKey' {
                        [pscustomobject]@{ Seconds = $time; Detected = [RobloxRouteNative]::HasPickupKey($frame) }
                    }
                    'Health' {
                        [pscustomobject]@{ Seconds = $time; FillPercent = [RobloxRouteNative]::HealthFill($frame) }
                    }
                    'Motion' {
                        $currentMotion = [RobloxRouteNative]::MotionSample($frame)
                        $difference = $null
                        if ($null -ne $previousMotion) {
                            $difference = [RobloxRouteNative]::MotionDifference($previousMotion, $currentMotion)
                        }
                        [pscustomobject]@{ Seconds = $time; Difference = $difference }
                        $previousMotion = $currentMotion
                    }
                }
            } finally { $frame.Dispose() }
        } finally { Remove-Item -LiteralPath $framePath -Force }
    }
} finally {
    if (Test-Path -LiteralPath $framePath) { Remove-Item -LiteralPath $framePath -Force }
}
