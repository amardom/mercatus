Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$config = Join-Path $env:TEMP ('mercatus-monthly-warmup-' + [guid]::NewGuid().ToString('N') + '.inil')
try {
    @('[Backtest]', 'Symbol=EURUSD', 'Timeframe=D1', 'WarmupYears=1',
      'From=2024-01-01', 'To=2024-02-06', 'ExtraCostPerExecutionUSD=0.10',
      '[Parameters]', 'LookbackMonths=12') | Set-Content -LiteralPath $config -Encoding ASCII
    $output = @(& (Join-Path $project 'tools\LiveSimulator.ps1') -Strategy MonthlyMomentum -Config $config -TimeoutSeconds 240)
    $summaryPath = $output | Where-Object { $_ -like '*summary.csv' } | Select-Object -Last 1
    $row = Import-Csv -LiteralPath $summaryPath
    $run = Join-Path (Split-Path $summaryPath) $row.Run
    $deals = @(Import-Csv -LiteralPath (Join-Path $run 'deals.csv'))
    $decisions = @(Import-Csv -LiteralPath (Join-Path $run 'decisions.csv'))
    $equity = @(Import-Csv -LiteralPath (Join-Path (Split-Path $summaryPath) 'equity.csv'))
    if ($row.From -ne '2024-01-01' -or $row.To -ne '2024-02-06' -or
        $row.FirstTick -lt '2024.01.01' -or $row.LastTick -ge '2024.02.06' -or
        $deals.Count -eq 0 -or @($deals | Where-Object { $_.time -lt '2024.01.01' }).Count -or
        @($equity | Where-Object { $_.Date -lt '2024-01-01' }).Count) {
        throw 'Warmup must not enter the reported period, trades or equity.'
    }
    if ($decisions[0].signal -ne 'LONG' -or $decisions[0].time -notlike '2024.01.*') {
        throw 'Expected a January signal using the complete preceding twelve months.'
    }
    foreach ($month in @($decisions | Group-Object { $_.time.Substring(0, 7) })) {
        if (@($month.Group.signal | Sort-Object -Unique).Count -ne 1) {
            throw 'The monthly target must remain fixed within a month.'
        }
    }
    if ((Get-Content -LiteralPath (Join-Path $run 'tester.ini') -Raw) -notmatch 'FromDate=2023.01.01') {
        throw 'MT5 must start before the requested trading period.'
    }
    Write-Output 'Monthly warmup: PASS (January history, monthly targets, no warmup trades or equity)'
} finally {
    Remove-Item -LiteralPath $config -ErrorAction SilentlyContinue
}
