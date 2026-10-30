# 刷课控制台：把专用浏览器藏在屏幕外，只留这个小窗口显示状态 / 进度 / 插件。
param([switch]$NoAutoStart)

$ErrorActionPreference = 'Stop'
$Dir  = $PSScriptRoot
$Port = 9222

# 只允许一个控制台实例
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ChaoxingBrushConsole', [ref]$createdNew)
if (-not $createdNew) { exit }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;

public static class CdpEval {
    public static string Eval(string wsUrl, string expr, int timeoutMs) {
        var cts = new CancellationTokenSource(timeoutMs);
        using (var ws = new ClientWebSocket()) {
            ws.ConnectAsync(new Uri(wsUrl), cts.Token).Wait(cts.Token);
            string msg = "{\"id\":1,\"method\":\"Runtime.evaluate\",\"params\":{\"expression\":" + JsonString(expr) + ",\"returnByValue\":true}}";
            var bytes = Encoding.UTF8.GetBytes(msg);
            ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, cts.Token).Wait(cts.Token);
            var buf = new byte[65536];
            var sb = new StringBuilder();
            while (true) {
                var res = ws.ReceiveAsync(new ArraySegment<byte>(buf), cts.Token).Result;
                sb.Append(Encoding.UTF8.GetString(buf, 0, res.Count));
                if (res.EndOfMessage) break;
            }
            return sb.ToString();
        }
    }

    static string JsonString(string s) {
        var sb = new StringBuilder("\"");
        foreach (char c in s) {
            switch (c) {
                case '\\': sb.Append("\\\\"); break;
                case '"':  sb.Append("\\\""); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 32) sb.Append("\\u" + ((int)c).ToString("x4"));
                    else sb.Append(c);
                    break;
            }
        }
        sb.Append("\"");
        return sb.ToString();
    }
}
"@

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="360" Height="268" WindowStyle="None" AllowsTransparency="False"
        Background="#181B22" Topmost="True" ResizeMode="NoResize"
        WindowStartupLocation="Manual" ShowInTaskbar="True" Title="刷课控制台">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#E9ECF2"/>
      <Setter Property="Background" Value="#3A3F4B"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="0,6"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#4A5160"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>
  <Border CornerRadius="12" Background="#F0181B22" BorderBrush="#2A2F3A" BorderThickness="1" Padding="14">
    <StackPanel>
      <Grid x:Name="DragArea" Background="Transparent">
        <TextBlock Text="刷课控制台" Foreground="#E9ECF2" FontSize="14" FontWeight="Bold"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="MinBtn" Text="—" Foreground="#8F97A6" FontSize="13"
                     Cursor="Hand" Margin="0,0,14,0" ToolTip="最小化到任务栏"/>
          <TextBlock x:Name="CloseBtn" Text="✕" Foreground="#8F97A6" FontSize="13"
                     Cursor="Hand" ToolTip="关闭控制台（后台刷课不受影响）"/>
        </StackPanel>
      </Grid>

      <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
        <Ellipse x:Name="Dot" Width="8" Height="8" Fill="#8F97A6" VerticalAlignment="Center"/>
        <TextBlock x:Name="StateText" Text="正在连接…" Foreground="#B9C0CC"
                   Margin="8,0,0,0" FontSize="12"/>
      </StackPanel>

      <TextBlock x:Name="CourseText" Text="—" Foreground="#E9ECF2" Margin="0,8,0,0"
                 FontSize="12" TextTrimming="CharacterEllipsis"/>

      <ProgressBar x:Name="Bar" Height="6" Margin="0,10,0,4" Minimum="0" Maximum="100"
                   Value="0" Background="#33363F" Foreground="#3DDC84" BorderThickness="0"/>

      <Grid>
        <TextBlock x:Name="ProgText" Text="0 / 0 章" Foreground="#B9C0CC" FontSize="12"/>
        <TextBlock x:Name="PointText" Text="剩余任务点 0" Foreground="#FFCF5C" FontSize="12"
                   HorizontalAlignment="Right"/>
      </Grid>

      <TextBlock x:Name="PluginText" Text="刷课插件：检测中…" Foreground="#8F97A6"
                 Margin="0,8,0,0" FontSize="11" TextTrimming="CharacterEllipsis"/>

      <Grid Margin="0,12,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/>
        </Grid.ColumnDefinitions>
        <Button x:Name="ShowBtn" Content="显示窗口" Grid.Column="0" Margin="0,0,4,0"/>
        <Button x:Name="HideBtn" Content="隐藏窗口" Grid.Column="1" Margin="4,0,4,0"/>
        <Button x:Name="StartBtn" Content="启动刷课" Grid.Column="2" Margin="4,0,0,0"
                Background="#2F7CF6"/>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$win.Left = $wa.Right  - $win.Width  - 24
$win.Top  = $wa.Bottom - $win.Height - 24

$dot     = $win.FindName('Dot')
$state   = $win.FindName('StateText')
$course  = $win.FindName('CourseText')
$bar     = $win.FindName('Bar')
$prog    = $win.FindName('ProgText')
$points  = $win.FindName('PointText')
$plugin  = $win.FindName('PluginText')
$close   = $win.FindName('CloseBtn')
$min     = $win.FindName('MinBtn')
$drag    = $win.FindName('DragArea')
$showBtn = $win.FindName('ShowBtn')
$hideBtn = $win.FindName('HideBtn')
$startBtn= $win.FindName('StartBtn')

$drag.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$close.Add_MouseLeftButtonDown({ $win.Close() })
$min.Add_MouseLeftButtonDown({ $win.WindowState = [System.Windows.WindowState]::Minimized })

