if(-not ('TaskbarIconHelper' -as [type])){
Add-Type @'
using System;
using System.IO;
using System.Runtime.InteropServices;

public static class TaskbarIconHelper {
    [DllImport("shell32.dll", SetLastError = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadImageW(IntPtr hinst, string lpszName, uint uType, int cxDesired, int cyDesired, uint fuLoad);

    [DllImport("user32.dll", EntryPoint = "SetClassLongPtrW")]
    private static extern IntPtr SetClassLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll", EntryPoint = "SetClassLongW")]
    private static extern IntPtr SetClassLong32(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    public static IntPtr SetClassLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong) {
        if (IntPtr.Size == 8)
            return SetClassLongPtr64(hWnd, nIndex, dwNewLong);
        return SetClassLong32(hWnd, nIndex, dwNewLong);
    }

    private const uint WM_SETICON = 0x0080;
    private const int ICON_SMALL = 0;
    private const int ICON_BIG = 1;
    private const int GCLP_HICON = -14;
    private const int GCLP_HICONSM = -34;
    private const uint IMAGE_ICON = 1;
    private const uint LR_LOADFROMFILE = 0x00000010;

    private static IntPtr _hBig = IntPtr.Zero;
    private static IntPtr _hSm = IntPtr.Zero;

    public static void Initialize(string appId) {
        try {
            SetCurrentProcessExplicitAppUserModelID(appId);
        } catch { }
    }

    public static void ApplyWindowIcon(IntPtr hWnd, string iconPath) {
        if (hWnd == IntPtr.Zero || string.IsNullOrEmpty(iconPath) || !File.Exists(iconPath)) return;
        try {
            if (_hBig == IntPtr.Zero) {
                _hBig = LoadImageW(IntPtr.Zero, iconPath, IMAGE_ICON, 48, 48, LR_LOADFROMFILE);
                _hSm = LoadImageW(IntPtr.Zero, iconPath, IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
            }
            if (_hBig != IntPtr.Zero) {
                SendMessage(hWnd, WM_SETICON, (IntPtr)ICON_BIG, _hBig);
                SetClassLongPtr(hWnd, GCLP_HICON, _hBig);
            }
            if (_hSm != IntPtr.Zero) {
                SendMessage(hWnd, WM_SETICON, (IntPtr)ICON_SMALL, _hSm);
                SetClassLongPtr(hWnd, GCLP_HICONSM, _hSm);
            }
        } catch { }
    }
}
'@
}
[TaskbarIconHelper]::Initialize('HytaleTogether.Launcher')
Add-Type -Path (Join-Path $script:BundleRoot 'DualSenseManager.cs')
[DualSenseManager]::Initialize()
$script:profiles=@(Read-Profiles | Sort-Object ScreenSlot)
$script:rows=@();$script:job=$null;$script:jobAction='';$script:binding=$null
$script:launch=New-LaunchState;$script:autoLaunch=$true
$script:colors=[ordered]@{'Electric Cyan'=@(0,210,255);'Warm Amber'=@(245,166,35);'Neon Emerald'=@(16,185,129);'Royal Purple'=@(168,85,247);'Crimson Red'=@(239,68,68);'Golden Yellow'=@(234,179,8);'Hot Pink'=@(236,72,153);'Pure White'=@(255,255,255);'Off'=@(0,0,0)}
$settingsPath=Join-Path $script:BundleRoot 'splitscreen-settings.json'
$settings=$null
if(Test-Path $settingsPath){$settings=Get-Content -Raw $settingsPath | ConvertFrom-Json}
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Hytale Together - Preview" Width="1160" Height="940" MinWidth="900" MinHeight="600" WindowStartupLocation="CenterScreen" Background="#0B0F17" FontFamily="Segoe UI" Foreground="#E7EDF5">
 <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#E6EDF3"/>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="#00D2FF"/>
            <Setter Property="BorderBrush" Value="#223046"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
            <Setter Property="Padding" Value="10"/>
        </Style>

        <ControlTemplate x:Key="ComboBoxToggleButton" TargetType="ToggleButton">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition />
                    <ColumnDefinition Width="24" />
                </Grid.ColumnDefinitions>
                <Border x:Name="Border" Grid.ColumnSpan="2" CornerRadius="5" Background="#141C2B" BorderBrush="#30415D" BorderThickness="1" />
                <Path Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M 0 0 L 4 4 L 8 0 Z" Fill="#8B949E" />
            </Grid>
            <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="Border" Property="BorderBrush" Value="#00D2FF" />
                    <Setter TargetName="Border" Property="Background" Value="#1A2436" />
                </Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>

        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="#141C2B"/>
            <Setter Property="Foreground" Value="#E6EDF3"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="ItemBorder" Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}">
                            <ContentPresenter />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="#0096C7" />
                                <Setter Property="Foreground" Value="#FFFFFF" />
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="#1A3A5A" />
                                <Setter Property="Foreground" Value="#00D2FF" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="Foreground" Value="#E6EDF3"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton Template="{StaticResource ComboBoxToggleButton}" Focusable="false" IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press"/>
                            <ContentPresenter IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" Margin="10,0,24,0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                            <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" x:Name="Popup" Focusable="False" AllowsTransparency="True" PopupAnimation="Slide">
                                <Grid MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}" SnapsToDevicePixels="True">
                                    <Border Background="#141C2B" BorderBrush="#30415D" BorderThickness="1" CornerRadius="5" Margin="0,2,0,0">
                                        <ScrollViewer SnapsToDevicePixels="True">
                                            <StackPanel IsItemsHost="True"/>
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

<Style TargetType="Button">
 <Setter Property="Foreground" Value="#E6EDF3"/><Setter Property="Background" Value="#1D293C"/><Setter Property="BorderBrush" Value="#30415D"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Margin" Value="4"/><Setter Property="Padding" Value="12,8"/><Setter Property="Cursor" Value="Hand"/>
 <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Chrome" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="BorderBrush" Value="#00D2FF"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Chrome" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
</Style>
<Style TargetType="CheckBox"><Setter Property="Foreground" Value="#E6EDF3"/><Setter Property="Margin" Value="6,8"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
        <Style x:Key="IconToggle" TargetType="ToggleButton">
            <Setter Property="Background" Value="#141C2B"/>
            <Setter Property="BorderBrush" Value="#30415D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="Margin" Value="3,2"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToggleButton">
                        <Border x:Name="Border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="#00D2FF"/>
                                <Setter TargetName="Border" Property="Background" Value="#162E44"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="#00D2FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
 </Window.Resources>
 <DockPanel Margin="16" Background="#0B0F17">
  <StackPanel DockPanel.Dock="Top">
   <TextBlock Text="HYTALE TOGETHER" Foreground="#00D2FF" FontSize="22" FontWeight="Bold"/>
   <TextBlock Text="1-4 players | Private account saves | SDL gamepad input" Margin="0,5,0,10"/>
   <WrapPanel Margin="0,4,0,8">
    <Button x:Name="Auto" ToolTip="Start session" Background="#0C3326" BorderBrush="#10B981" Padding="14,8">
     <Path Width="14" Height="14" Stretch="Uniform" Fill="#10B981" Data="M 3 1 L 13 8 L 3 15 Z"/>
    </Button>
    <Button x:Name="Stop" ToolTip="Stop &amp; restore running sessions" Background="#281418" BorderBrush="#EF4444" Padding="12,8">
     <Path Width="14" Height="14" Stretch="Uniform" Fill="#EF4444" Data="M 2 2 H 14 V 14 H 2 Z"/>
    </Button>
   </WrapPanel>
   <Expander x:Name="Setup" Header="Setup &amp; more" Foreground="#E6EDF3" Margin="4,2,4,10">
    <StackPanel>
     <TextBlock Text="First time: open the official launcher, launch each account to its main menu, then add running accounts. Close those game windows before starting your first session." TextWrapping="Wrap" Foreground="#9CA3AF" Margin="4,10"/>
     <WrapPanel>
      <Button x:Name="ManualStart" Content="Manual start session" ToolTip="Start session with manual launcher account selection and Play"/>
      <Button x:Name="Launcher" Content="Open launcher"/>
      <Button x:Name="Discover" Content="Add running accounts"/>
     </WrapPanel>
    </StackPanel>
   </Expander>
   <WrapPanel Margin="0,4,0,6">
    <TextBlock Text="Display" VerticalAlignment="Center" Margin="4"/><WrapPanel x:Name="MonitorIcons"/><ComboBox x:Name="Monitor" Width="210" MinHeight="30" Visibility="Collapsed"/><ComboBox x:Name="LayoutSelect" Visibility="Collapsed"/>
    <ToggleButton x:Name="Full" Style="{StaticResource IconToggle}" ToolTip="Fill screen (borderless fullscreen)">
     <Path Width="14" Height="14" Stretch="Uniform" Stroke="#B9C7D9" StrokeThickness="1.5" Data="M 2,5 L 2,2 L 5,2 M 9,2 L 12,2 L 12,5 M 12,9 L 12,12 L 9,12 M 5,12 L 2,12 L 2,9"/>
    </ToggleButton>
    <ToggleButton x:Name="Resize" Style="{StaticResource IconToggle}" ToolTip="Resizable windows">
     <Path Width="14" Height="14" Stretch="Uniform" Stroke="#B9C7D9" StrokeThickness="1.5" Data="M 2,2 L 14,2 L 14,14 L 2,14 Z M 2,5 L 14,5 M 9,14 L 14,9 M 11,14 L 14,11"/>
    </ToggleButton>
   </WrapPanel>
   <Border Background="#121824" CornerRadius="8" Padding="10" Margin="4,2,4,8">
    <DockPanel>
     <StackPanel DockPanel.Dock="Right" Width="240" Margin="12,0,0,0">
      <TextBlock Text="SCREEN LAYOUT" Foreground="#F5A623" FontWeight="Bold"/>
      <WrapPanel><Button x:Name="PreviousLayout" Content="&#x2039;" ToolTip="Previous layout"/><TextBlock x:Name="LayoutLabel" VerticalAlignment="Center" Width="140" TextAlignment="Center"/><Button x:Name="NextLayout" Content="&#x203A;" ToolTip="Next layout"/></WrapPanel>
      <TextBlock Text="Drag numbered players between sections. Adjust the split below." TextWrapping="Wrap" Foreground="#9CA3AF"/>
      <Slider x:Name="SplitRatio" Minimum="0.3" Maximum="0.7" Value="0.5" TickFrequency="0.05" IsSnapToTickEnabled="True" Margin="4,8" ToolTip="Size of the first / larger section"/>
      <CheckBox x:Name="Ratio16x9" Content="Maintain 16:9 ratio" Foreground="#B9C7D9" Margin="4,2,4,6" ToolTip="Maintain 16:9 aspect ratio for each game window section"/>
      <Button x:Name="ApplyLayout" Content="Apply" ToolTip="Apply layout to running games"/>
     </StackPanel>
     <Viewbox Height="150" Stretch="Uniform"><Canvas x:Name="LayoutPreview" Width="640" Height="360" Background="#080C13"/></Viewbox>
    </DockPanel>
   </Border>
   <Expander Header="Session tools" Foreground="#9CA3AF" Margin="4,2,4,6">
    <WrapPanel><Button x:Name="Attach" Content="Attach open games"/><Button x:Name="Pause" Content="Pause input"/><Button x:Name="Resume" Content="Resume input"/><Button x:Name="Cancel" Content="Cancel setup"/></WrapPanel>
   </Expander>
   <Border Background="#141C2B" CornerRadius="6" Padding="6" Margin="0,5">
    <WrapPanel><Button x:Name="LocalWorlds" Content="Refresh local worlds"/><ComboBox x:Name="LocalAddress" Width="280" MinHeight="30" Margin="4"/><Button x:Name="CopyLocal" Content="Copy join address"/><TextBlock Text="Other player: Servers > Direct Connect" VerticalAlignment="Center" Margin="8,0" FontSize="11" Foreground="#9CA3AF"/></WrapPanel>
   </Border>
   <TextBlock x:Name="Status" Text="Ready" TextWrapping="Wrap" Foreground="#71D9E8" Margin="4,8"/>
   <Border Background="#101725" BorderBrush="#1E2A3E" BorderThickness="1" CornerRadius="6" Padding="8,4" Margin="0,4,0,4">
    <DockPanel>
     <TextBlock Text="PLAYERS &amp; CONTROLLERS" Foreground="#00D2FF" FontWeight="Bold" FontSize="12" VerticalAlignment="Center" Margin="4,0,0,0"/>
     <WrapPanel HorizontalAlignment="Right">
      <Button x:Name="Scan" ToolTip="Refresh controllers" Padding="8,5" Margin="2">
       <Path Width="14" Height="14" Stretch="Uniform" Fill="#00D2FF" Data="M 17.65 6.35 A 8 8 0 1 0 19 12 h -2 a 6 6 0 1 1 -1.76 -4.24 L 12 11 h 9 V 2 l -3.35 4.35 z"/>
      </Button>
      <Button x:Name="Save" ToolTip="Save players &amp; preferences" Padding="8,5" Margin="2">
       <Path Width="14" Height="14" Stretch="Uniform" Fill="#10B981" Data="M 17 3 H 5 a 2 2 0 0 0 -2 2 v 14 a 2 2 0 0 0 2 2 h 14 a 2 2 0 0 0 2 -2 V 7 l -4 -4 z m -5 16 a 3 3 0 1 1 0 -6 a 3 3 0 0 1 0 6 z m 3 -10 H 6 V 5 h 9 v 4 z"/>
      </Button>
     </WrapPanel>
    </DockPanel>
   </Border>
  </StackPanel>
  <Expander DockPanel.Dock="Bottom" Header="Activity log" Foreground="#9CA3AF" Margin="0,8,0,0"><TextBox x:Name="Log" Height="110" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="#0D121C" Foreground="#CFD9E8"/></Expander>
  <ScrollViewer VerticalScrollBarVisibility="Auto"><UniformGrid x:Name="Players" Columns="2"/></ScrollViewer>
 </DockPanel>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$iconPath=Join-Path $script:BundleRoot 'assets/hytale-together.ico'
if(Test-Path $iconPath){
    $window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconPath)
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    $hwnd = $helper.EnsureHandle()
    [TaskbarIconHelper]::ApplyWindowIcon($hwnd, $iconPath)
    $window.Add_SourceInitialized({
        param($s,$e)
        [TaskbarIconHelper]::ApplyWindowIcon($helper.Handle, $iconPath)
    })
    $window.Add_Loaded({
        param($s,$e)
        [TaskbarIconHelper]::ApplyWindowIcon($helper.Handle, $iconPath)
    })
}
foreach($name in @('Auto','ManualStart','Launcher','Discover','Scan','Monitor','LayoutSelect','Full','Resize','Ratio16x9','Save','Attach','Pause','Resume','Stop','Cancel','Status','Log','Players','LocalWorlds','LocalAddress','CopyLocal','Setup','MonitorIcons','LayoutPreview','PreviousLayout','NextLayout','LayoutLabel','SplitRatio','ApplyLayout')){Set-Variable -Name ('ui'+$name) -Value $window.FindName($name) -Scope Script}
function Write-Panel([string]$Message){
    $uiStatus.Text=$Message
    $uiLog.AppendText(('[{0:HH:mm:ss}] {1}' -f [DateTime]::Now,$Message)+"`r`n");$uiLog.ScrollToEnd()
    Add-Content -LiteralPath (Join-Path $script:BundleRoot 'studio.log') -Value (([DateTime]::UtcNow.ToString('o'))+' '+$Message)
}
function Invoke-Panel($Work){try{& $Work}catch{Write-Panel ('Error: '+$_.Exception.Message)}}
function New-Combo($Items,[string]$Selected,[int]$Width){
    $c=New-Object Windows.Controls.ComboBox;$c.Width=$Width
    foreach($item in $Items){[void]$c.Items.Add([string]$item)}
    $c.SelectedItem=$Selected
    if($c.SelectedIndex -lt 0 -and $c.Items.Count){$c.SelectedIndex=0}
    return ,$c
}
function Set-PlayerDevice($TargetRow, [string]$NewId){
    if(!$TargetRow){return}
    if($script:settingDevice){return}
    $script:settingDevice=$true
    try {
        if($NewId){
            foreach($other in $script:rows){
                if($other -ne $TargetRow -and [string]$other.Pad.SelectedValue -eq $NewId){
                    $prev = [string]$TargetRow.Pad.SelectedValue
                    $targetItem = @($other.Pad.Items | Where-Object { $_.Id -eq $prev }) | Select-Object -First 1
                    if(!$targetItem -and $prev){
                        $d = @([DualSenseManager]::GetDevices() | Where-Object {$_.Id -eq $prev}) | Select-Object -First 1
                        $lbl = if($d){ $d.Name+' ['+$d.Id.Substring($d.Id.Length-6)+']' } else { 'Disconnected ['+$prev+']' }
                        $targetItem = [pscustomobject]@{Id=$prev;Label=$lbl;Device=$d}
                        [void]$other.Pad.Items.Add($targetItem)
                    }
                    $other.Pad.SelectedValue = $prev
                    $other.Profile.Controller = $prev
                    Update-ControllerCapabilities $other
                    Write-Panel "Swapped input between $($other.Profile.Name) and $($TargetRow.Profile.Name)."
                    break
                }
            }
        }
        $newItem = @($TargetRow.Pad.Items | Where-Object { $_.Id -eq $NewId }) | Select-Object -First 1
        if(!$newItem -and $NewId){
            $d = @([DualSenseManager]::GetDevices() | Where-Object {$_.Id -eq $NewId}) | Select-Object -First 1
            $lbl = if($d){ $d.Name+' ['+$d.Id.Substring($d.Id.Length-6)+']' } else { 'Disconnected ['+$NewId+']' }
            $newItem = [pscustomobject]@{Id=$NewId;Label=$lbl;Device=$d}
            [void]$TargetRow.Pad.Items.Add($newItem)
        }
        $TargetRow.Pad.SelectedValue = $NewId
        $TargetRow.Profile.Controller = $NewId
        Update-ControllerCapabilities $TargetRow
        Save-PlayerRows
    } finally {
        $script:settingDevice=$false
    }
}
function New-DeviceIcon([string]$Kind,[int]$Number){
    $button=New-Object Windows.Controls.Button;$button.Padding='8,6';$button.MinWidth=60
    $stack=New-Object Windows.Controls.StackPanel;$stack.Orientation='Horizontal'
    $path=New-Object Windows.Shapes.Path;$path.Width=34;$path.Height=24;$path.Stretch='Uniform';$path.Stroke='#B9C7D9';$path.StrokeThickness=1.5
    $shape=if($Kind -eq 'monitor'){
        'M 2,2 L 34,2 L 34,22 L 2,22 Z M 18,22 L 18,28 M 10,28 L 26,28'
    }elseif($Kind -eq 'kbm'){
        'M 2,4 L 26,4 C 27,4 28,5 28,6 L 28,20 C 28,21 27,22 26,22 L 2,22 C 1,22 0,21 0,20 L 0,6 C 0,5 1,4 2,4 Z M 5,8 L 7,8 M 10,8 L 12,8 M 15,8 L 17,8 M 20,8 L 22,8 M 5,12 L 8,12 M 11,12 L 17,12 M 20,12 L 23,12 M 31,6 C 33,6 35,8 35,11 L 35,17 C 35,20 33,22 31,22 C 29,22 29,20 29,17 L 29,11 C 29,8 31,6 31,6 Z M 31,6 L 31,11'
    }else{
        'M 9,5 L 27,5 C 32,5 37,22 32,24 C 29,25 26,19 24,18 L 12,18 C 10,19 7,25 4,24 C -1,22 4,5 9,5 Z M 10,9 L 10,16 M 6.5,12.5 L 13.5,12.5 M 26,10 L 26,11 M 30,13 L 30,14'
    }
    $path.Data=[Windows.Media.Geometry]::Parse($shape);[void]$stack.Children.Add($path)
    $labelText=if($Kind -eq 'kbm'){'KB+M'}else{[string]$Number}
    $text=New-Object Windows.Controls.TextBlock;$text.Text=$labelText;$text.Margin='6,0,0,0';$text.VerticalAlignment='Center';[void]$stack.Children.Add($text)
    $button.Content=$stack
    return ,$button
}
function Update-ControllerCapabilities($Row){
    $val=[string]$Row.Pad.SelectedValue
    $isKbm=($val -eq 'KBM')
    $device=$null
    if($val -and !$isKbm){
        if($Row.Pad.SelectedItem -and $Row.Pad.SelectedItem.Device){
            $device=$Row.Pad.SelectedItem.Device
        }
        if(!$device){
            $device=@([DualSenseManager]::GetDevices() | Where-Object { $_.Id -eq $val }) | Select-Object -First 1
        }
        $item=@($Row.Pad.Items | Where-Object { $_.Id -eq $val }) | Select-Object -First 1
        if(!$item){
            $lbl=if($device){ $device.Name+' ['+$device.Id.Substring($device.Id.Length-6)+']' } else { 'Disconnected ['+$val+']' }
            $item=[pscustomobject]@{Id=$val;Label=$lbl;Device=$device}
            [void]$Row.Pad.Items.Add($item)
        } elseif($device -and (!$item.PSObject.Properties['Device'] -or !$item.Device)) {
            if(!$item.PSObject.Properties['Device']){
                $item | Add-Member NoteProperty Device $device -Force
            } else {
                $item.Device=$device
            }
        }
        if($item -and $Row.Pad.SelectedItem -ne $item){
            $Row.Pad.SelectedItem=$item
        }
    }
    if($Row.PSObject.Properties['Choices']){
        foreach($choice in $Row.Choices){
            $isSelected=($choice.Tag.Id -eq $val)
            $choice.BorderBrush=if($isSelected){'#00D2FF'}else{'#30415D'}
            $choice.BorderThickness=if($isSelected){2}else{1}
        }
    }
    $hasLed=(!$isKbm -and $null -ne $device -and $device.HasLed)
    $hasRumble=(!$isKbm -and $null -ne $device -and $device.HasRumble)
    $hasTouch=(!$isKbm -and $null -ne $device -and $device.HasTouchpad)

    $Row.Swatches.IsEnabled=$hasLed
    $Row.Swatches.ToolTip=if($isKbm){'Keyboard & Mouse does not use RGB lights.'}elseif($hasLed){'RGB light color for this controller.'}else{'RGB color is available only when this controller reports a programmable lightbar.'}
    if($Row.PSObject.Properties['Color'] -and $Row.Color){$Row.Color.IsEnabled=$hasLed}
    $Row.Vibrate.IsEnabled=$hasRumble
    $Row.Touch.IsEnabled=$hasTouch
    if($Row.PSObject.Properties['TouchSensPanel']){
        $Row.TouchSensPanel.IsEnabled=($hasTouch -and [bool]$Row.Touch.IsChecked)
    }
    if($device -and !$device.HasTouchpad){$Row.Touch.IsChecked=$false}
    if($isKbm){
        $Row.Signal.Text='Input: Keyboard & Mouse (system focus)'
        $Row.Signal.Foreground='#10B981'
    } else {
        if(!$val){
            $Row.Signal.Text='Input: not attached'
            $Row.Signal.Foreground='#9CA3AF'
        } elseif($device){
            $Row.Signal.Text='Input: '+$device.Name
            $Row.Signal.Foreground='#00D2FF'
        } else {
            $Row.Signal.Text='Input: Disconnected ['+$val+']'
            $Row.Signal.Foreground='#EF4444'
        }
    }
}
function Build-PlayerRows {
    $uiPlayers.Children.Clear();$script:rows=@()
    $devices=@([DualSenseManager]::GetDevices());$uiSetup.IsExpanded=$script:profiles.Count -eq 0
    if(!$script:profiles.Count){
        $empty=New-Object Windows.Controls.Border;$empty.Background='#121824';$empty.CornerRadius=10;$empty.Padding=24;$empty.Margin=4
        $emptyText=New-Object Windows.Controls.TextBlock;$emptyText.Text="Add your first player`n`nStart a signed-in game from the official launcher, then choose Add running accounts above. Your existing worlds stay intact.";$emptyText.TextWrapping='Wrap';$emptyText.FontSize=15;$emptyText.Foreground='#B9C7D9';$empty.Child=$emptyText;[void]$uiPlayers.Children.Add($empty)
    }
    foreach($p in $script:profiles){
        $border=New-Object Windows.Controls.Border;$border.Background='#121824';$border.BorderBrush='#223046';$border.BorderThickness=1;$border.CornerRadius=8;$border.Margin='0,4,8,8';$border.Padding=14
        $stack=New-Object Windows.Controls.StackPanel;$border.Child=$stack
        $header=New-Object Windows.Controls.DockPanel;$header.LastChildFill=$false;$header.Margin='0,0,0,8'
        $enabled=New-Object Windows.Controls.CheckBox;$enabled.Content='P'+($script:rows.Count+1)+' '+$p.Name+' / '+$p.Branch;$enabled.FontSize=15;$enabled.FontWeight='SemiBold';$enabled.Foreground='#00D2FF';$enabled.IsChecked=(!$p.PSObject.Properties['Enabled'] -or $p.Enabled);$enabled.VerticalAlignment='Center'
        [Windows.Controls.DockPanel]::SetDock($enabled, [Windows.Controls.Dock]::Left)
        [void]$header.Children.Add($enabled)

        $headerRight=New-Object Windows.Controls.StackPanel;$headerRight.Orientation='Horizontal';$headerRight.VerticalAlignment='Center'
        [Windows.Controls.DockPanel]::SetDock($headerRight, [Windows.Controls.Dock]::Right)

        $vibrate=New-Object Windows.Controls.Button;$vibrate.Padding='6,4';$vibrate.Margin='0,0,6,0';$vibrate.VerticalAlignment='Center';$vibrate.ToolTip='Test controller vibration'
        [Windows.Automation.AutomationProperties]::SetName($vibrate,'Test vibration')
        $vibratePath=New-Object Windows.Shapes.Path;$vibratePath.Width=14;$vibratePath.Height=13;$vibratePath.Stretch='Uniform'
        $vibratePath.Fill=(New-Object Windows.Media.BrushConverter).ConvertFromString('#00D2FF')
        $vibratePath.Data=[Windows.Media.Geometry]::Parse('M 4,2 L 12,2 C 13.1,2 14,2.9 14,4 L 14,12 C 14,13.1 13.1,14 12,14 L 4,14 C 2.9,14 2,13.1 2,12 L 2,4 C 2,2.9 2.9,2 4,2 Z M 0,5 C -0.5,6.5 -0.5,9.5 0,11 M 16,5 C 16.5,6.5 16.5,9.5 16,11 M 5,11 L 11,11 M 5,5 L 7,5 M 9,5 L 11,5')
        $vibrate.Content=$vibratePath
        [void]$headerRight.Children.Add($vibrate)

        $assignBtn=New-Object Windows.Controls.Button;$assignBtn.Padding='8,4';$assignBtn.Margin='0';$assignBtn.VerticalAlignment='Center'
        $assignBtn.ToolTip='Press any controller button/stick or keyboard key to assign to '+$p.Name
        $assignStack=New-Object Windows.Controls.StackPanel;$assignStack.Orientation='Horizontal'
        $assignPath=New-Object Windows.Shapes.Path;$assignPath.Width=14;$assignPath.Height=13;$assignPath.Stretch='Uniform'
        $assignPath.Fill=(New-Object Windows.Media.BrushConverter).ConvertFromString('#00D2FF')
        $assignPath.Data=[Windows.Media.Geometry]::Parse('M 9,5 L 27,5 C 32,5 37,22 32,24 C 29,25 26,19 24,18 L 12,18 C 10,19 7,25 4,24 C -1,22 4,5 9,5 Z M 10,9 L 10,16 M 6.5,12.5 L 13.5,12.5 M 26,10 L 26,11 M 30,13 L 30,14')
        [void]$assignStack.Children.Add($assignPath)
        $assignLabel=New-Object Windows.Controls.TextBlock;$assignLabel.Text='Assign input';$assignLabel.Margin='5,0,0,0';$assignLabel.VerticalAlignment='Center';$assignLabel.FontSize=11
        [void]$assignStack.Children.Add($assignLabel)
        $assignBtn.Content=$assignStack
        [void]$headerRight.Children.Add($assignBtn)
        [void]$header.Children.Add($headerRight)
        [void]$stack.Children.Add($header)

        $line=New-Object Windows.Controls.StackPanel;[void]$stack.Children.Add($line)
        $pad=New-Object Windows.Controls.ComboBox;$pad.Width=370;$pad.Height=32;$pad.Margin='4,6,4,10';$pad.HorizontalAlignment='Left';$pad.DisplayMemberPath='Label';$pad.SelectedValuePath='Id'
        [void]$pad.Items.Add([pscustomobject]@{Id='';Label='Choose controller'})
        [void]$pad.Items.Add([pscustomobject]@{Id='KBM';Label='Keyboard & Mouse'})
        foreach($d in $devices){[void]$pad.Items.Add([pscustomobject]@{Id=$d.Id;Label=($d.Name+' ['+$d.Id.Substring($d.Id.Length-6)+']');Device=$d})}
        if($p.Controller -and $p.Controller -ne 'KBM' -and $p.Controller -notin @($devices.Id)){[void]$pad.Items.Add([pscustomobject]@{Id=$p.Controller;Label=('Disconnected ['+$p.Controller+']')})}
        $pad.SelectedValue=[string]$p.Controller;if($pad.SelectedIndex -lt 0){$pad.SelectedIndex=0};$details=New-Object Windows.Controls.Expander;$details.Header='Device details';$details.Foreground='#9CA3AF';$details.Content=$pad;[void]$line.Children.Add($details)
        $colorName=if($p.PSObject.Properties['Color']){$p.Color}elseif($settings -and $settings.PSObject.Properties['P'+$p.ScreenSlot+'Color']){$settings.('P'+$p.ScreenSlot+'Color')}else{'Electric Cyan'}
        $line2=New-Object Windows.Controls.WrapPanel;[void]$stack.Children.Add($line2)
        $touch=New-Object Windows.Controls.CheckBox;$touch.Content='Touchpad mouse';$touch.IsChecked=[bool]$p.TouchpadMouseEnabled;[void]$line2.Children.Add($touch)
        $sensPanel=New-Object Windows.Controls.StackPanel;$sensPanel.Orientation='Horizontal';$sensPanel.VerticalAlignment='Center';$sensPanel.Margin='6,0,10,0'
        $sensLabel=New-Object Windows.Controls.TextBlock;$sensLabel.Text='Sens:';$sensLabel.Foreground='#9CA3AF';$sensLabel.VerticalAlignment='Center';$sensLabel.Margin='0,0,4,0';$sensLabel.ToolTip='Touchpad mouse sensitivity'
        [void]$sensPanel.Children.Add($sensLabel)
        $currentSens=if($p.PSObject.Properties['TouchpadSensitivity'] -and $p.TouchpadSensitivity -gt 0){[double]$p.TouchpadSensitivity}else{1.0}
        $sensSlider=New-Object Windows.Controls.Slider;$sensSlider.Width=80;$sensSlider.Minimum=0.2;$sensSlider.Maximum=3.0;$sensSlider.Value=$currentSens;$sensSlider.TickFrequency=0.1;$sensSlider.IsSnapToTickEnabled=$true;$sensSlider.VerticalAlignment='Center'
        $sensSlider.ToolTip='Touchpad mouse pointer sensitivity (0.2x - 3.0x)'
        [void]$sensPanel.Children.Add($sensSlider)
        $sensText=New-Object Windows.Controls.TextBlock;$sensText.Text=('{0:0.0}x' -f $sensSlider.Value);$sensText.Foreground='#00D2FF';$sensText.VerticalAlignment='Center';$sensText.Margin='4,0,0,0';$sensText.Width=30
        [void]$sensPanel.Children.Add($sensText)
        $sensSlider.Tag=$sensText
        $sensSlider.Add_ValueChanged({
            param($s,$e)
            try {
                if($s -and $s.Tag -and $s.Tag.PSObject.Properties['Text']){
                    $s.Tag.Text=('{0:0.0}x' -f $s.Value)
                }
            } catch {}
        })
        [void]$line2.Children.Add($sensPanel)
        $escape=New-Combo @('No Escape mapping','Share = Escape','PS = Escape','Share + PS = Escape') '' 185;$escape.SelectedIndex=[int]$p.EscapeButtonMode;[void]$line2.Children.Add($escape)
        $signal=New-Object Windows.Controls.TextBlock;$signal.Foreground='#9CA3AF';$signal.Margin='6,6,0,0';$signal.Text='Input: not attached';[void]$stack.Children.Add($signal)
        $row=[pscustomobject]@{Signal=$signal;Profile=$p;Enabled=$enabled;Pad=$pad;SelectedColor=$colorName;Touch=$touch;TouchSensitivity=$sensSlider;TouchSensPanel=$sensPanel;Escape=$escape;Vibrate=$vibrate;Swatches=$null}
        $touch.Tag=$row
        $touch.Add_Checked({param($sender,$event) if($sender.Tag){Update-ControllerCapabilities $sender.Tag}})
        $touch.Add_Unchecked({param($sender,$event) if($sender.Tag){Update-ControllerCapabilities $sender.Tag}})
        $vibrate.Tag=$row;$vibrate.Add_Click({param($sender,$event) Invoke-Panel {if(![DualSenseManager]::VibrateById([string]$sender.Tag.Pad.SelectedValue,32768,600)){throw [DualSenseManager]::LastError};Write-Panel 'Vibration command accepted.'}})
        $swatches=New-Object Windows.Controls.WrapPanel;$swatches.Margin='0,6,0,4';$swatches.VerticalAlignment='Center'
        $row.Swatches=$swatches
        foreach($colorKey in $script:colors.Keys){
            $rgb=$script:colors[$colorKey];$swatch=New-Object Windows.Controls.Button;$swatch.Width=26;$swatch.Height=22;$swatch.Padding=0;$swatch.Margin=2;$swatch.ToolTip=$colorKey
            $swatch.Background=New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb($rgb[0],$rgb[1],$rgb[2]))
            $swatch.BorderBrush=if($colorKey -eq $colorName){ '#00D2FF' } else { '#223046' }
            $swatch.BorderThickness=if($colorKey -eq $colorName){ 2 } else { 1 }
            $swatch.Tag=[pscustomobject]@{Row=$row;Name=$colorKey}
            $swatch.Add_Click({param($sender,$event)
                $r=$sender.Tag.Row;$cName=$sender.Tag.Name
                $r.SelectedColor=$cName;$r.Profile.Color=$cName
                foreach($child in $r.Swatches.Children){
                    if($child.Tag -and $child.Tag.PSObject.Properties['Name']){
                        $isSel=($child.Tag.Name -eq $cName)
                        $child.BorderBrush=if($isSel){'#00D2FF'}else{'#223046'}
                        $child.BorderThickness=if($isSel){2}else{1}
                    }
                }
                if($r.Pad.SelectedValue -and $r.Pad.SelectedValue -ne 'KBM'){
                    $rgb=$script:colors[$cName]
                    [void][DualSenseManager]::SetLedById([string]$r.Pad.SelectedValue,$rgb[0],$rgb[1],$rgb[2])
                }
                Save-PlayerRows
            })
            [void]$swatches.Children.Add($swatch)
        }
        [void]$stack.Children.Add($swatches)
        $choices=New-Object Windows.Controls.WrapPanel;$choiceButtons=@();$deviceNumber=0
        foreach($device in $devices){
            $deviceNumber++;$choice=New-DeviceIcon 'controller' $deviceNumber
            $choice.ToolTip=$device.Name+' ['+$device.Id+']'
            [Windows.Automation.AutomationProperties]::SetName($choice,('Assign controller '+$deviceNumber+': '+$device.Name))
            $choice.Tag=[pscustomobject]@{Row=$row;Id=$device.Id}
            $choice.Add_Click({param($sender,$event) Set-PlayerDevice $sender.Tag.Row $sender.Tag.Id})
            [void]$choices.Children.Add($choice);$choiceButtons+=,$choice
        }
        $kbmChoice=New-DeviceIcon 'kbm' 0
        $kbmChoice.ToolTip='Assign Keyboard & Mouse'
        [Windows.Automation.AutomationProperties]::SetName($kbmChoice,'Assign Keyboard & Mouse')
        $kbmChoice.Tag=[pscustomobject]@{Row=$row;Id='KBM'}
        $kbmChoice.Add_Click({param($sender,$event) Set-PlayerDevice $sender.Tag.Row 'KBM'})
        [void]$choices.Children.Add($kbmChoice);$choiceButtons+=,$kbmChoice

        $assignBtn.Tag=$row
        $assignBtn.Add_Click({param($sender,$event) Invoke-Panel {
            if($script:job -or $script:launch.Phase -ne 'Idle'){throw 'Cancel the current operation before assigning.'}
            $targetRow=$sender.Tag
            [DualSenseManager]::OpenAll()
            $script:binding=[pscustomobject]@{
                TargetRow=$targetRow
                Released=$false
                Pending=$null
                Deadline=[DateTime]::UtcNow.AddSeconds(45)
            }
            Write-Panel ('Press any button/stick on controller or press any key for '+$targetRow.Profile.Name+'...')
        }})
        $line.Children.Insert(0,$choices)
        $row | Add-Member NoteProperty Choices $choiceButtons
        $pad.Tag=$row;$pad.Add_SelectionChanged({param($sender,$event) if(!$script:settingDevice -and $sender.Tag -and $sender.SelectedValue -and [string]$sender.SelectedValue -ne [string]$sender.Tag.Profile.Controller){Set-PlayerDevice $sender.Tag [string]$sender.SelectedValue}})
        Update-ControllerCapabilities $row
        $enabled.Add_Checked({Update-LayoutPreview});$enabled.Add_Unchecked({Update-LayoutPreview})
        $script:rows+=,$row;[void]$uiPlayers.Children.Add($border)
    }
    Update-LayoutPreview
}
function Save-PlayerRows([switch]$RequireControllers){
    $all=@();$slot=0
    foreach($r in $script:rows){
        $p=$r.Profile;$slot++
        $sensVal=if($r.PSObject.Properties['TouchSensitivity']){[math]::Round([double]$r.TouchSensitivity.Value, 2)}elseif($p.PSObject.Properties['TouchpadSensitivity']){[double]$p.TouchpadSensitivity}else{1.0}
        $colorVal=if($r.PSObject.Properties['SelectedColor'] -and $r.SelectedColor){[string]$r.SelectedColor}elseif($p.PSObject.Properties['Color']){[string]$p.Color}else{'Electric Cyan'}
        $entry=[pscustomobject]@{AccountId=$p.AccountId;Name=$p.Name;Branch=$p.Branch;Controller=[string]$r.Pad.SelectedValue;UserData=$p.UserData;ScreenSlot=$slot;Enabled=[bool]$r.Enabled.IsChecked;TouchpadMouseEnabled=[bool]$r.Touch.IsChecked;TouchpadSensitivity=$sensVal;EscapeButtonMode=$r.Escape.SelectedIndex;Color=$colorVal;ClientExe=$p.ClientExe}
        $all+=,$entry
    }
    Assert-PlayerConfiguration @($all | Where-Object Enabled) -RequireControllers:$RequireControllers
    Save-PublicJson $all $script:ProfileIndex;$script:profiles=$all
    foreach($p in @($all | Where-Object { $_.Enabled -and $_.Controller -ne 'KBM' })){if($p.Controller -and @([DualSenseManager]::GetDevices() | Where-Object {$_.Id -eq $p.Controller -and $_.HasLed}).Count){$rgb=$script:colors[$p.Color];if(![DualSenseManager]::SetLedById($p.Controller,$rgb[0],$rgb[1],$rgb[2])){Write-Panel ($p.Name+': '+[DualSenseManager]::LastError)}}}
    [pscustomobject]@{MonitorIndex=$uiMonitor.SelectedIndex;Layout=[string]$uiLayoutSelect.SelectedItem;LayoutName=$script:layoutName;SplitRatio=[double]$uiSplitRatio.Value;PlayerOrder=@($script:layoutOrder);WindowMode=$(if($uiFull.IsChecked){'FullScreen'}else{'Windowed'});ManualResize=[bool]$uiResize.IsChecked;Maintain16x9=[bool]$uiRatio16x9.IsChecked} | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
}
function Start-PanelJob([string]$ActionName){
    if($script:job -or $script:launch.HookJob){throw 'Wait for the current operation to finish.'}
    $arguments='-NoProfile -ExecutionPolicy Bypass -File '+[HytaleLaunchArgs]::Quote((Join-Path $script:BundleRoot 'SplitScreen.ps1'))+' -Action '+$ActionName+' -MonitorIndex '+$uiMonitor.SelectedIndex+' -Layout '+$uiLayoutSelect.SelectedItem+' -WindowMode '+$(if($uiFull.IsChecked){'FullScreen'}else{'Windowed'})
    if($uiResize.IsChecked){$arguments+=' -ManualResize'}
    $script:job=[HytaleAssignmentProcess]::new((Join-Path $PSHOME 'powershell.exe'),$arguments);$script:jobAction=$ActionName
    Write-Panel ($ActionName+' started...')
}
foreach($screen in [Windows.Forms.Screen]::AllScreens){[void]$uiMonitor.Items.Add($screen.DeviceName+' '+$screen.Bounds.Width+'x'+$screen.Bounds.Height)}
$uiMonitor.SelectedIndex=0
if($settings -and $settings.MonitorIndex -lt $uiMonitor.Items.Count){$uiMonitor.SelectedIndex=$settings.MonitorIndex}
$displayNumber=0
foreach($screen in [Windows.Forms.Screen]::AllScreens){
    $displayNumber++;$choice=New-DeviceIcon 'monitor' $displayNumber;$choice.Tag=$displayNumber-1
    $choice.ToolTip=$screen.DeviceName+' | '+$screen.Bounds.Width+' x '+$screen.Bounds.Height
    [Windows.Automation.AutomationProperties]::SetName($choice,('Display '+$displayNumber+' '+$choice.ToolTip))
    $choice.BorderBrush=if($choice.Tag -eq $uiMonitor.SelectedIndex){'#00D2FF'}else{'#30415D'}
    $choice.Add_Click({param($sender,$event) $uiMonitor.SelectedIndex=[int]$sender.Tag;foreach($other in $uiMonitorIcons.Children){$other.BorderBrush=if($other.Tag -eq $uiMonitor.SelectedIndex){'#00D2FF'}else{'#30415D'}}})
    [void]$uiMonitorIcons.Children.Add($choice)
}
[void]$uiLayoutSelect.Items.Add('Horizontal');[void]$uiLayoutSelect.Items.Add('Vertical');$uiLayoutSelect.SelectedIndex=0
if($settings){
    $uiLayoutSelect.SelectedItem=$settings.Layout
    $uiFull.IsChecked=$settings.WindowMode -eq 'FullScreen'
    $uiResize.IsChecked=[bool]$settings.ManualResize
    if($settings.PSObject.Properties['Maintain16x9']){$uiRatio16x9.IsChecked=[bool]$settings.Maintain16x9}
}
. (Join-Path $script:BundleRoot 'modules/LayoutPreview.ps1')
$uiSave.Add_Click({Invoke-Panel {Save-PlayerRows;Write-Panel 'Account bindings and display preferences saved.'}})
$uiScan.Add_Click({Invoke-Panel {if($script:rows.Count){Save-PlayerRows};Build-PlayerRows;Write-Panel 'Controllers refreshed; saved identities preserved.'}})
$uiLocalAddress.DisplayMemberPath='Label';$uiLocalAddress.SelectedValuePath='Address'
$uiLocalWorlds.Add_Click({Invoke-Panel {Start-PanelJob LocalWorlds}})
$uiCopyLocal.Add_Click({Invoke-Panel {
    if(!$uiLocalAddress.SelectedValue){throw 'Refresh local worlds and select an active host first.'}
    $world=$uiLocalAddress.SelectedItem
    $hostProcess=Get-Process -Id $world.HostPid -ErrorAction SilentlyContinue
    if(!$hostProcess -or $hostProcess.StartTime.ToUniversalTime().Ticks.ToString() -ne $world.HostStartTicks -or !@(Get-NetUDPEndpoint -LocalPort $world.Port -OwningProcess $world.ServerPid -ErrorAction SilentlyContinue).Count){throw 'That world is no longer listening. Refresh local worlds.'}
    [Windows.Clipboard]::SetText([string]$uiLocalAddress.SelectedValue)
    Write-Panel ('Copied '+$uiLocalAddress.SelectedValue+'. On the other client use Servers > Direct Connect, paste, and join.')
}})
$uiDiscover.Add_Click({Invoke-Panel {Start-PanelJob Discover}})
$uiLauncher.Add_Click({Invoke-Panel {Open-OfficialLauncher;Write-Panel 'Official launcher requested. Auto setup must prepare routing before Play.'}})
$uiAuto.Add_Click({Invoke-Panel {
    if($script:job -or $script:binding -or $script:launch.HookJob){throw 'Finish or cancel the current operation first.'}
    if(!(Test-Path (Join-Path $script:BundleRoot 'HytaleInputHost.exe'))){throw 'Input helper is quarantined or missing. Review Windows Security Protection history before launching a new session.'}
    Save-PlayerRows -RequireControllers
    Write-RoutingConfiguration | Out-Null
    Stop-LauncherAutomation
    $script:autoLaunch=$true
    $script:launch=New-LaunchState;$script:launch.Phase='AwaitAccounts'
    Open-OfficialLauncher
    Write-Panel 'Auto active. Waiting for official launcher routing; do not click Play yet.'
}})
$uiManualStart.Add_Click({Invoke-Panel {
    if($script:job -or $script:binding -or $script:launch.HookJob){throw 'Finish or cancel the current operation first.'}
    if(!(Test-Path (Join-Path $script:BundleRoot 'HytaleInputHost.exe'))){throw 'Input helper is quarantined or missing. Review Windows Security Protection history before launching a new session.'}
    Save-PlayerRows -RequireControllers
    Write-RoutingConfiguration | Out-Null
    Stop-LauncherAutomation
    $script:autoLaunch=$false
    $script:launch=New-LaunchState;$script:launch.Phase='AwaitAccounts'
    Open-OfficialLauncher
    Write-Panel 'Manual start active. Waiting for official launcher routing; select account and click Play in launcher.'
}})
$uiAttach.Add_Click({Invoke-Panel {Save-PlayerRows -RequireControllers;Start-PanelJob Attach}})
foreach($name in @('Pause','Resume','Stop')){
    $button=Get-Variable ('ui'+$name) -ValueOnly;$button.Tag=$name
    $button.Add_Click({param($sender,$event) Invoke-Panel {Stop-LauncherAutomation;$script:launch.Phase='Idle';Start-PanelJob ([string]$sender.Tag)}})
}
$uiCancel.Add_Click({Stop-LauncherAutomation;$script:launch.Phase='Idle';$script:binding=$null;Write-Panel 'Auto and controller assignment canceled. Running clients remain open.'})
$timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(25)
$script:nextSlow=[DateTime]::MinValue
$script:nextAuto=[DateTime]::MinValue
function Update-Studio {
 try {
    $busy=$null -ne $script:job -or $null -ne $script:binding -or $script:launch.Phase -ne 'Idle' -or $null -ne $script:launch.HookJob
    foreach($control in @($uiLayoutPreview,$uiNextLayout,$uiPreviousLayout,$uiSplitRatio,$uiApplyLayout,$uiPlayers,$uiAuto,$uiManualStart,$uiSave,$uiAttach,$uiScan,$uiDiscover,$uiLocalWorlds)){if($control){$control.IsEnabled=!$busy}}
    [DualSenseManager]::Pump()
    if($script:binding){
        $b=$script:binding
        if([DateTime]::UtcNow -gt $b.Deadline){$script:binding=$null;throw 'Assignment timed out; no controller assigned.'}
        $down=@([DualSenseManager]::AnyInputDown())
        if(!$b.Released){if(!$down.Count){$b.Released=$true}}
        elseif($b.Pending){
            if(!$down.Count){
                $id=$b.Pending
                if($b.PSObject.Properties['TargetRow'] -and $b.TargetRow){
                    $targetRow=$b.TargetRow
                    $script:binding=$null
                    Set-PlayerDevice $targetRow $id
                    Write-Panel ("Controller assigned to $($targetRow.Profile.Name) and saved.")
                }elseif($b.PSObject.Properties['Rows']){
                    $b.Ids+=,$id;$b.Pending=$null;$b.Index++;$b.Deadline=[DateTime]::UtcNow.AddSeconds(90)
                    if($b.Index -eq $b.Rows.Count){
                        for($i=0;$i -lt $b.Rows.Count;$i++){
                            Set-PlayerDevice $b.Rows[$i] $b.Ids[$i]
                        }
                        $script:binding=$null;Save-PlayerRows -RequireControllers;Write-Panel 'Controllers assigned and saved by account.'
                    }else{Write-Panel ('Press any button on controller for '+$b.Rows[$b.Index].Profile.Name+'.')}
                }else{$script:binding=$null}
            }
        }elseif($down.Count -eq 1 -and (!$b.PSObject.Properties['Ids'] -or $down[0] -notin $b.Ids)){$b.Pending=$down[0]}
        elseif($down.Count -gt 1){$uiStatus.Text='Multiple controllers answered. Release all buttons on other controllers.'}
    }
    if([DateTime]::UtcNow -ge $script:nextSlow){
        $script:nextSlow=[DateTime]::UtcNow.AddMilliseconds(500)
        if(Test-Path $script:SessionIndex){
            $savedSessions=Get-Content -Raw $script:SessionIndex | ConvertFrom-Json
            foreach($row in $script:rows){
                $entry=$savedSessions | Where-Object {$_.AccountId -eq $row.Profile.AccountId} | Select-Object -First 1
                try{
                    if(!$entry){throw 'No session'}
                    if([string]$row.Pad.SelectedValue -eq 'KBM'){
                        $row.Signal.Text='Input: Keyboard & Mouse (system focus)'
                        $row.Signal.Foreground='#10B981'
                    } else {
                        $snapshot=Get-AdapterSnapshot $entry.Pid
                        if($snapshot.Identity -ne [string]$row.Pad.SelectedValue){$row.Signal.Text='Input: binding changed - attach to apply';$row.Signal.Foreground='#F5A623'}
                        elseif($snapshot.Phase -ne 2 -or $snapshot.Command -ne 1){$row.Signal.Text='Input: paused, stopped, or disconnected';$row.Signal.Foreground='#F5A623'}
                        elseif($snapshot.Passed -gt 0){$row.Signal.Text='Input received: '+$snapshot.Passed+' controller events';$row.Signal.Foreground='#10B981'}
                        else{$row.Signal.Text='Waiting for controller input - move a stick';$row.Signal.Foreground='#F5A623'}
                    }
                }catch{$row.Signal.Text='Input: not attached';$row.Signal.Foreground='#9CA3AF'}
            }
        }
    }
    if([DateTime]::UtcNow -lt $script:nextAuto){return}
    $script:nextAuto=[DateTime]::UtcNow.AddMilliseconds(50)
    if($script:job -and $script:job.IsCompleted){
        $ok=$script:job.ExitCode -eq 0
        if($script:job.Output.Trim()){Write-Panel $script:job.Output.Trim()}
        if($script:job.Error.Trim()){Write-Panel $script:job.Error.Trim()}
        $completed=$script:jobAction;$script:job.Dispose();$script:job=$null
        if(!$ok){$script:launch.Phase='Idle';Write-Panel ($completed+' failed. Correct the reported issue and retry.')}
        elseif($completed -eq 'LocalWorlds'){
            $uiLocalAddress.Items.Clear()
            $worlds=Get-Content -Raw (Join-Path $script:BundleRoot 'local-worlds.json') | ConvertFrom-Json
            foreach($world in $worlds){if($world){[void]$uiLocalAddress.Items.Add($world)}}
            if($uiLocalAddress.Items.Count){$uiLocalAddress.SelectedIndex=0}
        }
        elseif($completed -eq 'Discover'){$script:profiles=@(Read-Profiles | Sort-Object ScreenSlot);Build-PlayerRows;Write-Panel 'Account catalog refreshed.'}
        elseif($completed -eq 'Arrange'){Write-Panel 'Screen layout applied.'}
        elseif($completed -eq 'Attach'){$script:launch.Phase='Idle';Write-Panel 'Adapters attached and windows arranged. Move each controller to verify input on its card.'}
    }
    if($script:launch.HookJob -and $script:launch.HookJob.IsCompleted){
        $hook=$script:launch.HookJob;$ok=$hook.ExitCode -eq 0
        $pidStr=[string]$script:launch.HookPid
        if($ok){
            $script:launch.Hooked[$pidStr]=$true
            Write-Panel 'Launcher routing ready. Automatic startup can now select the next account.'
        } else {
            $attempts=if($script:launch.PSObject.Properties['HookAttempts'] -and $script:launch.HookAttempts.ContainsKey($pidStr)){$script:launch.HookAttempts[$pidStr]}else{0}
            $attempts++
            if(!$script:launch.PSObject.Properties['HookAttempts']){$script:launch | Add-Member NoteProperty HookAttempts @{} -Force}
            $script:launch.HookAttempts[$pidStr]=$attempts
            $proc=Get-Process -Id ([int]$script:launch.HookPid) -ErrorAction SilentlyContinue
            if($proc -and $proc.MainWindowHandle -and $attempts -lt 8){
                # Launcher process is still starting up or initializing modules; retry on next tick
            } elseif($proc -and $proc.MainWindowHandle){
                $script:launch.Hooked[$pidStr]=$false
                Write-Panel ('Launcher routing failed: '+$hook.Error+' '+$hook.Output);$script:launch.Phase='Idle'
            } else {
                $script:launch.Hooked[$pidStr]=$false
                Write-Panel ('Launcher process notice: '+$hook.Error+' '+$hook.Output)
            }
        }
        $hook.Dispose();$script:launch.HookJob=$null
    }
    if($script:launch.Phase -eq 'AwaitAccounts' -and !$script:job -and !$script:launch.HookJob){
        $allLaunchers=@(Get-Process hytale-launcher -ErrorAction SilentlyContinue)
        $launchers=@($allLaunchers | Where-Object { $_.MainWindowHandle })
        $unusedLaunchers=@($launchers | Where-Object { !$script:launch.UsedLaunchers.ContainsKey([string]$_.Id) })
        if($unusedLaunchers.Count){$script:launch.OpenAttempts=0}
        foreach($launcher in $launchers){
            $pidStr=[string]$launcher.Id
            $attempts=if($script:launch.PSObject.Properties['HookAttempts'] -and $script:launch.HookAttempts.ContainsKey($pidStr)){$script:launch.HookAttempts[$pidStr]}else{0}
            if(!$script:launch.Hooked.ContainsKey($pidStr) -or ($script:launch.Hooked[$pidStr] -ne $true -and $attempts -lt 8)){
                $script:launch.HookPid=$launcher.Id
                $script:launch.HookJob=[HytaleAssignmentProcess]::new((Join-Path $script:BundleRoot 'HytaleLaunchHost.exe'),$pidStr)
                break
            }
        }
        if(!$script:launch.HookJob){
            $expected=@(Get-SelectedProfiles);$running=@(Get-AccountLaunches)
            $validRunning=@()
            $mismatchedBranch=@()
            $unrouted=@()
            foreach($p in $expected){
                $match=@($running | Where-Object {$_.AccountId -eq $p.AccountId})
                if($match.Count -ge 1){
                    $m=$match[0]
                    if($m.Branch -ne $p.Branch){
                        $mismatchedBranch+=([pscustomobject]@{Name=$p.Name;Running=$m.Branch;Expected=$p.Branch})
                    } elseif([IO.Path]::GetFullPath($m.SourceDir).TrimEnd('\') -ne [IO.Path]::GetFullPath($p.UserData).TrimEnd('\')){
                        $unrouted+=([pscustomobject]@{Name=$p.Name})
                    } elseif($m.Process.MainWindowHandle){
                        $validRunning+=,$m
                    }
                }
            }
            $ready=($validRunning.Count -eq $expected.Count -and $expected.Count -gt 0)
            if($ready){
                Stop-LauncherAutomation;$script:launch.Phase='Attaching';Start-PanelJob Attach
            }elseif($mismatchedBranch.Count){
                $item=$mismatchedBranch[0]
                $message="$($item.Name) is running on '$($item.Running)', but profile expects '$($item.Expected)'. Close the client and select '$($item.Expected)' in launcher."
                if($message -ne $script:launch.LastMessage){$script:launch.LastMessage=$message;Write-Panel $message}
            }elseif($unrouted.Count){
                $item=$unrouted[0]
                $message="$($item.Name) is using the shared folder. Close that client, click Auto, wait for routing ready, then click Play."
                if($message -ne $script:launch.LastMessage){$script:launch.LastMessage=$message;Write-Panel $message}
            }else{
                $missing=@($expected | Where-Object {$_.AccountId -notin @($validRunning.AccountId)})
                # Keep active unused launcher on top and push already-running game clients behind while launching
                foreach($ul in $unusedLaunchers){
                    if($ul.MainWindowHandle){
                        try {
                            [void][HytaleSplitWindow]::ShowWindow($ul.MainWindowHandle, 9)
                            [void][HytaleSplitWindow]::SetWindowPos($ul.MainWindowHandle, [IntPtr](-1), 0, 0, 0, 0, 0x43)
                            [void][HytaleSplitWindow]::SetWindowPos($ul.MainWindowHandle, [IntPtr](-2), 0, 0, 0, 0, 0x43)
                        } catch {}
                    }
                }
                foreach($vr in $validRunning){
                    if($vr.Process.MainWindowHandle){
                        try { [void][HytaleSplitWindow]::SetWindowPos($vr.Process.MainWindowHandle, [IntPtr]1, 0, 0, 0, 0, 0x13) } catch {}
                    }
                }
                # Close any previously used launcher whose game client is now running so it frees the launcher slot
                foreach($usedPid in @($script:launch.UsedLaunchers.Keys)){
                    $accId=$script:launch.UsedLaunchers[$usedPid]
                    if(@($validRunning | Where-Object {$_.AccountId -eq $accId}).Count){
                        $usedProc=Get-Process -Id ([int]$usedPid) -ErrorAction SilentlyContinue
                        if($usedProc){
                            try{[void]$usedProc.CloseMainWindow()}catch{}
                            if(!$usedProc.WaitForExit(150)){try{Stop-Process -Id $usedProc.Id -Force -ErrorAction SilentlyContinue}catch{}}
                        }
                    }
                }
                # Check if the next player needs an official launcher opened
                $target=$missing[0]
                $startingUp=($allLaunchers.Count -gt 0 -and $launchers.Count -eq 0)
                if(!$script:launch.Requested.ContainsKey($target.AccountId) -and !$unusedLaunchers.Count -and !$startingUp -and [DateTime]::UtcNow -gt $script:launch.LastOpen.AddSeconds(3)){
                    if($script:launch.OpenAttempts -ge 6){throw 'The official launcher did not remain open. Open it manually, then retry Auto.'}
                    $script:launch.LastOpen=[DateTime]::UtcNow;$script:launch.OpenAttempts++
                    Write-Panel "Opening official launcher for $($target.Name)..."
                    Open-OfficialLauncher
                }
                Update-LauncherAutomation $missing $launchers
                $message='Waiting for: '+(($missing | ForEach-Object {$_.Name}) -join ', ')+'. In the official launcher, select that account and click Play. Reopen the launcher if it closed.'
                if($message -ne $script:launch.LastMessage){$script:launch.LastMessage=$message;Write-Panel $message}
                if([DateTime]::UtcNow -gt $script:launch.Started.AddMinutes(10)){Stop-LauncherAutomation;$script:launch.Phase='Idle';Write-Panel 'Auto timed out after 10 minutes. Click Auto to retry.'}
            }
        }
    }
 } catch { Stop-LauncherAutomation;$script:launch.Phase='Idle';Write-Panel ('Error: '+$_.Exception.Message) }
}
$timer.Add_Tick({Update-Studio})
Build-PlayerRows
Write-Panel 'Ready. Saved account folders are preserved. Auto setup uses official authenticated launches.'
if(!(Test-Path (Join-Path $script:BundleRoot 'HytaleInputHost.exe'))){Write-Panel 'Input helper is missing or quarantined. New attachments are blocked; review Windows Security Protection history.'}
if(Test-Path (Join-Path $script:BundleRoot 'pending/HytaleInput-v5.dll')){Write-Panel 'Controller update staged: close both games, then reopen the studio to install it.'}
$timer.Start()
$window.Add_PreviewKeyDown({param($s,$e)
    if($script:binding -and $script:binding.TargetRow){
        $t=$script:binding.TargetRow
        $script:binding=$null
        Set-PlayerDevice $t 'KBM'
        Write-Panel ("Keyboard & Mouse assigned to $($t.Profile.Name) and saved.")
    }
})
$workArea = [System.Windows.SystemParameters]::WorkArea
if($workArea.Height -gt 0){
    $targetWidth = [math]::Min(1160, [math]::Max(900, [int]($workArea.Width * 0.85)))
    $targetHeight = [math]::Min(940, [math]::Max(600, [int]($workArea.Height * 0.92)))
    $window.Width = $targetWidth
    $window.Height = $targetHeight
    $window.Left = [math]::Max(0, ($workArea.Width - $targetWidth) / 2 + $workArea.Left)
    $window.Top = [math]::Max(0, ($workArea.Height - $targetHeight) / 2 + $workArea.Top)
}
try{[void]$window.ShowDialog()}finally{
    $timer.Stop();Stop-LauncherAutomation;[DualSenseManager]::Shutdown()
    if($script:job){$script:job.Dispose()}
    if($script:launch.HookJob){$script:launch.HookJob.Dispose()}
}
