Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$backtester = Join-Path $PSScriptRoot '..\..\tools\Backtester.ps1'
$config = Join-Path $env:TEMP ("mercatus-lookahead-$([guid]::NewGuid()).inib")
& (Join-Path $PSScriptRoot '..\Test_TradeExecution.ps1')

try {
    $runs = @(foreach ($symbol in 'MERCATUS_PAST_A', 'MERCATUS_PAST_B') {
        @('[Backtest]', "Symbol=$symbol", 'Timeframe=H1', 'From=2026-01-07', 'To=2026-01-16',
            '[Parameters]', 'Fast=2,4', 'Slow=12') | Set-Content -LiteralPath $config -Encoding ASCII
        $out = @(& $backtester -Strategy MovingAverage -Config $config -NoOpenChart)
        $summary = Import-Csv -LiteralPath $out[-1]
        $folder = Join-Path (Split-Path $summary.SimulationSummary -Parent) $summary.Run
        [pscustomobject]@{
            Schedule = @(Import-Csv -LiteralPath (Join-Path (Split-Path $out[-1] -Parent) 'schedule.csv'))
            Decisions = @(Import-Csv -LiteralPath (Join-Path $folder 'decisions.csv'))
            Deals = @(Import-Csv -LiteralPath (Join-Path $folder 'deals.csv'))
        }
    })
} finally { Remove-Item -LiteralPath $config -ErrorAction SilentlyContinue }

$cut = '2026.01.12'
foreach ($i in 0,1) {
    $a = $runs[0].Schedule[$i]
    $b = $runs[1].Schedule[$i]
    if ($a.FitTo -ne $b.FitTo -or $a.FitTo -gt '2026-01-12' -or
        $a.Fast -ne $b.Fast -or $a.Slow -ne $b.Slow -or $a.FitSharpe -ne $b.FitSharpe) {
        throw 'Changing future prices changed parameter selection.'
    }
}
foreach ($kind in 'Decisions','Deals') {
    $pastA = @($runs[0].$kind | Where-Object { $_.time -lt $cut } | ConvertTo-Csv -NoTypeInformation)
    $pastB = @($runs[1].$kind | Where-Object { $_.time -lt $cut } | ConvertTo-Csv -NoTypeInformation)
    if ($pastA.Count -lt 2 -or $pastB.Count -lt 2 -or ($pastA -join "|") -cne ($pastB -join "|")) {
        throw "Expected identical nonempty $kind before the cutoff."
    }
}
$afterA = @($runs[0].Decisions | Where-Object { $_.time -ge $cut } | Select-Object time, signal | ConvertTo-Csv -NoTypeInformation)
$afterB = @($runs[1].Decisions | Where-Object { $_.time -ge $cut } | Select-Object time, signal | ConvertTo-Csv -NoTypeInformation)
if ($afterA.Count -lt 2 -or $afterA.Count -ne $afterB.Count -or
    ($afterA -join "|") -ceq ($afterB -join "|")) {
    throw 'The future price change must change at least one signal.'
}
Write-Output 'NoLookahead: PASS (parameter selection, decisions and deals before the cutoff)'
