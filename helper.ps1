param(
    [int]$GamePid,
    [string]$Dir
)
$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$propType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($op, [Type]$type) {
    $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
    [void]$task.Wait(5000)
    $task.Result
}

function Clean([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '[\r\n=]', ' ').Trim()
}

$stateFile = Join-Path $Dir 'state.txt'
$stateTmp = Join-Path $Dir 'state.tmp'
$cmdFile = Join-Path $Dir 'cmd.txt'
$utf8 = New-Object System.Text.UTF8Encoding($false)

$mgr = Await ($mgrType::RequestAsync()) $mgrType

while ($true) {
    if (-not (Get-Process -Id $GamePid)) { break }

    $session = $null
    foreach ($s in $mgr.GetSessions()) {
        if ($s.SourceAppUserModelId -match 'spotify') { $session = $s; break }
    }

    if (Test-Path $cmdFile) {
        $c = (Get-Content $cmdFile -Raw).Trim()
        Remove-Item $cmdFile -Force
        if ($session) {
            switch ($c) {
                'next'   { [void](Await $session.TrySkipNextAsync() ([bool])) }
                'prev'   { [void](Await $session.TrySkipPreviousAsync() ([bool])) }
                'toggle' { [void](Await $session.TryTogglePlayPauseAsync() ([bool])) }
            }
        }
    }

    $status = 'none'; $title = ''; $artist = ''; $app = ''; $pos = 0; $dur = 0
    if ($session) {
        $app = Clean $session.SourceAppUserModelId
        $props = Await ($session.TryGetMediaPropertiesAsync()) $propType
        if ($props) { $title = Clean $props.Title; $artist = Clean $props.Artist }
        $info = $session.GetPlaybackInfo()
        $playing = ($info.PlaybackStatus -eq 'Playing')
        $status = if ($playing) { 'playing' } else { 'paused' }
        $tl = $session.GetTimelineProperties()
        if ($tl) {
            $pos = $tl.Position.TotalSeconds
            $dur = $tl.EndTime.TotalSeconds
            if ($playing) { $pos += ([DateTimeOffset]::Now - $tl.LastUpdatedTime).TotalSeconds }
            if ($dur -gt 0 -and $pos -gt $dur) { $pos = $dur }
            if ($pos -lt 0) { $pos = 0 }
        }
    }

    $text = "ts=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())`nstatus=$status`napp=$app`ntitle=$title`nartist=$artist`npos=$([math]::Round($pos,1))`ndur=$([math]::Round($dur,1))`n"
    [System.IO.File]::WriteAllText($stateTmp, $text, $utf8)
    Move-Item $stateTmp $stateFile -Force

    Start-Sleep -Milliseconds 250
}
