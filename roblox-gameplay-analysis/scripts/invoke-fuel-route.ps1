[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProfilePath,
    [switch]$DryRun,
    [switch]$TraceReturn
)

$ErrorActionPreference = 'Stop'
$profileData = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$prototype = Join-Path $PSScriptRoot 'roblox-route-prototype.ps1'
$region = $profileData.regions
foreach ($name in @('fuelMarker', 'pickupKey', 'bagTrail', 'generator', 'returnTrail')) {
    $bounds = $region.$name
    if ($null -eq $bounds -or $bounds.width -le 0 -or $bounds.height -le 0) {
        throw "The calibration profile needs a nonempty regions.$name."
    }
}
if ($profileData.referenceWidth -le 0 -or $profileData.referenceHeight -le 0 -or $null -eq $profileData.returnTurnX) {
    throw 'Set referenceWidth, referenceHeight, and returnTurnX in the calibration profile.'
}
foreach ($name in @('fuelTargetX', 'fuelArrivalY', 'fuelTolerance', 'generatorTargetX', 'generatorTargetY',
    'generatorTolerance', 'generatorMinimumWidth', 'trailOriginX', 'trailOriginY')) {
    if ($null -eq $profileData.$name) { throw "The calibration profile needs $name." }
}

$route = @(
    if ($profileData.departure) {
        @{
            name = 'Clear generator'
            action = 'clearGenerator'
            keys = $profileData.departure.keys
            durationMs = $profileData.departure.durationMs
        }
    }
    @{
        name = 'Approach fuel'
        action = 'followFuelMarker'
        region = $region.fuelMarker
        keys = @('w', 'shift')
        targetX = $profileData.fuelTargetX
        targetY = $profileData.fuelArrivalY
        tolerance = $profileData.fuelTolerance
        recoveryRegion = $region.recovery
        healthRegion = $region.health
        maxError = 0
        timeoutMs = 12000
    }
    @{ name = 'Aim at fuel'; action = 'aimFuel'; maxError = 0; timeoutMs = 1500 }
    @{
        name = 'Confirm pickup prompt'
        action = 'confirmFuelPrompt'
        pickupKeyRegion = $region.pickupKey
        maxError = 0
        timeoutMs = 3500
    }
    @{ name = 'Confirm bag'; action = 'confirmBag'; region = $region.bagTrail; maxError = 0; timeoutMs = 2000 }
    if ($profileData.retraceOutbound) {
        @{ name = 'Retrace outbound motion'; action = 'returnPath'; recoveryRegion = $region.recovery }
    }
    @{
        name = 'Follow return arrows'
        action = 'followReturnTrail'
        region = $region.generator
        targetX = $profileData.generatorTargetX
        targetY = $profileData.generatorTargetY
        tolerance = $profileData.generatorTolerance
        minimumWidth = $profileData.generatorMinimumWidth
        trailRegion = $region.returnTrail
        trailOriginX = $profileData.trailOriginX
        trailOriginY = $profileData.trailOriginY
        alignForDelivery = $true
        recoveryRegion = $region.recovery
        healthRegion = $region.health
        maxError = 0
        timeoutMs = 12000
    }
    foreach ($delivery in @(@('deliverFuel', 2000), @('confirmDelivery', 3000))) {
        @{
            name = $delivery[0]
            action = $delivery[0]
            region = $region.generator
            targetX = $profileData.generatorTargetX
            targetY = $profileData.generatorTargetY
            tolerance = $profileData.generatorTolerance
            minimumWidth = $profileData.generatorMinimumWidth
            maxError = 0
            timeoutMs = $delivery[1]
        }
    }
)

$routeJson = ConvertTo-Json -InputObject $route -Depth 6 -Compress
& $prototype -RouteJson $routeJson -ReferenceWidth $profileData.referenceWidth `
    -ReferenceHeight $profileData.referenceHeight -ReturnTurnX $profileData.returnTurnX `
    -DryRun:$DryRun -TraceReturn:$TraceReturn
