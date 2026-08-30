$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$consolePath=Join-Path $root 'lib/Archimedes.Console.ps1'
. $consolePath
$items=1..7|%{[pscustomobject]@{Id="i$_";Name="Item $_"}}
$s=New-ArchimedesMenuState -Items $items -IdProperty Id -PageSize 2 -MultiSelect
if($s.CurrentRow -ne 0 -or $s.CurrentColumn -ne 0){throw 'Initial row/column invalid'}
Move-ArchimedesMenuCursor $s Right
if($s.CurrentRow -ne 0 -or $s.CurrentColumn -ne 1){throw 'Right navigation failed'}
Move-ArchimedesMenuCursor $s Down
if($s.CurrentRow -ne 1 -or $s.CurrentColumn -ne 1){throw 'Down navigation failed'}
Move-ArchimedesMenuCursor $s PageDown
if($s.CurrentRow -ne 3 -or $s.CurrentColumn -ne 0){throw 'PageDown must avoid empty second-column cell'}
Move-ArchimedesMenuCursor $s Right
if($s.CurrentColumn -ne 0){throw 'Cursor moved onto empty cell'}
Move-ArchimedesMenuCursor $s Home
Toggle-ArchimedesMenuSelection $s
if(-not $s.Selected.Contains('i1')){throw 'Selection failed'}
Set-ArchimedesMenuFilter $s 'Item 2'
if($s.FilteredIndices.Count -ne 1){throw 'Filter failed'}
$theme=Get-ArchimedesAnsiTheme
if($theme.Header -notmatch '\[44m' -or $theme.Active -notmatch '\[46;30m'){throw 'ANSI theme mismatch'}
if((Get-Content $consolePath -Raw) -match 'Clear-Host'){throw 'Clear-Host is forbidden in menu navigation'}
Write-Host 'PASS console menu state'