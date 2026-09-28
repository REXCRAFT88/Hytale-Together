function Get-LayoutNames([int]$Count){
    switch($Count){
        1 { @('Full') }
        2 { @('Stacked','SideBySide') }
        3 { @('LargeLeft','LargeRight','LargeTop','LargeBottom','Stacked','SideBySide') }
        4 { @('Grid','Stacked','SideBySide') }
        default { @('Full') }
    }
}
function Get-NormalizedLayout([int]$Count,[string]$Name,[double]$Ratio=0.5){
    if($Count -lt 1 -or $Count -gt 4){throw 'Select 1 to 4 players.'}
    if($Name -notin @(Get-LayoutNames $Count)){throw 'Layout does not match the selected player count.'}
    if([double]::IsNaN($Ratio) -or $Ratio -lt 0.3 -or $Ratio -gt 0.7){throw 'Split must be between 30% and 70%.'}
    $cells=@()
    switch($Name){
        Full {$cells=,@(0,0,1,1)}
        Grid {$cells=@(@(0,0,$Ratio,0.5),@($Ratio,0,(1-$Ratio),0.5),@(0,0.5,$Ratio,0.5),@($Ratio,0.5,(1-$Ratio),0.5))}
        LargeLeft {$cells=@(@(0,0,$Ratio,1),@($Ratio,0,(1-$Ratio),0.5),@($Ratio,0.5,(1-$Ratio),0.5))}
        LargeRight {$cells=@(@((1-$Ratio),0,$Ratio,1),@(0,0,(1-$Ratio),0.5),@(0,0.5,(1-$Ratio),0.5))}
        LargeTop {$cells=@(@(0,0,1,$Ratio),@(0,$Ratio,0.5,(1-$Ratio)),@(0.5,$Ratio,0.5,(1-$Ratio)))}
        LargeBottom {$cells=@(@(0,(1-$Ratio),1,$Ratio),@(0,0,0.5,(1-$Ratio)),@(0.5,0,0.5,(1-$Ratio)))}
        default {
            for($i=0;$i -lt $Count;$i++){
                $start=$i/$Count;$size=1.0/$Count
                if($Count -eq 2){$start=if($i -eq 0){0}else{$Ratio};$size=if($i -eq 0){$Ratio}else{1-$Ratio}}
                if($Name -eq 'Stacked'){$cells+=,@(0,$start,1,$size)}else{$cells+=,@($start,0,$size,1)}
            }
        }
    }
    foreach($c in $cells){[pscustomobject]@{X=[double]$c[0];Y=[double]$c[1];Width=[double]$c[2];Height=[double]$c[3]}}
}
function Convert-LayoutCell($Cell,$Bounds,$Fit16x9=$false){
    $fit = if($Fit16x9 -is [bool]){ $Fit16x9 } elseif($Fit16x9 -is [string]){ $Fit16x9 -notin @('False','false','0','','System.String') } else { [bool]$Fit16x9 }
    $left=[math]::Round($Cell.X*$Bounds.Width);$top=[math]::Round($Cell.Y*$Bounds.Height)
    $w=[math]::Round(($Cell.X+$Cell.Width)*$Bounds.Width)-$left
    $h=[math]::Round(($Cell.Y+$Cell.Height)*$Bounds.Height)-$top
    if($fit){$scale=[math]::Min($w/16,$h/9);$fw=[math]::Floor(16*$scale);$fh=[math]::Floor(9*$scale);$left+=[math]::Floor(($w-$fw)/2);$top+=[math]::Floor(($h-$fh)/2);$w=$fw;$h=$fh}
    [pscustomobject]@{X=[int]($Bounds.X+$left);Y=[int]($Bounds.Y+$top);Width=[int]$w;Height=[int]$h}
}
function Resolve-LayoutOrder($Ids,$SavedOrder){
    $order=@();foreach($id in @($SavedOrder)+@($Ids)){if($id -in $Ids -and $id -notin $order){$order+=,[string]$id}};$order
}

