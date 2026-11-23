param(
    [string]$MetaTraderDirectory = (Join-Path $env:ProgramFiles 'MetaTrader 5'),
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 90,
    [string]$TerminalDataDirectory,
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$Strategy = 'MovingAverage',
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Config,
    [switch]$NoOpenChart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\WriteEquityChart.ps1')
. (Join-Path $PSScriptRoot 'internal\GetClosedTradeCount.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$strategyFile = Join-Path $projectRoot "strategies\$Strategy\$Strategy.mqh"
if (-not (Test-Path -LiteralPath $strategyFile -PathType Leaf)) {
    throw "Unknown strategy '$Strategy'. Choose a folder name from strategies/."
}
$FixedParameters = $false
. (Join-Path $PSScriptRoot 'internal\ReadExperiment.ps1')
. (Join-Path $PSScriptRoot 'internal\SelectBestSharpe.ps1')
$engine = Join-Path $PSScriptRoot 'internal\InvokeSimulator.ps1'

$days = ($to - $from).Days
if ($days -lt 9) { throw 'Walk-forward requires at least nine calendar days.' }
$dates = @(for ($i = 0; $i -le 9; $i++) {
    $from.AddDays([Math]::Floor($days * $i / 9))
})
$root = Join-Path $projectRoot "outputs\walkforward\$Strategy\$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $root -Force | Out-Null
$periodConfig = Join-Path $root 'period.ini'
try {
    $rows = @(for ($i = 0; $i -lt 5; $i++) {
        $fitFrom = $dates[$i].ToString('yyyy-MM-dd', $culture)
        $testFrom = $dates[($i + 4)].ToString('yyyy-MM-dd', $culture)
        $testTo = $dates[($i + 5)].ToString('yyyy-MM-dd', $culture)
        $settings = @($spec.Keys | Where-Object { $_ -notin 'From', 'To' } | ForEach-Object { "$_=$($spec[$_])" })
        $gridSettings = @($inputs | ForEach-Object { "$_=$($parameters[$_])" })
        Write-Host "Pass $($i + 1)/5: fit $fitFrom to $testFrom, test $testFrom to $testTo"
        @('[Backtest]', $settings, "From=$fitFrom", "To=$testFrom", '[Parameters]', $gridSettings) |
            Set-Content -LiteralPath $periodConfig -Encoding ASCII
        $fit = & $engine -Strategy $Strategy -Config $periodConfig -TimeoutSeconds $TimeoutSeconds -MetaTraderDirectory $MetaTraderDirectory -TerminalDataDirectory $TerminalDataDirectory
        $winner = Select-BestSharpe -Rows @(Import-Csv -LiteralPath $fit.SummaryPath) -Pass ($i + 1)
        $row = [ordered]@{ Pass = $i + 1; FitFrom = $fitFrom; FitTo = $testFrom; From = $testFrom; To = $testTo; FitSharpe = $winner.NetAnnualizedSharpe }
        foreach ($key in $inputs) { $row[$key] = $winner.$key }
        $row.FitSummary = $fit.SummaryPath
        [pscustomobject]$row
    })
    Copy-Item -LiteralPath $Config -Destination (Join-Path $root 'experiment.ini')
    $schedulePath = Join-Path $root 'schedule.csv'
    $rows | Export-Csv -LiteralPath $schedulePath -NoTypeInformation
    $selectedSettings = @($inputs | ForEach-Object { "$_=$($rows[0].$_)" })
    @('[Backtest]', $settings, "From=$($rows[0].From)", "To=$($rows[-1].To)", '[Parameters]', $selectedSettings) |
        Set-Content -LiteralPath $periodConfig -Encoding ASCII
    $test = & $engine -Strategy $Strategy -Config $periodConfig -FixedParameters -Schedule $schedulePath -TimeoutSeconds $TimeoutSeconds -MetaTraderDirectory $MetaTraderDirectory -TerminalDataDirectory $TerminalDataDirectory
    $summaryPath = Join-Path $root 'summary.csv'

    $simulationRecipe = Get-Content -LiteralPath (Join-Path (Split-Path $test.SummaryPath) 'recipe.json') -Raw | ConvertFrom-Json
    [ordered]@{
        Strategy = $Strategy
        ExperimentConfig = 'experiment.ini'
        Schedule = 'schedule.csv'
        Selection = 'Highest in-sample annualized Sharpe after extra execution costs'
        TrainingSegments = 4
        TestSegments = 1
        Passes = $rows.Count
        Git = $simulationRecipe.Git
        MT5FileVersion = $simulationRecipe.MT5FileVersion
        FitRecipes = @($rows | ForEach-Object { Join-Path (Split-Path $_.FitSummary) 'recipe.json' })
        SimulationRecipe = Join-Path (Split-Path $test.SummaryPath) 'recipe.json'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'recipe.json') -Encoding UTF8
    $result = Import-Csv -LiteralPath $test.SummaryPath
    $result | Add-Member -NotePropertyName SimulationSummary -NotePropertyValue $test.SummaryPath
    $result | Select-Object * -ExcludeProperty $inputs | Export-Csv -LiteralPath $summaryPath -NoTypeInformation
    $simulation = Join-Path (Split-Path $test.SummaryPath) $result.Run
    $daily = @(Import-Csv -LiteralPath (Join-Path $simulation 'equity.csv'))
    $deals = @(Import-Csv -LiteralPath (Join-Path $simulation 'deals.csv'))
    $rows | Select-Object Pass, From, To, @{Name = 'ClosedTrades'; Expression = {
        Get-ClosedTradeCount -Deals $deals -From $_.From -To $_.To
    }} | Export-Csv -LiteralPath (Join-Path $root 'out_of_sample.csv') -NoTypeInformation
    $extraCost = [decimal]::Parse($result.ExtraCostPerExecutionUSD, $culture)
    $curve = @(Get-CostAdjustedEquity $daily $deals $result.From $extraCost)
    $curve | Export-Csv -LiteralPath (Join-Path $root 'equity.csv') -NoTypeInformation
    $chart = Write-EquityChart $curve $dates[4] $to $root $Strategy $spec.Symbol $spec.Timeframe 'Walk-forward equity' -Segments $rows -ParameterNames $inputs -ExtraCost $extraCost
    Write-Host "Equity chart: $chart"
    if (!$NoOpenChart) {
        try { Invoke-Item -LiteralPath $chart -ErrorAction Stop }
        catch { Write-Warning "Could not open the equity chart automatically. Open the SVG at the path above." }
    }
    Write-Output $summaryPath
}
finally { Remove-Item -LiteralPath $periodConfig -ErrorAction SilentlyContinue }
