Set-StrictMode -Version Latest

function Get-ArchimedesAnsiTheme {
    $esc=[char]27
    [pscustomobject]@{
        Reset="$esc[0m"
        Header="$esc[44m$esc[97m"
        Navbar="$esc[44m$esc[97m"
        Footer="$esc[44m$esc[97m"
        Active="$esc[46;30m"
        ClearLine="$esc[2K"
    }
}

function New-ArchimedesMenuState {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][string]$IdProperty,
        [int]$PageSize=12,
        [switch]$MultiSelect
    )
    $indices=if($Items.Count){@(0..($Items.Count-1))}else{@()}
    [pscustomobject]@{
        Items=@($Items); IdProperty=$IdProperty; Columns=2
        PageSize=[Math]::Max(1,$PageSize); MultiSelect=[bool]$MultiSelect
        Filter=''; FilteredIndices=$indices
        CurrentRow=0; CurrentColumn=0; TopRow=0; Cursor=0; Top=0
        Selected=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    }
}
function Sync-ArchimedesMenuPosition {
    param([Parameter(Mandatory)]$State)
    $State.Cursor=($State.CurrentRow*$State.Columns)+$State.CurrentColumn
    $State.Top=$State.TopRow*$State.Columns
}

function Test-ArchimedesMenuCellExists {
    param([Parameter(Mandatory)]$State,[int]$Row,[int]$Column)
    if($Row -lt 0 -or $Column -lt 0 -or $Column -ge $State.Columns){return $false}
    return ((($Row*$State.Columns)+$Column) -lt $State.FilteredIndices.Count)
}

function Set-ArchimedesMenuViewport {
    param([Parameter(Mandatory)]$State)
    $count=$State.FilteredIndices.Count
    if(-not $count){$State.CurrentRow=0;$State.CurrentColumn=0;$State.TopRow=0;Sync-ArchimedesMenuPosition $State;return}
    $rows=[int][Math]::Ceiling($count/[double]$State.Columns)
    $State.CurrentRow=[Math]::Max(0,[Math]::Min($State.CurrentRow,$rows-1))
    $State.CurrentColumn=[Math]::Max(0,[Math]::Min($State.CurrentColumn,$State.Columns-1))
    if(-not (Test-ArchimedesMenuCellExists $State $State.CurrentRow $State.CurrentColumn)){$State.CurrentColumn=0}
    $maxTop=[Math]::Max(0,$rows-$State.PageSize)
    $State.TopRow=[Math]::Max(0,[Math]::Min($State.TopRow,$maxTop))
    if($State.CurrentRow -lt $State.TopRow){$State.TopRow=$State.CurrentRow}
    if($State.CurrentRow -ge ($State.TopRow+$State.PageSize)){$State.TopRow=[Math]::Min($maxTop,$State.CurrentRow-$State.PageSize+1)}
    Sync-ArchimedesMenuPosition $State
}
function Set-ArchimedesMenuFilter {
    param([Parameter(Mandatory)]$State,[string]$Filter)
    $State.Filter=[string]$Filter
    $matches=New-Object System.Collections.Generic.List[int]
    for($i=0;$i -lt $State.Items.Count;$i++){
        $text=(($State.Items[$i].PSObject.Properties|ForEach-Object{[string]$_.Value}) -join ' ')
        if([string]::IsNullOrWhiteSpace($State.Filter) -or $text.IndexOf($State.Filter,[StringComparison]::OrdinalIgnoreCase) -ge 0){$matches.Add($i)}
    }
    $State.FilteredIndices=@($matches)
    $State.CurrentRow=0;$State.CurrentColumn=0;$State.TopRow=0
    Set-ArchimedesMenuViewport $State
}

