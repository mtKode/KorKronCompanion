<#
  Puts the KorKronCompanion addon into your WoW client's Interface\AddOns folder.

  .\install-addon.ps1                 # link (junction): edits in the repo show up after /reload in game
  .\install-addon.ps1 -Copy           # plain copy instead (for guildies / a zip)
  .\install-addon.ps1 -Client _forever_ -WowPath "D:\Games\World of Warcraft"
#>
param(
    [string]$WowPath,
    [string]$Client = '_forever_',
    [switch]$Copy
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'addon\KorKronCompanion'

$roots = @($WowPath, 'C:\Program Files (x86)\World of Warcraft', 'C:\Program Files\World of Warcraft',
           'C:\Games\World of Warcraft', 'D:\World of Warcraft', 'D:\Games\World of Warcraft') |
         Where-Object { $_ -and (Test-Path $_) }
if (-not $roots) { throw "World of Warcraft not found. Pass -WowPath 'X:\path\to\World of Warcraft'." }
$clientDir = Join-Path $roots[0] $Client
if (-not (Test-Path $clientDir)) { throw "No $Client folder in $($roots[0]). Pass -Client _retail_ (or similar)." }

$addons = Join-Path $clientDir 'Interface\AddOns'
New-Item -ItemType Directory -Force $addons | Out-Null
$target = Join-Path $addons 'KorKronCompanion'
if (Test-Path $target) { Remove-Item $target -Recurse -Force }

if ($Copy) {
    Copy-Item $source $target -Recurse
    Write-Host "Copied KorKronCompanion to $target" -ForegroundColor Green
} else {
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Host "Linked $target -> $source (edit in the repo, /reload in game)" -ForegroundColor Green
}
Write-Host "In game: AddOns list at the character screen, tick 'Load out of date AddOns' if it shows as out of date."
