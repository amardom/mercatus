Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$engine = Join-Path $PSScriptRoot '..\..\tools\internal\InvokeSimulator.ps1'
$fixture = Join-Path $PSScriptRoot '..\fixtures\CreateFixture.mq5'
$culture = [Globalization.CultureInfo]::InvariantCulture
$temp = Join-Path $env:TEMP ('mercatus-transition-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$config = Join-Path $temp 'transition.inib'
$schedule = Join-Path $temp 'schedule.csv'
try {
    @('[Backtest]', 'Symbol=MERCATUS_PAST_A', 'Timeframe=H1', 'From=2026-01-09', 'To=2026-01-11',
        '[Parameters]', 'Lookback=1') | Set-Content -LiteralPath $config -Encoding ASCII
    @('From,To,Lookback', '2026-01-09,2026-01-10,1', '2026-01-10,2026-01-11,24') |
        Set-Content -LiteralPath $schedule -Encoding ASCII
    $output = & $engine -Strategy CloseMomentum -Config $config -FixedParameters -Schedule $schedule -SetupScript $fixture -Leverage '1:1'
    @('[Backtest]', 'Symbol=MERCATUS_PAST_A', 'Timeframe=H1', 'From=2026-01-08', 'To=2026-01-11',
        '[Parameters]', 'Lookback=1') | Set-Content -LiteralPath $config -Encoding ASCII
    @('From,To,Lookback', '2026-01-08,2026-01-10,1', '2026-01-10,2026-01-11,24') |
        Set-Content -LiteralPath $schedule -Encoding ASCII
    $blockedOutput = & $engine -Strategy CloseMomentum -Config $config -FixedParameters -Schedule $schedule -Leverage '1:1' -DrawdownLimit 0.00005
} finally {
    Remove-Item -LiteralPath $config,$schedule -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp
}

$row = Import-Csv -LiteralPath $output.SummaryPath
$run = Join-Path (Split-Path $output.SummaryPath -Parent) $row.Run
$decisions = @(Import-Csv -LiteralPath (Join-Path $run 'decisions.csv'))
$deals = @(Import-Csv -LiteralPath (Join-Path $run 'deals.csv'))
$boundary = '2026.01.10 00:00:00'
$before = @($decisions | Where-Object { $_.time -lt $boundary })
$after = @($decisions | Where-Object { $_.time -ge $boundary })
if (!$before.Count -or !$after.Count -or $before[-1].signal -ne 'SHORT' -or
    $before[-1].active_parameters -ne 'Lookback=1' -or $after[0].time -ne $boundary -or
    $after[0].signal -ne 'LONG' -or $after[0].active_parameters -ne 'Lookback=24' -or
    [decimal]::Parse($after[0].current_exposure, $culture) -le 0) {
    throw 'Expected the first decision with Lookback=24 to reverse an open short.'
}

$past = @($deals | Where-Object { $_.time -lt $boundary })
$fills = @($deals | Where-Object { $_.time -eq $boundary })
if (!$past.Count -or $past[-1].type -ne 'DEAL_TYPE_SELL' -or $past[-1].entry -ne '0' -or
    $fills.Count -ne 2 -or $fills[0].entry -ne '1' -or $fills[1].entry -ne '0') {
    throw 'Expected a short entry before the boundary, then a close and an open at the boundary.'
}
foreach ($fill in $fills) {
    if ($fill.type -ne 'DEAL_TYPE_BUY' -or [decimal]::Parse($fill.price, $culture) -ne [decimal]'102.02' -or
        [decimal]::Parse($fill.volume, $culture) -ne 1) { throw 'Unexpected reversal fill.' }
}
$balance = [decimal]10000
foreach ($deal in $past) {
    foreach ($field in 'profit', 'commission', 'swap', 'fee') {
        $balance += [decimal]::Parse($deal.$field, $culture)
    }
}
$expectedEquity = $balance + [decimal]::Parse($past[-1].price, $culture) - [decimal]'102.02'
if ($expectedEquity -eq 10000 -or
    [Math]::Abs([decimal]::Parse($after[0].equity, $culture) - $expectedEquity) -gt 0.01 -or
    [Math]::Abs([decimal]::Parse($row.FinalBalance, $culture) - 10000 -
        [decimal]::Parse($row.NetProfit, $culture)) -gt 0.01) {
    throw 'Equity at the boundary must include the accumulated balance and the open short.'
}
Write-Output 'Short window transition: PASS (parameter switch, two reversal fills and continuous equity)'

$blockedRow = Import-Csv -LiteralPath $blockedOutput.SummaryPath
$blockedRun = Join-Path (Split-Path $blockedOutput.SummaryPath -Parent) $blockedRow.Run
$riskDecisions = @(Import-Csv -LiteralPath (Join-Path $blockedRun 'decisions.csv'))
$riskDeals = @(Import-Csv -LiteralPath (Join-Path $blockedRun 'deals.csv'))
$blockedBefore = @($riskDecisions | Where-Object { $_.time -lt $boundary -and $_.entry_blocked -eq 'true' })
$riskAfter = @($riskDecisions | Where-Object { $_.time -ge $boundary })
if (!$blockedBefore.Count -or !$riskAfter.Count -or
    $riskAfter[0].active_parameters -ne 'Lookback=24' -or
    $riskAfter[0].signal -eq 'CASH' -or $riskAfter[0].entry_blocked -ne 'true' -or
    @($riskAfter | Where-Object { $_.active_parameters -ne 'Lookback=24' }).Count) {
    throw 'The drawdown entry block must survive the parameter switch.'
}
if ($riskDeals.Count -ne 2 -or $riskDeals[0].entry -ne '0' -or $riskDeals[1].entry -ne '1' -or
    $riskDeals[1].time -ge $boundary -or [int]$blockedRow.OpenPositions -ne 0 -or
    @($riskAfter | Where-Object {
        [decimal]::Parse($_.current_exposure, $culture) -ne 0 -or
        ($_.signal -ne 'CASH' -and $_.entry_blocked -ne 'true')
    }).Count) {
    throw 'The blocked strategy must close its first position and remain flat across the boundary.'
}
$peak = [decimal]10000
foreach ($decision in $riskDecisions) {
    $equity = [decimal]::Parse($decision.equity, $culture)
    if ($equity -gt $peak) { $peak = $equity }
    $expectedDrawdown = 1 - $equity / $peak
    if ([Math]::Abs([decimal]::Parse($decision.drawdown, $culture) - $expectedDrawdown) -gt [decimal]'0.000000001') {
        throw 'Drawdown must retain the equity high-water mark across windows.'
    }
}
if ($peak -le 10000 -or [decimal]::Parse($riskAfter[0].drawdown, $culture) -le [decimal]'0.00005') {
    throw 'The fixture must carry a raised equity peak and an active drawdown into the next window.'
}
$balance = [decimal]10000
foreach ($deal in $riskDeals) {
    foreach ($field in 'profit', 'commission', 'swap', 'fee') {
        $balance += [decimal]::Parse($deal.$field, $culture)
    }
}
if ([Math]::Abs([decimal]::Parse($blockedRow.FinalBalance, $culture) - $balance) -gt [decimal]'0.01') {
    throw 'The blocked simulation balance must reconcile with its executions.'
}
Write-Output 'Drawdown window transition: PASS (persistent block, position closure and equity peak)'