function Move-ArchimedesMenuCursor {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][ValidateSet('Up','Down','Left','Right','PageUp','PageDown','Home','End')][string]$Action
    )
    if(-not $State.FilteredIndices.Count){return}
    $rows=[int][Math]::Ceiling($State.FilteredIndices.Count/[double]$State.Columns)
    switch($Action){
        'Up' {if($State.CurrentRow -gt 0){$State.CurrentRow--}}
        'Down' {if($State.CurrentRow -lt ($rows-1)){$State.CurrentRow++;if(-not(Test-ArchimedesMenuCellExists $State $State.CurrentRow $State.CurrentColumn)){$State.CurrentColumn=0}}}
        'Left' {if($State.CurrentColumn -gt 0){$State.CurrentColumn--}}
        'Right' {if(Test-ArchimedesMenuCellExists $State $State.CurrentRow 1){$State.CurrentColumn=1}}
        'PageUp' {$State.CurrentRow=[Math]::Max(0,$State.CurrentRow-$State.PageSize)}
        'PageDown' {$State.CurrentRow=[Math]::Min($rows-1,$State.CurrentRow+$State.PageSize);if(-not(Test-ArchimedesMenuCellExists $State $State.CurrentRow $State.CurrentColumn)){$State.CurrentColumn=0}}
        'Home' {$State.CurrentRow=0;$State.CurrentColumn=0;$State.TopRow=0}
        'End' {$last=$State.FilteredIndices.Count-1;$State.CurrentRow=[Math]::Floor($last/$State.Columns);$State.CurrentColumn=$last%$State.Columns}
    }
    Set-ArchimedesMenuViewport $State
}
function Get-ArchimedesCurrentMenuItem {
    param([Parameter(Mandatory)]$State)
    if(-not $State.FilteredIndices.Count){return $null}
    $flat=($State.CurrentRow*$State.Columns)+$State.CurrentColumn
    if($flat -ge $State.FilteredIndices.Count){return $null}
    return $State.Items[$State.FilteredIndices[$flat]]
}

function Toggle-ArchimedesMenuSelection {
    param([Parameter(Mandatory)]$State)
    $item=Get-ArchimedesCurrentMenuItem $State
    if(-not $item){return}
    $id=[string]$item.($State.IdProperty)
    if($State.Selected.Contains($id)){[void]$State.Selected.Remove($id)}else{[void]$State.Selected.Add($id)}
}

function Select-AllArchimedesMenuItems {
    param([Parameter(Mandatory)]$State)
    foreach($index in $State.FilteredIndices){[void]$State.Selected.Add([string]$State.Items[$index].($State.IdProperty))}
}

function Clear-ArchimedesMenuSelection {
    param([Parameter(Mandatory)]$State)
    $State.Selected.Clear()
}

function Get-ArchimedesSelectedMenuItems {
    param([Parameter(Mandatory)]$State)
    if($State.MultiSelect){return @($State.Items|Where-Object{$State.Selected.Contains([string]$_.($State.IdProperty))})}
    $current=Get-ArchimedesCurrentMenuItem $State
    if($current){return @($current)}
    return @()
}
function Test-ArchimedesRawConsoleAvailable {
    try {
        if([Console]::IsInputRedirected -or [Console]::IsOutputRedirected){return $false}
        $null=[Console]::CursorLeft;$null=[Console]::CursorTop;$null=[Console]::WindowWidth
        return $true
    } catch {return $false}
}

function Format-ArchimedesMenuLine {
    param($State,$Item,[scriptblock]$DisplayScript)
    $id=[string]$Item.($State.IdProperty)
    $mark=if($State.MultiSelect){if($State.Selected.Contains($id)){'[x]'}else{'[ ]'}}else{'   '}
    return "$mark $(& $DisplayScript $Item)"
}

function Get-ArchimedesRawCellText {
    param($State,[int]$FlatPosition,[scriptblock]$DisplayScript)
    if($FlatPosition -lt 0 -or $FlatPosition -ge $State.FilteredIndices.Count){return ''}
    $item=$State.Items[$State.FilteredIndices[$FlatPosition]]
    return (Format-ArchimedesMenuLine $State $item $DisplayScript)
}

function Write-ArchimedesAnsiCell {
    param([int]$Row,[int]$Column,[int]$Width,[string]$Text,[string]$Style,[string]$Reset)
    $esc=[char]27;$w=[Math]::Max(1,$Width)
    if($Text.Length -gt $w){$Text=$Text.Substring(0,$w)}
    $padded=$Text.PadRight($w)
    Write-Host -NoNewline "$esc[$($Row+1);$($Column+1)H$Style$padded$Reset"
}

function Write-ArchimedesAnsiBar {
    param([int]$Row,[int]$Width,[string]$Text,[string]$Style,[string]$Reset)
    Write-ArchimedesAnsiCell -Row $Row -Column 0 -Width $Width -Text $Text -Style $Style -Reset $Reset
}
function Write-ArchimedesRawCellAtPosition {
    param($State,[int]$FlatPosition,[int]$StartTop,[int]$WindowWidth,[scriptblock]$DisplayScript)
    $row=[Math]::Floor($FlatPosition/$State.Columns)
    if($row -lt $State.TopRow -or $row -ge ($State.TopRow+$State.PageSize)){return}
    $column=$FlatPosition%$State.Columns
    $displayRow=$row-$State.TopRow
    $colWidth=[Math]::Floor($WindowWidth/$State.Columns)
    $text=Get-ArchimedesRawCellText $State $FlatPosition $DisplayScript
    $active=($row -eq $State.CurrentRow -and $column -eq $State.CurrentColumn)
    $theme=Get-ArchimedesAnsiTheme
    $style=if($active){$theme.Active}else{$theme.Reset}
    Write-ArchimedesAnsiCell -Row ($StartTop+2+$displayRow) -Column ($column*$colWidth) -Width $colWidth -Text $text -Style $style -Reset $theme.Reset
}

