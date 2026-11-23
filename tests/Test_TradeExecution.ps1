Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot '..\tools\internal\InvokeSimulator.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures\CreateFixture.mq5'
$config = Join-Path $PSScriptRoot 'fixtures\Backtester.inib'
$culture = [Globalization.CultureInfo]::InvariantCulture
$times = @('02:00:00', '07:00:00', '13:00:00', '18:00:00')
$prices = @(102.02, 101, 101.02, 100)
$types = @('DEAL_TYPE_BUY', 'DEAL_TYPE_SELL')
foreach ($case in @(
    @{ Name = 'baseline'; Limit = 0.15; Count = 4; Net = -2.04; Balance = 9997.96; Blocked = 0 }
    @{ Name = 'drawdown'; Limit = 0.00005; Count = 2; Net = -1.02; Balance = 9998.98; Blocked = 5 }
)) {
    $options = @{}
    if ($case.Name -eq 'baseline') { $options.SetupScript = $fixture }
    $output = & $engine -Strategy MovingAverage -Config $config -FixedParameters -Leverage '1:1' -DrawdownLimit $case.Limit @options
    $row = Import-Csv -LiteralPath $output.SummaryPath
    $run = Join-Path (Split-Path $output.SummaryPath -Parent) $row.Run
    $deals = @(Import-Csv -LiteralPath (Join-Path $run 'deals.csv'))
    if ($deals.Count -ne $case.Count -or [int]$row.Executions -ne $case.Count -or
        [Math]::Abs([double]::Parse($row.NetProfit, $culture) - $case.Net) -gt 1e-8 -or
        [Math]::Abs([double]::Parse($row.FinalBalance, $culture) - $case.Balance) -gt 1e-8 -or
        [int]$row.BlockedEntries -ne $case.Blocked -or [int]$row.OpenPositions -ne 0) {
        throw "Unexpected backtester totals for $($case.Name)."
    }
    for ($i = 0; $i -lt $deals.Count; $i++) {
        $deal = $deals[$i]
        if ($deal.time -ne "2026.01.05 $($times[$i])" -or $deal.type -ne $types[$i % 2] -or
            [double]::Parse($deal.volume, $culture) -ne 1 -or
            [Math]::Abs([double]::Parse($deal.price, $culture) - $prices[$i]) -gt 1e-8) {
            throw "Unexpected deal $($i + 1) for $($case.Name)."
        }
    }
    Write-Output "Backtester $($case.Name): PASS"
}

$config = Join-Path $PSScriptRoot 'fixtures\CloseMomentum.inib'
$reversalTimes = @('02:00:00', '06:00:00', '06:00:00', '12:00:00', '12:00:00', '17:00:00', '17:00:00', '01:00:00')
$reversalPrices = @(102.02, 102, 102, 100.02, 100.02, 101, 101, 95.02)
$reversalTypes = @('BUY', 'SELL', 'SELL', 'BUY', 'BUY', 'SELL', 'SELL', 'BUY')
foreach ($case in @(
    @{ Name = 'reversals'; Limit = 0.15; Count = 8; Checked = 8; Net = 8.92 }
    @{ Name = 'blocked reversal'; Limit = 0.000001; Count = 2; Checked = 2; Net = -0.02 }
)) {
    $output = & $engine -Strategy CloseMomentum -Config $config -FixedParameters -Leverage '1:1' -DrawdownLimit $case.Limit
    $row = Import-Csv -LiteralPath $output.SummaryPath
    $run = Join-Path (Split-Path $output.SummaryPath -Parent) $row.Run
    $deals = @(Import-Csv -LiteralPath (Join-Path $run 'deals.csv'))
    if ($deals.Count -ne $case.Count -or [decimal]::Parse($row.NetProfit, $culture) -ne [decimal]$case.Net -or
        [decimal]::Parse($row.FinalBalance, $culture) -ne (10000 + [decimal]$case.Net) -or
        [int]$row.OpenPositions -ne 0) {
        throw "Unexpected totals for $($case.Name): count=$($deals.Count), net=$($row.NetProfit)."
    }
    for ($i = 0; $i -lt $case.Checked; $i++) {
        $deal = $deals[$i]
        $date = if ($i -eq 7) { '2026.01.06' } else { '2026.01.05' }
        if ($deal.time -ne "$date $($reversalTimes[$i])" -or $deal.type -ne "DEAL_TYPE_$($reversalTypes[$i])" -or
            [int]$deal.entry -ne ($i % 2) -or [decimal]::Parse($deal.volume, $culture) -ne 1 -or
            [decimal]::Parse($deal.price, $culture) -ne [decimal]$reversalPrices[$i]) {
            throw "Unexpected deal $($i + 1) for $($case.Name)."
        }
    }
    if ($case.Name -eq 'blocked reversal' -and [int]$row.BlockedEntries -le 0) {
        throw 'The risk gate did not block the new side of the reversal.'
    }
    Write-Output "Backtester $($case.Name): PASS"
}

