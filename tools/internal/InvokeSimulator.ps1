param(
    [string]$MetaTraderDirectory = (Join-Path $env:ProgramFiles 'MetaTrader 5'),
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 90,
    [string]$TerminalDataDirectory,
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$Strategy = 'MovingAverage',
    [Parameter(Mandatory)][string]$Config,
    [switch]$FixedParameters,
    [string]$Schedule,
    [string]$SetupScript,
    [ValidateRange(0.00000001, 1.0)][double]$DrawdownLimit = 0.15,
    [ValidatePattern('^1:[1-9]\d*$')][string]$Leverage = '1:100'
)

Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GetClosedTradeCount.ps1')
. (Join-Path $PSScriptRoot 'WriteEquityChart.ps1')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$strategyFile = Join-Path $projectRoot "strategies\$Strategy\$Strategy.mqh"
if (-not (Test-Path -LiteralPath $strategyFile -PathType Leaf)) {
    throw "Unknown strategy '$Strategy'. Choose a folder name from strategies/."
}
. (Join-Path $PSScriptRoot 'ReadExperiment.ps1')
. (Join-Path $PSScriptRoot 'WriteRunRecipe.ps1')
$gitState = Get-RunGitState $projectRoot
Write-Host "Strategy: $Strategy"
$outputRoot = Join-Path $projectRoot "outputs\backtest\$Strategy"
$outputRoot = Join-Path $outputRoot ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0,8))
$runRoot = Join-Path $env:TEMP ('mercatus-backtest-' + [guid]::NewGuid().ToString('N'))
$commonRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal\Common\Files\Mercatus'
$terminal = Join-Path $MetaTraderDirectory 'terminal64.exe'
$terminalRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'Close MetaTrader 5 before running the backtest.'
}
if (-not $TerminalDataDirectory) {
    $matchesByOrigin = @(Get-ChildItem -LiteralPath $terminalRoot -Directory | Where-Object {
        $origin = Join-Path $_.FullName 'origin.txt'
        (Test-Path -LiteralPath $origin) -and
            ((Get-Content -LiteralPath $origin -Raw).Trim() -eq $MetaTraderDirectory.TrimEnd('\'))
    })
    if ($matchesByOrigin.Count -ne 1) { throw 'Specify the configured MT5 data folder with -TerminalDataDirectory (File > Open Data Folder).' }
    $TerminalDataDirectory = $matchesByOrigin[0].FullName
}
$settings = Get-Content -LiteralPath (Join-Path $TerminalDataDirectory 'config\common.ini') -Raw
if ($settings -notmatch '(?mi)^Server=MetaQuotes-Demo\s*$' -or $settings -notmatch '(?mi)^Login=([1-9]\d*)\s*$') {
    throw 'Sign in to MetaQuotes-Demo in MT5 before running the backtest.'
}
$demoLogin = $Matches[1]
$mtData = $TerminalDataDirectory
$demoSettings = "Login=$demoLogin" + [Environment]::NewLine + 'Server=MetaQuotes-Demo'
$runIds = @()
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
New-Item -ItemType Directory -Path $runRoot | Out-Null

function Invoke-MtProcess {
    param([string]$Executable, [string[]]$Arguments, [int[]]$AcceptedExitCodes = @(0))
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WindowStyle Hidden -PassThru
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { throw "MT5 process exceeded $TimeoutSeconds seconds." }
        $process.Refresh()
        if ($process.ExitCode -eq -1000012353) { throw "MT5 Strategy Tester requires a configured account. Check that the desktop terminal is signed in to MetaQuotes-Demo." }
        if ($process.ExitCode -notin $AcceptedExitCodes) { throw "MT5 process exited with code $($process.ExitCode)." }
    }
    finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

function New-MqlSchedule {
    param([string]$StrategySource, [string]$SchedulePath, [string[]]$ParameterNames)

    $culture = [Globalization.CultureInfo]::InvariantCulture
    $selected = @()
    $code = Get-Content -LiteralPath $strategySource -Raw
    $code = [regex]::Replace($code, '(?m)^(\s*)input(?=\s+int\s+\w+\s*=)', '$1')
    [IO.File]::WriteAllText($strategySource, $code)
    $selected += '#define MERCATUS_SCHEDULE'
    $selected += 'void apply_schedule(const datetime now)', '{'
    $scheduleRows = @(Import-Csv -LiteralPath $SchedulePath)
    foreach ($segment in ($scheduleRows | Sort-Object From -Descending)) {
        $date = [datetime]::ParseExact($segment.From, 'yyyy-MM-dd', $culture).ToString('yyyy.MM.dd', $culture)
        $selected += "   if(now >= D'$date')", '   {'
        foreach ($key in $ParameterNames) { $selected += "      $key = $([int]$segment.$key);" }
        $selected += '      return;', '   }'
    }
    $selected += '}'
    $parameterFormat = ($ParameterNames | ForEach-Object { "$_=%d" }) -join ';'
    $arguments = $ParameterNames -join ', '
    $selected += 'string format_active_parameters()', '{',
        ('   return StringFormat("{0}", {1});' -f $parameterFormat, $arguments), '}'
    return $selected
}

try {
    Copy-Item -LiteralPath $Config -Destination (Join-Path $outputRoot 'experiment.ini')
    if ($Schedule) { Copy-Item -LiteralPath $Schedule -Destination (Join-Path $outputRoot 'schedule.csv') }
    $terminalVersion = (Get-Item -LiteralPath $terminal).VersionInfo.FileVersion
    $sourceRoot = Join-Path $runRoot 'source'
    New-Item -ItemType Directory -Path $sourceRoot | Out-Null
    foreach ($name in @('experts', 'strategies')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $sourceRoot -Recurse
    }
    $selected = @('#include "../strategies/{0}/{0}.mqh"' -f $Strategy)
    if ($Schedule) {
        $strategySource = Join-Path $sourceRoot "strategies\$Strategy\$Strategy.mqh"
        $selected += New-MqlSchedule -StrategySource $strategySource -SchedulePath $Schedule -ParameterNames $inputs
    }
    $selected | Set-Content -LiteralPath (Join-Path $sourceRoot 'experts\SelectedStrategy.mqh') -Encoding ASCII
    $sources = @('experts\Simulator.mq5')
    if ($SetupScript) {
        New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'setup') | Out-Null
        Copy-Item -LiteralPath $SetupScript -Destination (Join-Path $sourceRoot 'setup\Setup.mq5')
        $sources = @('setup\Setup.mq5') + $sources
    }
    foreach ($relative in $sources) {
        $source = Join-Path $sourceRoot $relative
        $log = [IO.Path]::ChangeExtension($source, '.log')
        $binary = [IO.Path]::ChangeExtension($source, '.ex5')
        Remove-Item -LiteralPath $log, $binary -ErrorAction SilentlyContinue
        Invoke-MtProcess -Executable (Join-Path $MetaTraderDirectory 'MetaEditor64.exe') -Arguments @(('/compile:"' + $source + '"'), '/log') -AcceptedExitCodes @(0, 1)
        if (-not (Test-Path -LiteralPath $log)) { throw 'Missing compiler log.' }
        Copy-Item -LiteralPath $log -Destination (Join-Path $outputRoot ((Split-Path $source -Leaf) + '.log'))
        if ((Get-Content -LiteralPath $log -Encoding Unicode -Raw) -notmatch 'Result: 0 errors, 0 warnings' -or -not (Test-Path -LiteralPath $binary)) {
            throw "Compilation failed: $relative. See the strategy output directory."
        }
        $kind = if ($relative.StartsWith('setup')) { 'Scripts' } else { 'Experts' }
        $destination = Join-Path $mtData ('MQL5\' + $kind + '\Mercatus')
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath $binary -Destination $destination
    }
    if ($SetupScript) {
        $setup = Join-Path $runRoot 'setup.ini'
    @"
[Common]
$demoSettings
NewsEnable=0
[Experts]
Enabled=0
AllowLiveTrading=0
AllowDllImport=0
[StartUp]
Symbol=EURUSD
Period=H1
Script=Mercatus\Setup.ex5
ShutdownTerminal=1
"@ | Set-Content -LiteralPath $setup -Encoding ASCII
        Invoke-MtProcess -Executable $terminal -Arguments @(('/config:"' + $setup + '"'))
    }
    $presets = Join-Path $mtData 'MQL5\Profiles\Tester'
    New-Item -ItemType Directory -Path $presets -Force | Out-Null
    $summary = @()
    $scenarios = @(1..$grid.Count | ForEach-Object { "run-$_" })
    $index = 0
    foreach ($scenario in $scenarios) {
        $runId = [guid]::NewGuid().ToString('N')
        $runIds += $runId
        $scenarioOutput = Join-Path $outputRoot $scenario
        New-Item -ItemType Directory -Path $scenarioOutput -Force | Out-Null
        $presetName = "mercatus-$runId.set"
        $reportName = "mercatus-$runId.htm"
        $preset = @("RunId=$runId", "DrawdownLimit=$($DrawdownLimit.ToString('R', $culture))", "TradingFrom=$($from.ToString('yyyy.MM.dd', $culture))")
        $combination = $grid[$index]
        $index++
        $parameterLines = @($combination.Keys | ForEach-Object { "$_=$($combination[$_])" })
        if (!$Schedule) { $preset += $parameterLines }
        Write-Host "Run $index/$($grid.Count): $($parameterLines -join ', ')"
        $preset | Set-Content -LiteralPath (Join-Path $presets $presetName) -Encoding ASCII
        $config = @"
[Common]
$demoSettings
NewsEnable=0
[Experts]
Enabled=0
AllowLiveTrading=0
AllowDllImport=0
[Tester]
Expert=Mercatus\Simulator.ex5
ExpertParameters=$presetName
Symbol=$($spec.Symbol)
Period=$($spec.Timeframe)
Model=4
ExecutionMode=0
Optimization=0
FromDate=$($from.AddYears(-$warmupYears).ToString('yyyy.MM.dd', $culture))
ToDate=$($to.ToString('yyyy.MM.dd', $culture))
Deposit=10000
Currency=USD
Leverage=$leverage
UseLocal=1
UseRemote=0
UseCloud=0
Visual=0
Report=$reportName
ReplaceReport=1
ShutdownTerminal=1
"@
        $config.Substring($config.IndexOf('[Experts]')) |
            Set-Content -LiteralPath (Join-Path $scenarioOutput 'tester.ini') -Encoding ASCII
        $preset | Set-Content -LiteralPath (Join-Path $scenarioOutput $presetName) -Encoding ASCII
        $configFile = Join-Path $runRoot ($scenario + '.ini')
        $config | Set-Content -LiteralPath $configFile -Encoding ASCII
        Invoke-MtProcess -Executable $terminal -Arguments @(('/config:"' + $configFile + '"'))
        foreach ($kind in @('decisions', 'deals')) {
            $file = Join-Path $commonRoot ($runId + '-' + $kind + '.csv')
            if (-not (Test-Path -LiteralPath $file)) { throw "Missing $scenario $kind output. See terminal logs." }
            Copy-Item -LiteralPath $file -Destination (Join-Path $scenarioOutput ($kind + '.csv'))
        }
        $report = Join-Path $mtData $reportName
        if (-not (Test-Path -LiteralPath $report)) { $report = Join-Path $MetaTraderDirectory $reportName }
        if (-not (Test-Path -LiteralPath $report)) { throw 'Missing native MT5 report.' }
        Copy-Item -LiteralPath $report -Destination (Join-Path $scenarioOutput 'report.htm')
        $agentLogs = @(Get-ChildItem -LiteralPath (Join-Path $mtData 'Tester') -Filter '*.log' -File -Recurse)
        $text = ($agentLogs | ForEach-Object { Get-Content -LiteralPath $_.FullName -Encoding Unicode }) -join "`n"
        $result = [regex]::Matches($text, ('MercatusSimulator: (PASS|FAIL) run=' + $runId + '[^\r\n]*'))
        if ($result.Count -eq 0 -or $result[$result.Count - 1].Groups[1].Value -ne 'PASS') { throw "Backtest execution failed: $scenario." }
        Write-Host ($scenario + ': ' + $result[$result.Count - 1].Value)
        Copy-Item -LiteralPath (Join-Path $commonRoot "$runId-equity.csv") -Destination (Join-Path $scenarioOutput 'equity.csv')
        $metrics = Import-Csv -LiteralPath (Join-Path $commonRoot "$runId-metrics.csv")
        $row = [ordered]@{ Run = $scenario; Strategy = $Strategy; Symbol = $spec.Symbol; Timeframe = $spec.Timeframe; From = $spec.From; To = $spec.To }
        foreach ($key in $combination.Keys) { $row[$key] = $combination[$key] }
        foreach ($metric in $metrics.PSObject.Properties) { $row[$metric.Name] = $metric.Value }
        $row.ClosedTrades = Get-ClosedTradeCount -Deals @(Import-Csv -LiteralPath (Join-Path $scenarioOutput 'deals.csv')) -From $spec.From -To $spec.To
        $extraCostTotal = $extraCost * [int]$metrics.Executions
        $netProfit = [decimal]::Parse($metrics.NetProfit, $culture)
        $row.ExtraCostPerExecutionUSD = $extraCost.ToString($culture)
        $row.ExtraCostTotalUSD = $extraCostTotal.ToString($culture)
        $row.NetProfitAfterExtraCostUSD = ($netProfit - $extraCostTotal).ToString($culture)
        $daily = @(Import-Csv -LiteralPath (Join-Path $scenarioOutput 'equity.csv'))
        $deals = @(Import-Csv -LiteralPath (Join-Path $scenarioOutput 'deals.csv'))
        $netCurve = @(Get-CostAdjustedEquity $daily $deals $spec.From $extraCost)
        $netMetrics = Get-EquityMetrics $netCurve
        $row.NetAnnualizedSharpe = ''
        if ($null -ne $netMetrics.Sharpe) { $row.NetAnnualizedSharpe = $netMetrics.Sharpe.ToString('R', $culture) }
        $row.Server = 'MetaQuotes-Demo'
        $row.TickMode = 'RealTicks'
        $row.ExecutionDelayMs = 0
        $quality = [regex]::Match((Get-Content -LiteralPath $report -Raw), '(?is)History Quality:\s*</td>\s*<td\b[^>]*>\s*<b>\s*([^<]+)')
        $row.MT5HistoryQuality = $quality.Groups[1].Value.Trim()
        $summary += [pscustomobject]$row
    }
    $summaryPath = Join-Path $outputRoot 'summary.csv'
    $summary | Export-Csv -LiteralPath $summaryPath -NoTypeInformation
    [ordered]@{
        Strategy = $Strategy
        Git = $gitState
        MT5FileVersion = $terminalVersion
        ExperimentConfig = 'experiment.ini'
        Schedule = $(if ($Schedule) { 'schedule.csv' } else { $null })
        SetupScriptSHA256 = $(if ($SetupScript) { (Get-FileHash -LiteralPath $SetupScript).Hash } else { $null })
        Runs = @(foreach ($row in $summary) {
            [ordered]@{
                Run = $row.Run
                TesterConfig = "$($row.Run)/tester.ini"
                DataOrigin = $(if ($row.CustomSymbol -eq '1') { 'Custom symbol in MT5' } else { $row.Server })
                Symbol = $row.Symbol
                TickMode = $row.TickMode
                FirstTick = $row.FirstTick
                LastTick = $row.LastTick
                TicksProcessed = $row.TicksProcessed
                MT5HistoryQuality = $row.MT5HistoryQuality
                TesterBuild = $row.TesterBuild
            }
        })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputRoot 'recipe.json') -Encoding UTF8
    [pscustomobject]@{ SummaryPath = $summaryPath; ParameterNames = $inputs }
}
finally {
    foreach ($runId in $runIds) {
        Remove-Item -LiteralPath (Join-Path $mtData "MQL5\Profiles\Tester\mercatus-$runId.set") -ErrorAction SilentlyContinue
        foreach ($root in @($mtData, $MetaTraderDirectory)) {
            Remove-Item -LiteralPath (Join-Path $root "mercatus-$runId.htm") -ErrorAction SilentlyContinue
        }
        foreach ($kind in @('decisions', 'deals', 'metrics', 'equity')) {
            Remove-Item -LiteralPath (Join-Path $commonRoot ($runId + '-' + $kind + '.csv')) -ErrorAction SilentlyContinue
        }
    }
    $resolved = [IO.Path]::GetFullPath($runRoot)
    $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notmatch '^mercatus-backtest-[0-9a-f]{32}$') { throw 'Unexpected cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
