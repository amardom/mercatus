Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$config = Join-Path $PSScriptRoot 'WalkForward.inib'
$output = @(& (Join-Path $PSScriptRoot '..\..\tools\Backtester.ps1') -Strategy MovingAverage -Config $config -NoOpenChart)
$folder = Split-Path $output[-1] -Parent
$schedule = @(Import-Csv -LiteralPath (Join-Path $folder 'schedule.csv'))
$expectedDates = @('2025-01-06','2025-01-12','2025-01-18','2025-01-25','2025-01-31','2025-02-06','2025-02-13','2025-02-19','2025-02-25','2025-03-04')
if ($schedule.Count -ne 5) { throw 'Expected five walk-forward passes.' }
for ($i = 0; $i -lt 5; $i++) {
    $pass = $schedule[$i]
    if ($pass.Pass -ne ($i + 1) -or $pass.FitFrom -ne $expectedDates[$i] -or
        $pass.FitTo -ne $expectedDates[$i + 4] -or $pass.From -ne $pass.FitTo -or
        $pass.To -ne $expectedDates[$i + 5]) {
        throw "Incorrect fit/test boundaries for pass $($i + 1)."
    }
    $fit = @(Import-Csv -LiteralPath $pass.FitSummary)
    if ($fit.Count -ne 2 -or @($fit | Where-Object {
        $_.From -ne $pass.FitFrom -or $_.To -ne $pass.FitTo -or !$_.NetAnnualizedSharpe
    }).Count) { throw 'Incorrect fit runs.' }
    $scores = @($fit | ForEach-Object { [double]::Parse($_.NetAnnualizedSharpe, $culture) })
    $winner = if ($scores[0] -ge $scores[1]) { $fit[0] } else { $fit[1] }
    if ($pass.Fast -ne $winner.Fast -or $pass.Slow -ne $winner.Slow -or
        $pass.FitSharpe -ne $winner.NetAnnualizedSharpe) { throw 'Did not select the best in-sample Sharpe.' }
}
if (@($schedule.Fast | Sort-Object -Unique).Count -lt 2) { throw 'Fixture must exercise a parameter change.' }

$summary = @(Import-Csv -LiteralPath $output[-1])
if ($summary.Count -ne 1 -or $summary[0].From -ne $schedule[0].From -or $summary[0].To -ne $schedule[-1].To) {
    throw 'Expected one continuous out-of-sample run.'
}
$row = $summary[0]
$run = Join-Path (Split-Path $row.SimulationSummary -Parent) $row.Run
$decisions = @(Import-Csv -LiteralPath (Join-Path $run 'decisions.csv'))
foreach ($pass in $schedule) {
    $from = $pass.From.Replace('-', '.')
    $to = $pass.To.Replace('-', '.')
    $segment = @($decisions | Where-Object { $_.time -ge $from -and $_.time -lt $to })
    if (!$segment.Count -or @($segment | Where-Object {
        $_.active_parameters -ne "Fast=$($pass.Fast);Slow=$($pass.Slow)"
    }).Count) { throw "Wrong parameters applied during $($pass.From)." }
}
$raw = @(Import-Csv -LiteralPath (Join-Path $run 'equity.csv'))
$curve = @(Import-Csv -LiteralPath (Join-Path $folder 'equity.csv'))
$deals = @(Import-Csv -LiteralPath (Join-Path $run 'deals.csv'))
$expected = 10000 + [decimal]::Parse($row.NetProfitAfterExtraCostUSD, $culture) + [decimal]::Parse($row.BalanceResidual, $culture)
if ($raw.Count -lt 2 -or $curve.Count -ne $raw.Count -or $deals.Count -ne [int]$row.Executions -or
    $curve[0].Date -ne $row.From -or [decimal]::Parse($raw[0].Equity, $culture) -ne 10000 -or
    [decimal]::Parse($curve[0].EquityUSD, $culture) -ne 10000 -or
    [Math]::Abs([decimal]::Parse($curve[-1].EquityUSD, $culture) - $expected) -gt 0.01) {
    throw 'Continuous equity does not reconcile.'
}
for ($i = 1; $i -lt $curve.Count; $i++) {
    $fills = @($deals | Where-Object { $_.time.Substring(0, 10) -le $raw[$i].Date }).Count
    $expectedEquity = [decimal]::Parse($raw[$i].Equity, $culture) - [decimal]'0.10' * $fills
    if (!$raw[$i].Date -or $curve[$i].Date -ne $raw[$i].Date.Replace('.', '-') -or
        $curve[$i].Date -lt $curve[$i - 1].Date -or $curve[$i].Date -ge $row.To -or
        [Math]::Abs([decimal]::Parse($curve[$i].EquityUSD, $culture) - $expectedEquity) -gt 0.000001) {
        throw 'The published curve differs from continuous equity after execution costs.'
    }
}
[xml]$chart = Get-Content -LiteralPath (Join-Path $folder 'equity.svg') -Raw
if (@($chart.svg.g.polyline.points -split ' ').Count -ne $curve.Count) { throw 'Missing chart observations.' }
$recipe = Get-Content -LiteralPath (Join-Path $folder 'recipe.json') -Raw | ConvertFrom-Json
if ($recipe.Passes -ne 5 -or $recipe.TrainingSegments -ne 4 -or $recipe.TestSegments -ne 1 -or
    @($recipe.FitRecipes).Count -ne 5 -or
    (Get-FileHash -LiteralPath $config).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $folder $recipe.ExperimentConfig)).Hash) {
    throw 'Incomplete walk-forward recipe.'
}
for ($i = 0; $i -lt 5; $i++) {
    $pass = $schedule[$i]
    $fitFolder = Split-Path $pass.FitSummary -Parent
    if ($recipe.FitRecipes[$i] -ne (Join-Path $fitFolder 'recipe.json')) { throw 'Incorrect fit recipe link.' }
    $fitRecipe = Get-Content -LiteralPath $recipe.FitRecipes[$i] -Raw | ConvertFrom-Json
    $fitConfig = Get-Content -LiteralPath (Join-Path $fitFolder $fitRecipe.ExperimentConfig) -Raw
    if ($fitConfig -notmatch "(?m)^From=$($pass.FitFrom)\s*$" -or
        $fitConfig -notmatch "(?m)^To=$($pass.FitTo)\s*$" -or
        $fitConfig -notmatch '(?m)^Fast=2,4\s*$' -or $fitConfig -notmatch '(?m)^Slow=12\s*$') {
        throw "Incorrect saved fit configuration for pass $($i + 1)."
    }
}
$simulationFolder = Split-Path $row.SimulationSummary -Parent
if ($recipe.SimulationRecipe -ne (Join-Path $simulationFolder 'recipe.json')) {
    throw 'Incorrect continuous simulation recipe link.'
}
$simulation = Get-Content -LiteralPath $recipe.SimulationRecipe -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath (Join-Path $folder $recipe.Schedule)).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $simulationFolder $simulation.Schedule)).Hash) {
    throw 'Saved schedule differs from the one used in the continuous simulation.'
}
$simulationConfig = Get-Content -LiteralPath (Join-Path $simulationFolder $simulation.ExperimentConfig) -Raw
if ($simulationConfig -notmatch "(?m)^From=$($schedule[0].From)\s*$" -or
    $simulationConfig -notmatch "(?m)^To=$($schedule[-1].To)\s*$") {
    throw 'Incorrect saved continuous simulation dates.'
}
Write-Output 'WalkForward: PASS (boundaries, Sharpe selection, active parameters and continuous equity)'