. (Join-Path $PSScriptRoot '..\tools\internal\WriteEquityChart.ps1')
$temporaryConfig = Join-Path $env:TEMP ("mercatus-costs-{0}.inib" -f [guid]::NewGuid().ToString('N'))
try {
    foreach ($cost in @([decimal]0, [decimal]'0.10')) {
        $content = @"
[Backtest]
Symbol=MERCATUS_SYNTH
Timeframe=H1
From=2026-01-05
To=2026-01-06
ExtraCostPerExecutionUSD=$($cost.ToString($culture))

[Parameters]
Lookback=1
"@
        [IO.File]::WriteAllText($temporaryConfig, $content)
        $output = & $engine -Strategy CloseMomentum -Config $temporaryConfig -FixedParameters -Leverage '1:1'
        $row = Import-Csv -LiteralPath $output.SummaryPath
        $run = Join-Path (Split-Path $output.SummaryPath -Parent) $row.Run
        $deals = @(Import-Csv -LiteralPath (Join-Path $run 'deals.csv'))
        $decisions = @(Import-Csv -LiteralPath (Join-Path $run 'decisions.csv'))
        $daily = @(Import-Csv -LiteralPath (Join-Path $run 'equity.csv'))
        $curve = @(Get-CostAdjustedEquity $daily $deals '2026-01-05' $cost)
        if ($deals.Count -ne 8 -or [int]$row.Executions -ne 8 -or [int]$row.OpenPositions -ne 0) {
            throw 'Expected an opening, three two-fill reversals and a final closure.'
        }
        foreach ($index in @(1, 3, 5)) {
            if ($deals[$index].time -ne $deals[$index + 1].time -or
                [int]$deals[$index].entry -ne 1 -or [int]$deals[$index + 1].entry -ne 0) {
                throw 'The fixture did not execute both sides of a reversal.'
            }
        }
        if ([int]$deals[-1].entry -ne 1 -or $deals[-1].time -notlike '2026.01.05 23:59:*' -or
            @($decisions | Where-Object { $_.time -eq $deals[-1].time }).Count -ne 0) {
            throw 'The fixture did not exercise the forced end-of-test closure.'
        }
        $extra = $cost * 8
        $net = [decimal]::Parse($row.NetProfit, $culture)
        if ([decimal]::Parse($row.ExtraCostTotalUSD, $culture) -ne $extra -or
            [decimal]::Parse($row.NetProfitAfterExtraCostUSD, $culture) -ne $net - $extra -or
            [decimal]::Parse($row.FinalBalance, $culture) -ne 10000 + $net) {
            throw 'Summary costs do not count each reversal fill and the final closure exactly once.'
        }
        for ($i = 1; $i -lt $curve.Count; $i++) {
            $date = $curve[$i].Date.Replace('-', '.')
            $executions = @($deals | Where-Object { $_.time.Substring(0, 10) -le $date }).Count
            $expected = [decimal]::Parse($daily[$i].Equity, $culture) - $cost * $executions
            if ([decimal]$curve[$i].EquityUSD -ne $expected) {
                throw 'Daily equity does not deduct the execution costs on their execution dates.'
            }
        }
        $expectedFinal = 10000 + $net - $extra + [decimal]::Parse($row.BalanceResidual, $culture)
        if ([decimal]$curve[0].EquityUSD -ne 10000 -or [decimal]$curve[-1].EquityUSD -ne $expectedFinal) {
            throw 'Cost-adjusted equity does not reconcile with the summary.'
        }
        if ($cost -eq 0) {
            $baselineDeals = $deals | ConvertTo-Csv -NoTypeInformation
            $baselineNet = $net
        } elseif ((($deals | ConvertTo-Csv -NoTypeInformation) -join "`n") -cne ($baselineDeals -join "`n") -or $net -ne $baselineNet) {
            throw 'Postprocessed costs changed the native trades or profit.'
        }
        Write-Output "Execution costs USD ${cost}: PASS (reversals, forced closure, summary and daily equity)"
    }
} finally {
    if (Test-Path -LiteralPath $temporaryConfig) { Remove-Item -LiteralPath $temporaryConfig }
}
