Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\..'
$culture = [Globalization.CultureInfo]::InvariantCulture
$config = Join-Path $PSScriptRoot 'Live.inil'
$output = @(& (Join-Path $root 'tools\LiveSimulator.ps1') -Strategy MovingAverage -Config $config)
$folder = Split-Path $output[-1] -Parent
$rows = @(Import-Csv -LiteralPath (Join-Path $folder 'summary.csv'))
if ($rows.Count -ne 1 -or $rows[0].From -ne '2025-01-01' -or $rows[0].To -ne '2025-02-15' -or
    $rows[0].Fast -ne '4' -or $rows[0].Slow -ne '12' -or [int]$rows[0].Executions -le 0) {
    throw 'Live did not run the full period with fixed parameters.'
}
$row = $rows[0]
$net = [decimal]::Parse($row.NetProfit, $culture)
$extra = [decimal]'0.10' * [int]$row.Executions
if ([decimal]::Parse($row.ExtraCostPerExecutionUSD, $culture) -ne [decimal]'0.10' -or
    [decimal]::Parse($row.ExtraCostTotalUSD, $culture) -ne $extra -or
    [decimal]::Parse($row.NetProfitAfterExtraCostUSD, $culture) -ne ($net - $extra)) {
    throw 'Live applied an incorrect extra cost.'
}
$curve = @(Import-Csv -LiteralPath (Join-Path $folder 'equity.csv'))
$expected = 10000 + ($net - $extra) + [decimal]::Parse($row.BalanceResidual, $culture)
if ($curve.Count -lt 2 -or $curve[0].Date -ne $row.From -or [decimal]$curve[0].EquityUSD -ne 10000 -or
    [Math]::Abs([decimal]::Parse($curve[-1].EquityUSD, $culture) - $expected) -gt 0.01) {
    throw 'Live equity does not reconcile with the continuous simulation.'
}
$raw = @(Import-Csv -LiteralPath (Join-Path (Join-Path $folder $row.Run) 'equity.csv'))
$returns = @(for ($i = 1; $i -lt $raw.Count; $i++) {
    [double]::Parse($raw[$i].Equity, $culture) / [double]::Parse($raw[$i - 1].Equity, $culture) - 1
})
$mean = ($returns | Measure-Object -Average).Average
$sumSquares = ($returns | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum
$expectedSharpe = [Math]::Sqrt(252) * $mean / [Math]::Sqrt($sumSquares / ($returns.Count - 1))
if (!$row.AnnualizedSharpe -or [Math]::Abs([double]::Parse($row.AnnualizedSharpe, $culture) - $expectedSharpe) -gt 0.000001) {
    throw 'Reported Sharpe differs from the Sharpe recalculated from daily equity.'
}
[xml]$chart = Get-Content -LiteralPath $output[-1] -Raw
if (@($chart.svg.g.polyline.points -split ' ').Count -ne $curve.Count) {
    throw 'The chart does not contain one point per equity row.'
}
$recipe = Get-Content -LiteralPath (Join-Path $folder 'recipe.json') -Raw | ConvertFrom-Json
$run = $recipe.Runs[0]
if ($recipe.Strategy -ne 'MovingAverage' -or $recipe.Git.Commit -notmatch '^[a-f0-9]{40,64}$' -or
    $recipe.Git.Dirty -isnot [bool] -or !$recipe.MT5FileVersion -or $recipe.Runs.Count -ne 1 -or
    $run.TesterBuild -notmatch '^\d+$' -or $run.DataOrigin -ne 'MetaQuotes-Demo' -or
    $run.Symbol -ne $row.Symbol -or $run.TickMode -ne $row.TickMode -or $run.FirstTick -ne $row.FirstTick) {
    throw 'Live recipe does not describe the executed run.'
}
if ((Get-FileHash -LiteralPath $config).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $folder $recipe.ExperimentConfig)).Hash) {
    throw 'Live did not retain the experiment config.'
}
$testerPath = Join-Path $folder $run.TesterConfig
$tester = Get-Content -LiteralPath $testerPath -Raw
if ($tester -match '(?im)^\s*(Login|Password)\s*=' -or $tester -notmatch '(?m)^ExpertParameters=(\S+)\s*$') {
    throw 'Live tester config contains credentials or is missing its input file.'
}
$preset = Get-Content -LiteralPath (Join-Path (Split-Path $testerPath -Parent) $Matches[1]) -Raw
if ($preset -notmatch '(?m)^Fast=4\s*$' -or $preset -notmatch '(?m)^Slow=12\s*$') {
    throw 'Saved MT5 inputs differ from the Live configuration.'
}
Write-Output "Live: PASS (continuous period, fixed parameters, costs, equity and Sharpe), net USD $net"
