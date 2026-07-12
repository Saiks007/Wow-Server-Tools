$script:logPath = Join-Path $env:TEMP 'WowServerControl.log'
"[$([DateTime]::Now.ToString('HH:mm:ss.fff'))] script entered, PSVersion=$($PSVersionTable.PSVersion) User=$env:USERNAME CWD=$(Get-Location)" | Add-Content -Path $script:logPath -ErrorAction SilentlyContinue
try {
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
"[$([DateTime]::Now.ToString('HH:mm:ss.fff'))] assemblies loaded" | Add-Content -Path $script:logPath -ErrorAction SilentlyContinue
} catch {
"[$([DateTime]::Now.ToString('HH:mm:ss.fff'))] Add-Type FAILED: $($_ | Out-String)" | Add-Content -Path $script:logPath -ErrorAction SilentlyContinue
throw
}

# Native C# reader: pumps a TextReader into a ConcurrentQueue on a .NET Task thread.
# This avoids invoking PowerShell scriptblocks from background threads, which crashes
# the process without even entering try/catch.
if (-not ('WowSC.StreamPump' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Collections.Concurrent;
using System.Threading.Tasks;
namespace WowSC {
    public static class StreamPump {
        public static void Start(TextReader reader, ConcurrentQueue<string> queue) {
            Task.Factory.StartNew(() => {
                try {
                    string line;
                    while ((line = reader.ReadLine()) != null) {
                        queue.Enqueue(line);
                    }
                } catch { }
            }, TaskCreationOptions.LongRunning);
        }

        // Runs a command in the background, captures its stdout, enqueues the full text once.
        public static void FetchStdout(string fileName, string args, ConcurrentQueue<string> queue) {
            Task.Factory.StartNew(() => {
                try {
                    var psi = new ProcessStartInfo(fileName, args) {
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        StandardOutputEncoding = Encoding.UTF8,
                        StandardErrorEncoding  = Encoding.UTF8
                    };
                    using (var p = Process.Start(psi)) {
                        string text = p.StandardOutput.ReadToEnd();
                        p.WaitForExit(10000);
                        queue.Enqueue(text ?? "");
                    }
                } catch (Exception ex) {
                    queue.Enqueue("__ERROR__: " + ex.Message);
                }
            });
        }
    }
}
'@ -Language CSharp
}

$script:logPath = Join-Path $env:TEMP 'WowServerControl.log'
function Log-ToFile([string]$msg) {
    try { Add-Content -Path $script:logPath -Value ("[{0}] {1}" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')), $msg) -ErrorAction SilentlyContinue } catch {}
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WoW Server Control (embedded WSL)" Height="660" Width="980"
        WindowStartupLocation="CenterScreen" Background="#1E1E1E">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Grid.Resources>
            <Style TargetType="Button">
                <Setter Property="Height" Value="34"/>
                <Setter Property="Margin" Value="0,3"/>
                <Setter Property="FontSize" Value="12"/>
                <Setter Property="Background" Value="#2D2D30"/>
                <Setter Property="Foreground" Value="#DCDCDC"/>
                <Setter Property="BorderBrush" Value="#3F3F46"/>
                <Setter Property="Cursor" Value="Hand"/>
            </Style>
            <Style TargetType="TextBlock">
                <Setter Property="Foreground" Value="#DCDCDC"/>
            </Style>
            <Style TargetType="TextBox">
                <Setter Property="Background" Value="#0C0C0C"/>
                <Setter Property="Foreground" Value="#D4D4D4"/>
                <Setter Property="BorderBrush" Value="#3F3F46"/>
                <Setter Property="FontFamily" Value="Consolas"/>
                <Setter Property="FontSize" Value="12"/>
                <Setter Property="CaretBrush" Value="#DCDCDC"/>
            </Style>
        </Grid.Resources>

        <TextBlock Grid.Row="0" Text="WoW Server Control (embedded WSL)" FontSize="18" FontWeight="Bold"/>
        <TextBlock Grid.Row="1" Name="txtIp" Text="WSL2 IP: (click 'Get WSL2 IP')" FontSize="12" Foreground="#9CDCFE" Margin="0,2,0,8"/>

        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="250"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                <Grid Margin="0,3">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Button Grid.Column="0" Name="btnStartDocker" Content="Start Docker" Margin="0"/>
                    <Border Grid.Column="1" Name="badgeDocker" Background="#8B1B1B" CornerRadius="3"
                            Margin="6,0,0,0" VerticalAlignment="Center" Padding="8,4" MinWidth="38">
                        <TextBlock Name="txtBadgeDocker" Text="OFF" Foreground="White" FontWeight="Bold"
                                   FontSize="11" HorizontalAlignment="Center"/>
                    </Border>
                </Grid>
                <Button Name="btnGetIp"       Content="Get WSL2 IP"/>

                <Grid Margin="0,3">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Button Grid.Column="0" Name="btnWotLK" Content="Start WotLK Server" Margin="0"/>
                    <Border Grid.Column="1" Name="badgeWotLK" Background="#8B1B1B" CornerRadius="3"
                            Margin="6,0,0,0" VerticalAlignment="Center" Padding="8,4" MinWidth="38">
                        <TextBlock Name="txtBadgeWotLK" Text="OFF" Foreground="White" FontWeight="Bold"
                                   FontSize="11" HorizontalAlignment="Center"/>
                    </Border>
                </Grid>

                <Grid Margin="0,3">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Button Grid.Column="0" Name="btnTBC" Content="Start TBC Server" Margin="0"/>
                    <Border Grid.Column="1" Name="badgeTBC" Background="#8B1B1B" CornerRadius="3"
                            Margin="6,0,0,0" VerticalAlignment="Center" Padding="8,4" MinWidth="38">
                        <TextBlock Name="txtBadgeTBC" Text="OFF" Foreground="White" FontWeight="Bold"
                                   FontSize="11" HorizontalAlignment="Center"/>
                    </Border>
                </Grid>

                <Grid Margin="0,3">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Button Grid.Column="0" Name="btnVanilla" Content="Start Vanilla Server" Margin="0"/>
                    <Border Grid.Column="1" Name="badgeVanilla" Background="#8B1B1B" CornerRadius="3"
                            Margin="6,0,0,0" VerticalAlignment="Center" Padding="8,4" MinWidth="38">
                        <TextBlock Name="txtBadgeVanilla" Text="OFF" Foreground="White" FontWeight="Bold"
                                   FontSize="11" HorizontalAlignment="Center"/>
                    </Border>
                </Grid>

                <Button Name="btnWatchLogs"   Content="Watch Server Start (logs -f)"/>
                <Button Name="btnStop"        Content="Stop WoW Server"/>
                <Button Name="btnStatus"      Content="Check Server Status (docker ps)"/>
                <Button Name="btnGMConsole"   Content="Open GM Console (attach)"/>
                <Separator Margin="0,10"/>
                <Button Name="btnCancel"      Content="Cancel / Restart Shell" Background="#5A2A2A"/>
                <Button Name="btnClear"       Content="Clear Output"/>
            </StackPanel>

            <Grid Grid.Column="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBox Grid.Row="0" Name="txtOutput" IsReadOnly="True"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                         TextWrapping="NoWrap" AcceptsReturn="True"/>
                <Grid Grid.Row="1" Margin="0,6,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="$ " Foreground="#B5CEA8" VerticalAlignment="Center" FontFamily="Consolas" FontSize="13" Margin="2,0,4,0"/>
                    <TextBox Grid.Column="1" Name="txtInput" Height="26" VerticalContentAlignment="Center" Foreground="#DCDCDC"/>
                    <Button Grid.Column="2" Name="btnSend" Content="Send" Width="70" Height="26" Margin="6,0,0,0"/>
                </Grid>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:window = [Windows.Markup.XamlReader]::Load($reader)

$script:txtOutput = $script:window.FindName("txtOutput")
$script:txtInput  = $script:window.FindName("txtInput")
$script:txtIp     = $script:window.FindName("txtIp")
$btnStartDocker   = $script:window.FindName("btnStartDocker")
$btnGetIp         = $script:window.FindName("btnGetIp")
$btnWotLK         = $script:window.FindName("btnWotLK")
$btnTBC           = $script:window.FindName("btnTBC")
$btnVanilla       = $script:window.FindName("btnVanilla")
$btnWatchLogs     = $script:window.FindName("btnWatchLogs")
$btnStop          = $script:window.FindName("btnStop")
$btnStatus        = $script:window.FindName("btnStatus")
$btnGMConsole     = $script:window.FindName("btnGMConsole")
$btnCancel        = $script:window.FindName("btnCancel")
$btnClear         = $script:window.FindName("btnClear")
$btnSend          = $script:window.FindName("btnSend")

$script:badgeDocker     = $script:window.FindName("badgeDocker")
$script:txtBadgeDocker  = $script:window.FindName("txtBadgeDocker")
$script:badgeWotLK      = $script:window.FindName("badgeWotLK")
$script:badgeTBC        = $script:window.FindName("badgeTBC")
$script:badgeVanilla    = $script:window.FindName("badgeVanilla")
$script:txtBadgeWotLK   = $script:window.FindName("txtBadgeWotLK")
$script:txtBadgeTBC     = $script:window.FindName("txtBadgeTBC")
$script:txtBadgeVanilla = $script:window.FindName("txtBadgeVanilla")

$script:onBrush  = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2E7D32'))
$script:offBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#8B1B1B'))

$script:proc = $null
$script:sudoPassword = $null
$script:outputQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$script:statusQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$script:shellExitReported = $true

function Set-Badge {
    param($Border, $TextBlk, [bool]$IsOn)
    if ($null -eq $Border -or $null -eq $TextBlk) { return }
    if ($IsOn) {
        $Border.Background = $script:onBrush
        $TextBlk.Text = "ON"
    } else {
        $Border.Background = $script:offBrush
        $TextBlk.Text = "OFF"
    }
}

function Trigger-StatusCheck {
    try {
        $probe = 'docker info >/dev/null 2>&1 && echo __DOCKER_ON__ || echo __DOCKER_OFF__; docker compose ls 2>/dev/null'
        [WowSC.StreamPump]::FetchStdout('wsl.exe', "-e bash -c `"$probe`"", $script:statusQueue)
    } catch {
        Log-ToFile ("Trigger-StatusCheck: " + ($_ | Out-String))
    }
}

function Enqueue-Line {
    param([string]$Line)
    if ($null -eq $Line) { return }
    $script:outputQueue.Enqueue([string]$Line)
}

function Log-Line { param([string]$Msg) Enqueue-Line -Line $Msg }

$script:drainTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:drainTimer.Interval = [TimeSpan]::FromMilliseconds(60)
$script:drainTimer.Add_Tick({
    try {
        $sb = New-Object System.Text.StringBuilder
        $line = ""
        $count = 0
        $any = $false
        while ($count -lt 500 -and $script:outputQueue.TryDequeue([ref]$line)) {
            [void]$sb.AppendLine($line)
            $any = $true
            $count++
        }
        if ($any) {
            $script:txtOutput.AppendText($sb.ToString())
            $script:txtOutput.ScrollToEnd()
        }
        # Poll bash's exit state (avoids using the Exited event on a background thread).
        if ($script:proc -and $script:proc.HasExited -and -not $script:shellExitReported) {
            $script:shellExitReported = $true
            $script:txtOutput.AppendText("[shell exited]`r`n")
            $script:txtOutput.ScrollToEnd()
        }
        # Drain status queue and update badges from the most recent result.
        $statusText = ""
        $latest = $null
        while ($script:statusQueue.TryDequeue([ref]$statusText)) { $latest = $statusText }
        if ($null -ne $latest -and -not $latest.StartsWith("__ERROR__")) {
            Set-Badge $script:badgeDocker  $script:txtBadgeDocker  ($latest -match '__DOCKER_ON__')
            Set-Badge $script:badgeWotLK   $script:txtBadgeWotLK   ($latest -match 'wow-server-playerbots')
            Set-Badge $script:badgeTBC     $script:txtBadgeTBC     ($latest -match 'wow-tbc-server')
            Set-Badge $script:badgeVanilla $script:txtBadgeVanilla ($latest -match 'wow-vanilla-server')
        }
    } catch {
        Log-ToFile ("drainTimer error: " + ($_ | Out-String))
    }
})

function Start-BashProcess {
    try {
        if ($script:proc -and -not $script:proc.HasExited) { return }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = "wsl.exe"
        $psi.Arguments = "-e bash -l"
        $psi.RedirectStandardInput  = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
        try { $psi.StandardInputEncoding = [System.Text.Encoding]::UTF8 } catch {}

        $script:proc = New-Object System.Diagnostics.Process
        $script:proc.StartInfo = $psi

        [void]$script:proc.Start()
        try { $script:proc.StandardInput.NewLine = "`n" } catch {}

        # Pump stdout and stderr from native .NET tasks straight into the queue.
        [WowSC.StreamPump]::Start($script:proc.StandardOutput, $script:outputQueue)
        [WowSC.StreamPump]::Start($script:proc.StandardError,  $script:outputQueue)

        $script:shellExitReported = $false
    } catch {
        Log-ToFile ("Start-BashProcess: " + ($_ | Out-String))
        Enqueue-Line ("[ERROR starting bash: " + $_.Exception.Message + "]")
    }
}

function Send-Command {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$Silent,
        [string]$DisplayAs
    )
    try {
        if (-not $script:proc -or $script:proc.HasExited) {
            Log-Line "[shell not running - starting a fresh one]"
            Start-BashProcess
            Start-Sleep -Milliseconds 200
        }
        if (-not $Silent) {
            $shown = if ([string]::IsNullOrEmpty($DisplayAs)) { $Command } else { $DisplayAs }
            Log-Line ("> " + $shown)
        }
        $script:proc.StandardInput.WriteLine($Command)
        $script:proc.StandardInput.Flush()
    } catch {
        Log-ToFile ("Send-Command: " + ($_ | Out-String))
        Enqueue-Line ("[ERROR sending command: " + $_.Exception.Message + "]")
    }
}

function Prompt-Password {
    param([string]$Title = "Password", [string]$Msg = "Enter password:")
    try {
        [xml]$px = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" Height="170" Width="360"
        WindowStartupLocation="CenterOwner" WindowStyle="ToolWindow"
        Background="#1E1E1E" ShowInTaskbar="False">
  <StackPanel Margin="14">
    <TextBlock Text="$Msg" Foreground="#DCDCDC" Margin="0,0,0,8"/>
    <PasswordBox Name="pb" Height="26" Background="#0C0C0C" Foreground="#DCDCDC" BorderBrush="#3F3F46"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button Name="ok" Content="OK" Width="72" Height="26" Margin="0,0,6,0" IsDefault="True"
              Background="#2D2D30" Foreground="#DCDCDC" BorderBrush="#3F3F46"/>
      <Button Name="cancel" Content="Cancel" Width="72" Height="26" IsCancel="True"
              Background="#2D2D30" Foreground="#DCDCDC" BorderBrush="#3F3F46"/>
    </StackPanel>
  </StackPanel>
</Window>
"@
        $r  = New-Object System.Xml.XmlNodeReader $px
        $d  = [Windows.Markup.XamlReader]::Load($r)
        $pb = $d.FindName("pb")
        $ok = $d.FindName("ok")
        $cn = $d.FindName("cancel")
        $script:pwResult = $null
        $ok.Add_Click({ $script:pwResult = $pb.Password; $d.DialogResult = $true })
        $cn.Add_Click({ $d.DialogResult = $false })
        $d.Owner = $script:window
        $d.Add_Loaded({ try { $pb.Focus() | Out-Null } catch {} })
        [void]$d.ShowDialog()
        return $script:pwResult
    } catch {
        Log-ToFile ("Prompt-Password: " + ($_ | Out-String))
        return $null
    }
}

function Wrap-Handler {
    param([string]$Name, [scriptblock]$Body)
    $wrapped = [scriptblock]::Create(@"
try { & { $($Body.ToString()) } } catch {
    Log-ToFile ('$Name' + ': ' + (`$_ | Out-String))
    Enqueue-Line ('[ERROR in $Name' + ': ' + `$_.Exception.Message + ']')
}
"@)
    return $wrapped
}

# ---- button handlers ----

$btnStartDocker.Add_Click( (Wrap-Handler 'btnStartDocker' {
    if ([string]::IsNullOrEmpty($script:sudoPassword)) {
        $pw = Prompt-Password "sudo password" "Enter sudo password (used to start docker):"
        if ([string]::IsNullOrEmpty($pw)) { return }
        $script:sudoPassword = $pw
    }
    $pwEsc = $script:sudoPassword -replace "'", "'\''"
    Send-Command -Silent -Command "echo '$pwEsc' | sudo -S -k service docker start" -DisplayAs "sudo service docker start"
    Log-Line "> sudo service docker start   (password sent from secure prompt)"
    Schedule-StatusCheck 3000
}) )

$btnGetIp.Add_Click( (Wrap-Handler 'btnGetIp' {
    Send-Command "hostname -I | awk '{print `$1}'"
    try {
        $raw = & wsl.exe -e bash -lc "hostname -I | awk '{print `$1}'" 2>$null
        $ip = ($raw -join "").Trim()
        if ($ip) {
            $script:txtIp.Text = "WSL2 IP: $ip  (copied to clipboard)"
            [System.Windows.Forms.Clipboard]::SetText($ip)
        }
    } catch {}
}) )

$btnWotLK.Add_Click(   (Wrap-Handler 'btnWotLK'   { Send-Command "cd ~/wow-server-playerbots && docker compose up -d"; Schedule-StatusCheck 4000 }) )
$btnTBC.Add_Click(     (Wrap-Handler 'btnTBC'     { Send-Command "cd ~/wow-tbc-server && docker compose up -d";       Schedule-StatusCheck 4000 }) )
$btnVanilla.Add_Click( (Wrap-Handler 'btnVanilla' { Send-Command "cd ~/wow-vanilla-server && docker compose up -d";   Schedule-StatusCheck 4000 }) )

$btnWatchLogs.Add_Click( (Wrap-Handler 'btnWatchLogs' {
    Send-Command "docker logs -f `$(docker ps --format '{{.Names}}' | grep -i 'worldserver\|mangosd' | head -1)"
    Log-Line "[tip: click 'Cancel / Restart Shell' to stop watching]"
}) )

$btnStop.Add_Click(   (Wrap-Handler 'btnStop'   { Send-Command "cd ~/wow-server-playerbots && docker compose down"; Schedule-StatusCheck 3000 }) )
$btnStatus.Add_Click( (Wrap-Handler 'btnStatus' { Send-Command "docker ps" }) )

$btnGMConsole.Add_Click( (Wrap-Handler 'btnGMConsole' {
    Log-Line "[GM console needs a real TTY - opening a new terminal window]"
    Log-Line "[in that window: type GM commands, detach with Ctrl+P then Ctrl+Q]"
    $inner = "docker attach `$(docker ps --format '{{.Names}}' | grep -i 'worldserver\|mangosd' | head -1)"
    $escaped = $inner -replace '"', '\"'
    $cmdArgs = "/k title GM Console && wsl.exe -e bash -lic `"$escaped`""
    Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs
}) )

$btnCancel.Add_Click( (Wrap-Handler 'btnCancel' {
    if ($script:proc -and -not $script:proc.HasExited) {
        Log-Line "[killing shell...]"
        try { $script:proc.Kill() } catch {}
    }
    Start-BashProcess
    Log-Line "[shell restarted]"
}) )

$btnClear.Add_Click( (Wrap-Handler 'btnClear' { $script:txtOutput.Clear() }) )

$script:sendInputAction = {
    $cmd = $script:txtInput.Text
    if ([string]::IsNullOrWhiteSpace($cmd)) { return }
    Send-Command -Command $cmd
    $script:txtInput.Clear()
}
$btnSend.Add_Click( (Wrap-Handler 'btnSend' { & $script:sendInputAction }) )

$script:txtInput.Add_KeyDown( (Wrap-Handler 'txtInputKeyDown' {
    if ($args[1].Key -eq [System.Windows.Input.Key]::Return -or $args[1].Key -eq [System.Windows.Input.Key]::Enter) {
        $args[1].Handled = $true
        & $script:sendInputAction
    }
}) )

$script:window.Add_Closed({
    try {
        if ($script:drainTimer)        { $script:drainTimer.Stop() }
        if ($script:statusPollTimer)   { $script:statusPollTimer.Stop() }
        if ($script:pendingCheckTimer) { $script:pendingCheckTimer.Stop() }
        if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill() }
        if ($script:notifyIcon) { $script:notifyIcon.Visible = $false; $script:notifyIcon.Dispose() }
    } catch {}
    try { if ($script:app) { $script:app.Shutdown() } } catch {}
})

# ---- App icon (used by both the WPF window title bar / taskbar and the tray icon) ----
$script:iconPath = Join-Path $PSScriptRoot 'icon.png'
if (Test-Path $script:iconPath) {
    try {
        # WPF window / taskbar icon
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.UriSource = New-Object System.Uri ($script:iconPath, [System.UriKind]::Absolute)
        $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bi.EndInit()
        $bi.Freeze()
        $script:window.Icon = $bi
    } catch { Log-ToFile ("window icon: " + ($_ | Out-String)) }

    try {
        # Tray icon: convert PNG -> Bitmap -> HICON -> Icon
        $script:appBitmap = New-Object System.Drawing.Bitmap $script:iconPath
        $script:appIcon   = [System.Drawing.Icon]::FromHandle($script:appBitmap.GetHicon())
    } catch { Log-ToFile ("tray icon load: " + ($_ | Out-String)) }
}

# ---- Tray icon: minimize hides window, tray shows; double-click restores ----
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
if ($script:appIcon) { $script:notifyIcon.Icon = $script:appIcon }
else                 { $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application }
$script:notifyIcon.Text = "WoW Server Control"
$script:notifyIcon.Visible = $false
$script:balloonShown = $false

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayShow = New-Object System.Windows.Forms.ToolStripMenuItem
$trayShow.Text = "Show"
$trayExit = New-Object System.Windows.Forms.ToolStripMenuItem
$trayExit.Text = "Exit"
[void]$trayMenu.Items.Add($trayShow)
[void]$trayMenu.Items.Add($trayExit)
$script:notifyIcon.ContextMenuStrip = $trayMenu

function Show-MainWindow {
    try {
        $script:window.Show()
        if ($script:window.WindowState -eq [System.Windows.WindowState]::Minimized) {
            $script:window.WindowState = [System.Windows.WindowState]::Normal
        }
        [void]$script:window.Activate()
        $script:notifyIcon.Visible = $false
    } catch { Log-ToFile ("Show-MainWindow: " + ($_ | Out-String)) }
}

function Hide-ToTray {
    try {
        $script:window.Hide()
        $script:notifyIcon.Visible = $true
        if (-not $script:balloonShown) {
            $script:balloonShown = $true
            $script:notifyIcon.ShowBalloonTip(3000, "WoW Server Control",
                "Minimized to tray. Double-click the icon to restore.",
                [System.Windows.Forms.ToolTipIcon]::Info)
        }
    } catch { Log-ToFile ("Hide-ToTray: " + ($_ | Out-String)) }
}

function Exit-App {
    try { $script:notifyIcon.Visible = $false; $script:notifyIcon.Dispose() } catch {}
    try { $script:window.Close() } catch {}
    try { if ($script:app) { $script:app.Shutdown() } } catch {}
}

$trayShow.add_Click({ Show-MainWindow })
$trayExit.add_Click({ Exit-App })
$script:notifyIcon.add_DoubleClick({ Show-MainWindow })

$script:window.Add_StateChanged({
    try {
        if ($script:window.WindowState -eq [System.Windows.WindowState]::Minimized) {
            Hide-ToTray
        }
    } catch { Log-ToFile ("StateChanged: " + ($_ | Out-String)) }
})

$script:window.Dispatcher.add_UnhandledException({
    param($theSender, $e)
    try {
        Log-ToFile ("UnhandledException: " + ($e.Exception | Out-String))
        $script:outputQueue.Enqueue("[UNHANDLED: " + $e.Exception.Message + "]")
        $e.Handled = $true
    } catch {}
})

# Status polling: every 5s, kick off a background docker compose ls; the drain timer
# picks up the result from $script:statusQueue and updates the badges.
$script:statusPollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:statusPollTimer.Interval = [TimeSpan]::FromSeconds(5)
$script:statusPollTimer.Add_Tick({ try { Trigger-StatusCheck } catch {} })

# One-shot delayed refresh after clicking a start/stop button.
$script:pendingCheckTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pendingCheckTimer.Add_Tick({
    try { $script:pendingCheckTimer.Stop(); Trigger-StatusCheck } catch {}
})
function Schedule-StatusCheck([int]$ms) {
    try {
        $script:pendingCheckTimer.Stop()
        $script:pendingCheckTimer.Interval = [TimeSpan]::FromMilliseconds($ms)
        $script:pendingCheckTimer.Start()
    } catch {}
}

Log-ToFile "=== app starting ==="
Start-BashProcess
$script:drainTimer.Start()
$script:statusPollTimer.Start()
Trigger-StatusCheck
Log-Line "[embedded WSL shell ready. Click a button, or type below and press Enter.]"

$script:app = New-Object System.Windows.Application
$script:app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

# When launched via wscript.exe (vbHide=0), the process inherits STARTF_USESHOWWINDOW=SW_HIDE
# which suppresses the first ShowWindow call. Force the window visible after render, and
# briefly bring it to the front so it isn't hidden behind other windows.
$script:window.Add_ContentRendered({
    try {
        $script:window.Visibility = [System.Windows.Visibility]::Visible
        $script:window.WindowState = [System.Windows.WindowState]::Normal
        $script:window.Show()
        $script:window.Topmost = $true
        $script:window.Topmost = $false
        [void]$script:window.Activate()
    } catch { Log-ToFile ("ContentRendered force-show: " + ($_ | Out-String)) }
})

$script:app.Run($script:window) | Out-Null