function Invoke-PSFile([string]$file, [string[]]$extra) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (Join-Path $Dir $file)) + $extra
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden | Out-Null
}

function Show-Browser { Invoke-PSFile 'show-window.ps1' @('-X', '100', '-Y', '80', '-W', '1100', '-H', '900') }
function Hide-Browser { Invoke-PSFile 'show-window.ps1' @('-X', '-2000', '-Y', '-2000', '-W', '1100', '-H', '900') }
function Start-Brush  { Invoke-PSFile 'start-brush.ps1' @('-Hidden') }

$showBtn.Add_Click({ Show-Browser })
$hideBtn.Add_Click({ Hide-Browser })
$startBtn.Add_Click({ Start-Brush })

function Get-PageTarget {
    try {
        $tabs = Invoke-RestMethod "http://127.0.0.1:$Port/json/list" -TimeoutSec 1
    } catch {
        return $null
    }
    $pages = @($tabs | Where-Object { $_.type -eq 'page' })
    if ($pages.Count -eq 0) { return $null }
    $course = $pages | Where-Object { $_.url -match 'studentstudy' } | Select-Object -First 1
    if ($course) { return $course }
    return $pages | Select-Object -First 1
}

$expr = @'
(()=>{
  const href = location.href;
  if (/passport|login/i.test(href) || (document.title || '').indexOf('登录') >= 0) {
    return JSON.stringify({ kind: 'login' });
  }
  const cid = (href.match(/chapterId=(\d+)/) || [])[1] || '';
  const leaves = [...document.querySelectorAll('.posCatalog_select')].filter(e => e.querySelector('.posCatalog_name'));
  let done = 0, pend = 0, pts = 0;
  leaves.forEach(e => {
    const t = ((e.querySelector('.prevHoverTips') || {}).textContent || '').trim();
    if (!t) return;
    if (t.indexOf('已完成') >= 0) { done++; return; }
    pend++;
    const m = t.match(/(\d+)\s*个/);
    pts += m ? Number(m[1]) : 1;
  });
  let chapter = '';
  if (cid) {
    for (const e of leaves) {
      const s = e.querySelector('.posCatalog_name');
      if ((s.getAttribute('onclick') || '').indexOf("'" + cid + "'") >= 0) {
        chapter = (s.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 30);
        break;
      }
    }
  }
  const text = document.body ? document.body.innerText : '';
  let st = '空闲';
  if (text.indexOf('等待手动提交') >= 0) st = '等待手动提交';
  else if (text.indexOf('正在完成') >= 0 || text.indexOf('即将开始做作业') >= 0) st = '答题中';
  else if (leaves.length) st = '运行中';
  const plugin = !!document.getElementById('csbutton');
  return JSON.stringify({ kind: 'course', cid, done, pend, pts, total: done + pend, chapter, state: st, plugin });
})()
'@

$script:loginShown = $false

function Update-Status {
    $target = Get-PageTarget
    if (-not $target) {
        $dot.Fill = [System.Windows.Media.Brushes]::Gray
        $state.Text = '浏览器未启动'
        $course.Text = '点右下角「启动刷课」，浏览器会在后台打开'
        $prog.Text = '0 / 0 章'
        $points.Text = '剩余任务点 0'
        $bar.Value = 0
        $plugin.Text = '刷课插件：—'
        return
    }

    try {
        $raw = [CdpEval]::Eval($target.webSocketDebuggerUrl, $expr, 1500)
        $obj = $raw | ConvertFrom-Json
        $value = $obj.result.result.value
        if (-not $value) { throw 'empty' }
        $d = $value | ConvertFrom-Json
    } catch {
        $dot.Fill = [System.Windows.Media.Brushes]::Gray
        $state.Text = '页面读取失败'
        return
    }

    if ($d.kind -eq 'login') {
        $dot.Fill = [System.Windows.Media.Brushes]::Goldenrod
        $state.Text = '需要登录（已调出窗口）'
        $course.Text = '请在弹出的浏览器里扫码登录学习通'
        $prog.Text = '0 / 0 章'
        $points.Text = '剩余任务点 0'
        $bar.Value = 0
        $plugin.Text = '刷课插件：等待登录'
        if (-not $script:loginShown) {
            $script:loginShown = $true
            Show-Browser
        }
        return
    }

    $script:loginShown = $false
    $ratio = 0
    if ($d.total -gt 0) { $ratio = [math]::Round($d.done / $d.total * 100) }
    $bar.Value = $ratio
    $doneText = if ($d.chapter) { $d.chapter } else { '课程页' }
    $course.Text = $doneText
    $prog.Text = "$($d.done) / $($d.total) 章"
    $points.Text = "剩余任务点 $($d.pts)"
    $state.Text = $d.state
    if ($d.state -eq '答题中' -or $d.state -eq '运行中') {
        $dot.Fill = [System.Windows.Media.Brushes]::LimeGreen
    } elseif ($d.state -eq '等待手动提交') {
        $dot.Fill = [System.Windows.Media.Brushes]::Goldenrod
    } else {
        $dot.Fill = [System.Windows.Media.Brushes]::Gray
    }
    if ($d.plugin) {
        $plugin.Text = '刷课插件：超星学习通满分助手 · 已加载'
    } else {
        $plugin.Text = '刷课插件：未检测到（请先安装）'
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Update-Status })
$timer.Start()

$win.Add_Loaded({
    Update-Status
    if (-not $NoAutoStart) {
        $t = Get-PageTarget
        if (-not $t) { Start-Brush }
    }
})

[void]$win.ShowDialog()
