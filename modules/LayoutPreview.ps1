$script:layoutName=if($settings -and $settings.LayoutName){$settings.LayoutName}elseif($settings -and $settings.Layout -eq 'Vertical'){'SideBySide'}else{'Stacked'}
$script:layoutOrder=@($settings.PlayerOrder)
if($settings -and $settings.SplitRatio -ge 0.3 -and $settings.SplitRatio -le 0.7){$uiSplitRatio.Value=$settings.SplitRatio}
$script:layoutDrag=$null
function Update-LayoutPreview {
    if(!$uiLayoutPreview){return}
    $selected=@($script:rows | Where-Object {$_.Enabled.IsChecked})
    $uiLayoutPreview.Children.Clear()
    if(!$selected.Count -or $selected.Count -gt 4){$uiLayoutLabel.Text='Select 1-4 players';return}
    $ids=@($selected | ForEach-Object {[string]$_.Profile.AccountId})
    $script:layoutOrder=@(Resolve-LayoutOrder $ids $script:layoutOrder)
    $names=@(Get-LayoutNames $selected.Count)
    if($script:layoutName -notin $names){$script:layoutName=$names[0]}
    $uiLayoutLabel.Text=$script:layoutName -creplace '([a-z])([A-Z])','$1 $2'
    $uiSplitRatio.IsEnabled=$selected.Count -gt 1 -and ($selected.Count -eq 2 -or $script:layoutName -notin @('Stacked','SideBySide'))
    $screen=[Windows.Forms.Screen]::AllScreens[[math]::Max(0,$uiMonitor.SelectedIndex)]
    $uiLayoutPreview.Height=640.0*$screen.Bounds.Height/$screen.Bounds.Width
    $bounds=[pscustomobject]@{X=0;Y=0;Width=640;Height=$uiLayoutPreview.Height}
    $cells=@(Get-NormalizedLayout $selected.Count $script:layoutName $uiSplitRatio.Value)
    $palette=@('#125C76','#784522','#4A3976','#286148')
    for($i=0;$i -lt $cells.Count;$i++){
        $id=$script:layoutOrder[$i];$row=$selected | Where-Object {$_.Profile.AccountId -eq $id} | Select-Object -First 1
        $maintain16x9 = [bool]($uiRatio16x9 -and $uiRatio16x9.IsChecked)
        $cell=Convert-LayoutCell $cells[$i] $bounds $maintain16x9
        $tile=New-Object Windows.Controls.Border;$tile.Width=[math]::Max(1,$cell.Width-4);$tile.Height=[math]::Max(1,$cell.Height-4)
        $tile.Background=$palette[[array]::IndexOf($ids,$id)%4];$tile.BorderBrush='#9CAFC7';$tile.BorderThickness=1;$tile.CornerRadius=5
        $tile.Tag=$i;$tile.Cursor='Hand';$tile.ToolTip=$row.Profile.Name+' - drag to another section to swap players';$tile.Focusable=$true
        [Windows.Automation.AutomationProperties]::SetName($tile,('Screen section '+($i+1)+': '+$row.Profile.Name))
        $label=New-Object Windows.Controls.TextBlock;$label.Text='P'+([array]::IndexOf($script:rows,$row)+1);$label.Foreground='White';$label.FontSize=40*[math]::Max(1,$uiLayoutPreview.Height/360);$label.TextWrapping='Wrap';$label.TextAlignment='Center';$label.VerticalAlignment='Center';$label.Margin=8;$tile.Child=$label
        [Windows.Controls.Canvas]::SetLeft($tile,$cell.X+2);[Windows.Controls.Canvas]::SetTop($tile,$cell.Y+2)
        $tile.Add_MouseLeftButtonDown({param($sender,$event) $script:layoutDrag=[int]$sender.Tag;$sender.Opacity=0.65;[void]$uiLayoutPreview.CaptureMouse();$event.Handled=$true})
        [void]$uiLayoutPreview.Children.Add($tile)
    }
}
function Switch-PreviewLayout([int]$Delta){
    $count=@($script:rows | Where-Object {$_.Enabled.IsChecked}).Count
    $names=@(Get-LayoutNames $count);$index=[array]::IndexOf($names,$script:layoutName)
    $script:layoutName=$names[($index+$Delta+$names.Count)%$names.Count];Update-LayoutPreview
}
function Swap-PreviewPlayers([int]$From,[int]$To){
    if($From -ge 0 -and $To -ge 0 -and $From -lt $script:layoutOrder.Count -and $To -lt $script:layoutOrder.Count){
        $id=$script:layoutOrder[$From];$script:layoutOrder[$From]=$script:layoutOrder[$To];$script:layoutOrder[$To]=$id
    }
    Update-LayoutPreview
}
$uiLayoutPreview.Add_MouseLeftButtonUp({param($sender,$event)
    if($null -eq $script:layoutDrag){return}
    $from=$script:layoutDrag;$script:layoutDrag=$null;$sender.ReleaseMouseCapture();$point=$event.GetPosition($sender)
    foreach($tile in $sender.Children){
        $x=[Windows.Controls.Canvas]::GetLeft($tile);$y=[Windows.Controls.Canvas]::GetTop($tile)
        if($point.X -ge $x -and $point.X -lt $x+$tile.Width -and $point.Y -ge $y -and $point.Y -lt $y+$tile.Height){Swap-PreviewPlayers $from ([int]$tile.Tag);return}
    }
    Update-LayoutPreview
})
$uiLayoutPreview.Add_LostMouseCapture({if($null -ne $script:layoutDrag){$script:layoutDrag=$null;Update-LayoutPreview}})
$uiNextLayout.Add_Click({Switch-PreviewLayout 1})
$uiPreviousLayout.Add_Click({Switch-PreviewLayout -1})
$uiSplitRatio.Add_ValueChanged({Update-LayoutPreview})
$uiMonitor.Add_SelectionChanged({Update-LayoutPreview})
$uiFull.Add_Checked({Update-LayoutPreview});$uiFull.Add_Unchecked({Update-LayoutPreview})
if($uiRatio16x9){$uiRatio16x9.Add_Checked({Update-LayoutPreview});$uiRatio16x9.Add_Unchecked({Update-LayoutPreview})}
$uiApplyLayout.Add_Click({Invoke-Panel {Save-PlayerRows;Start-PanelJob Arrange}})
