param([string]$MetaTraderDirectory = (Join-Path $env:ProgramFiles 'MetaTrader 5'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Get-Process terminal64 -ErrorAction SilentlyContinue) { throw 'Close MetaTrader 5 before running strategy tests.' }
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$terminalRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
$data = @(Get-ChildItem -LiteralPath $terminalRoot -Directory | Where-Object {
    $origin = Join-Path $_.FullName 'origin.txt'
    (Test-Path -LiteralPath $origin) -and ((Get-Content -LiteralPath $origin -Raw).Trim() -eq $MetaTraderDirectory.TrimEnd('\'))
})
if ($data.Count -ne 1) { throw 'Could not locate the desktop MT5 data folder.' }
$scripts = Join-Path $data[0].FullName 'MQL5\Scripts'
$token = [guid]::NewGuid().ToString('N')
$temp = Join-Path $env:TEMP "mercatus-strategies-$token"
New-Item -ItemType Directory -Path $temp | Out-Null
$installed = @()

function Invoke-TestProcess($file, $arguments) {
    $process = Start-Process -FilePath $file -ArgumentList $arguments -WindowStyle Hidden -PassThru
    try {
        if (!$process.WaitForExit(120000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Timed out: $file"
        }
        return $process.ExitCode
    } finally { $process.Dispose() }
}

try {
    Copy-Item -LiteralPath (Join-Path $project 'experts'),(Join-Path $project 'strategies') -Destination $temp -Recurse
    New-Item -ItemType Directory -Path (Join-Path $temp 'tests') | Out-Null
    Copy-Item -LiteralPath $PSScriptRoot -Destination (Join-Path $temp 'tests\Strategies') -Recurse
    $tests = @(Get-ChildItem -LiteralPath (Join-Path $temp 'tests\Strategies') -Filter 'Test_*.mq5' -File)
    if (!$tests.Count) { throw 'No strategy tests found.' }
    foreach ($test in $tests) {
        $code = Invoke-TestProcess (Join-Path $MetaTraderDirectory 'MetaEditor64.exe') @(('/compile:"' + $test.FullName + '"'), '/log')
        $log = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($test.FullName, '.log')) -Raw
        if ($code -notin 0,1 -or $log -notmatch 'Result: 0 errors, 0 warnings') { throw $log }
        $name = "$($test.BaseName)_$token"
        $binary = Join-Path $scripts "$name.ex5"
        $installed += $binary
        Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($test.FullName, '.ex5')) -Destination $binary
        $config = Join-Path $temp 'run.ini'
        @"
[Experts]
Enabled=0
AllowLiveTrading=0
AllowDllImport=0
[StartUp]
Symbol=EURUSD
Period=H1
Script=$name.ex5
ShutdownTerminal=1
"@ | Set-Content -LiteralPath $config -Encoding ASCII
        $code = Invoke-TestProcess (Join-Path $MetaTraderDirectory 'terminal64.exe') @(('/config:"' + $config + '"'))
        $logs = Join-Path $data[0].FullName 'MQL5\Logs'
        $marker = 'Strategy test: ' + $test.BaseName.Substring(5) + ' PASS'
        $pattern = [regex]::Escape($name) + '.*' + [regex]::Escape($marker)
        if ($code -ne 0 -or !(Get-ChildItem -LiteralPath $logs -Filter '*.log' -File | Select-String -Pattern $pattern -Quiet)) {
            throw "$($test.BaseName) failed. See the MT5 Experts log."
        }
        Write-Output $marker
    }
} finally {
    foreach ($binary in $installed) { Remove-Item -LiteralPath $binary -ErrorAction SilentlyContinue }
    $resolved = (Resolve-Path -LiteralPath $temp).ProviderPath
    $tempRoot = (Resolve-Path -LiteralPath $env:TEMP).ProviderPath.TrimEnd('\') + '\'
    if ($resolved -ne (Join-Path $tempRoot "mercatus-strategies-$token")) { throw 'Unexpected test workspace.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