function Write-ArchimedesRawMenuFull {
    param($State,[string]$Title,[int]$StartTop,[int]$WindowWidth,[scriptblock]$DisplayScript)
    $theme=Get-ArchimedesAnsiTheme
    $rows=[int][Math]::Ceiling($State.FilteredIndices.Count/[double]$State.Columns)
    $pages=[Math]::Max(1,[int][Math]::Ceiling($rows/[double]$State.PageSize))
    $page=[Math]::Min($pages,[Math]::Floor($State.TopRow/[double]$State.PageSize)+1)
    Write-ArchimedesAnsiBar -Row $StartTop -Width $WindowWidth -Text " ARCHIMEDES  |  $Title" -Style $theme.Header -Reset $theme.Reset
    $nav=" Filter: $($State.Filter)  |  Page $page/$pages  |  Selected: $($State.Selected.Count)"
    Write-ArchimedesAnsiBar -Row ($StartTop+1) -Width $WindowWidth -Text $nav -Style $theme.Navbar -Reset $theme.Reset
    for($r=0;$r -lt $State.PageSize;$r++){
        for($c=0;$c -lt $State.Columns;$c++){
            $flat=(($State.TopRow+$r)*$State.Columns)+$c
            Write-ArchimedesRawCellAtPosition $State $flat $StartTop $WindowWidth $DisplayScript
        }
    }
    $help=(' {0} {1} {2} {3}  SPACE select  ENTER accept  ESC back  A all  N none  HOME/END  PgUp/PgDn  / filter' -f ([char]0x2191),([char]0x2193),([char]0x2190),([char]0x2192))
    Write-ArchimedesAnsiBar -Row ($StartTop+2+$State.PageSize) -Width $WindowWidth -Text $help -Style $theme.Footer -Reset $theme.Reset
}
function Read-ArchimedesRawFilter {
    param($State,[int]$PromptRow)
    $theme=Get-ArchimedesAnsiTheme
    try{[Console]::CursorVisible=$true}catch{}
    try{
        $esc=[char]27
        Write-Host -NoNewline "$esc[$($PromptRow+1);1H$($theme.Reset)$($theme.ClearLine)"
        $value=Read-Host 'Filter'
        Set-ArchimedesMenuFilter $State $value
    } finally {
        try{[Console]::CursorVisible=$false}catch{}
    }
}

