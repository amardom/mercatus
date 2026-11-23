Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot '..\tools\internal\InvokeSimulator.ps1'
$config = Join-Path $env:TEMP ("mercatus-sharpe-$([guid]::NewGuid()).inib")
$culture = [Globalization.CultureInfo]::InvariantCulture

try {
    foreach ($case in @(
        @{ From = '2026-01-05'; To = '2026-01-08'; Expected = ''; Trades = 0 }
        @{ From = '2026-01-07'; To = '2026-01-09'; Expected = '-11.22497216'; Trades = 4 }
    )) {
        @('[Backtest]', 'Symbol=MERCATUS_PAST_A', 'Timeframe=H1', "From=$($case.From)", "To=$($case.To)",
            '[Parameters]', 'Fast=2', 'Slow=4') | Set-Content -LiteralPath $config -Encoding ASCII
        $output = & $engine -Strategy MovingAverage -Config $config -FixedParameters
        $row = Import-Csv -LiteralPath $output.SummaryPath
        if ($row.AnnualizedSharpe -ne $case.Expected -or [int]$row.Executions -ne $case.Trades) {
            throw "Unexpected Sharpe or execution count from $($case.From). Sharpe: '$($row.AnnualizedSharpe)', executions: $($row.Executions)."
        }
    }
} finally { Remove-Item -LiteralPath $config -ErrorAction SilentlyContinue }
Write-Output 'Sharpe calculation: PASS (constant equity and hand-calculated case)'