function Invoke-ArchimedesFallbackMenu {
    param($State,[string]$Title,[scriptblock]$DisplayScript)
    while($true){
        Write-Host ''
        Write-Host $Title
        $rows=[int][Math]::Ceiling($State.FilteredIndices.Count/[double]$State.Columns)
        $pages=[Math]::Max(1,[int][Math]::Ceiling($rows/[double]$State.PageSize))
        $page=[Math]::Floor($State.TopRow/[double]$State.PageSize)+1
        Write-Host "Page $page/$pages  Filter: $($State.Filter)"
        $start=$State.TopRow*$State.Columns
        $end=[Math]::Min($start+($State.PageSize*$State.Columns),$State.FilteredIndices.Count)
        for($flat=$start;$flat -lt $end;$flat++){
            $item=$State.Items[$State.FilteredIndices[$flat]]
            Write-Host ("[{0}] {1}" -f ($flat+1),(Format-ArchimedesMenuLine $State $item $DisplayScript))
        }
        Write-Host '[>] Next  [<] Previous  [/] Filter  [Q] Back'
        if($State.MultiSelect){Write-Host '[A] Select filtered  [N] Clear selection  [ENTER] Accept selected'}
        $choice=Read-Host 'Select'
        if([string]::IsNullOrWhiteSpace($choice) -and $State.MultiSelect -and $State.Selected.Count){return @(Get-ArchimedesSelectedMenuItems $State)}
        switch -Regex($choice){
            '^>$' {Move-ArchimedesMenuCursor $State PageDown;continue}
            '^<$' {Move-ArchimedesMenuCursor $State PageUp;continue}
            '^/$' {Set-ArchimedesMenuFilter $State (Read-Host 'Filter');continue}
            '^[qQ]$' {return @()}
            '^[aA]$' {if($State.MultiSelect){Select-AllArchimedesMenuItems $State};continue}
            '^[nN]$' {if($State.MultiSelect){Clear-ArchimedesMenuSelection $State};continue}
            '^\d+$' {$flat=[int]$choice-1;if($flat -ge 0 -and $flat -lt $State.FilteredIndices.Count){$State.CurrentRow=[Math]::Floor($flat/$State.Columns);$State.CurrentColumn=$flat%$State.Columns;Set-ArchimedesMenuViewport $State;if($State.MultiSelect){Toggle-ArchimedesMenuSelection $State;continue};return @(Get-ArchimedesSelectedMenuItems $State)}}
        }
    }
}
function Invoke-ArchimedesRawMenu {
    param($State,[string]$Title,[scriptblock]$DisplayScript)
    $originalVisible=$true
    try{$originalVisible=[Console]::CursorVisible}catch{}
    $startTop=[Console]::CursorTop
    $lastWidth=0
    try{
        try{[Console]::CursorVisible=$false}catch{}
        while($true){
            $width=[Math]::Max(20,[Console]::WindowWidth-1)
            if($lastWidth -ne $width){Write-ArchimedesRawMenuFull $State $Title $startTop $width $DisplayScript;$lastWidth=$width}
            $oldFlat=($State.CurrentRow*$State.Columns)+$State.CurrentColumn
            $oldTop=$State.TopRow
            $key=[Console]::ReadKey($true)
            $full=$false;$refreshCurrent=$false
            switch($key.Key){
                'UpArrow' {Move-ArchimedesMenuCursor $State Up}
                'DownArrow' {Move-ArchimedesMenuCursor $State Down}
                'LeftArrow' {Move-ArchimedesMenuCursor $State Left}
                'RightArrow' {Move-ArchimedesMenuCursor $State Right}
                'PageUp' {Move-ArchimedesMenuCursor $State PageUp;$full=$true}
                'PageDown' {Move-ArchimedesMenuCursor $State PageDown;$full=$true}
                'Home' {Move-ArchimedesMenuCursor $State Home;$full=$true}
                'End' {Move-ArchimedesMenuCursor $State End;$full=$true}
                'Spacebar' {if($State.MultiSelect){Toggle-ArchimedesMenuSelection $State;$refreshCurrent=$true}}
                'A' {if($State.MultiSelect){Select-AllArchimedesMenuItems $State;$full=$true}}
                'N' {if($State.MultiSelect){Clear-ArchimedesMenuSelection $State;$full=$true}}
                'Enter' {if($State.MultiSelect -and -not $State.Selected.Count){continue};return @(Get-ArchimedesSelectedMenuItems $State)}
                'Escape' {return @()}
            }
            if($key.KeyChar -eq '/') {Read-ArchimedesRawFilter $State ($startTop+3+$State.PageSize);$full=$true}
            $newWidth=[Math]::Max(20,[Console]::WindowWidth-1)
            if($newWidth -ne $lastWidth){$lastWidth=$newWidth;$full=$true}
            if($State.TopRow -ne $oldTop){$full=$true}
            if($full){Write-ArchimedesRawMenuFull $State $Title $startTop $lastWidth $DisplayScript;continue}
            $newFlat=($State.CurrentRow*$State.Columns)+$State.CurrentColumn
            if($newFlat -ne $oldFlat){Write-ArchimedesRawCellAtPosition $State $oldFlat $startTop $lastWidth $DisplayScript;Write-ArchimedesRawCellAtPosition $State $newFlat $startTop $lastWidth $DisplayScript}
            elseif($refreshCurrent){Write-ArchimedesRawCellAtPosition $State $newFlat $startTop $lastWidth $DisplayScript}
        }
    } finally {
        $theme=Get-ArchimedesAnsiTheme
        Write-Host -NoNewline $theme.Reset
        try{[Console]::CursorVisible=$originalVisible}catch{}
        try{[Console]::SetCursorPosition(0,[Math]::Min([Console]::BufferHeight-1,$startTop+3+$State.PageSize))}catch{}
        Write-Host ''
    }
}
function Invoke-ArchimedesSelectionMenu {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][string]$IdProperty,
        [Parameter(Mandatory)][scriptblock]$DisplayScript,
        [switch]$MultiSelect,
        [int]$PageSize=12
    )
    $state=New-ArchimedesMenuState -Items $Items -IdProperty $IdProperty -PageSize $PageSize -MultiSelect:$MultiSelect
    if(Test-ArchimedesRawConsoleAvailable){return @(Invoke-ArchimedesRawMenu $state $Title $DisplayScript)}
    return @(Invoke-ArchimedesFallbackMenu $state $Title $DisplayScript)
}
