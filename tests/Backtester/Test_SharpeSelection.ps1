Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tools\internal\SelectBestSharpe.ps1')

$rows = @(ConvertFrom-Csv @(
    'Run,NetAnnualizedSharpe'
    'run-1,-3'
    'run-2,-0.2'
    'run-3,-1'
))
if ((Select-BestSharpe -Rows $rows -Pass 1).Run -ne 'run-2') {
    throw 'Expected the numerically highest Sharpe among negative scores.'
}
$rows = @(ConvertFrom-Csv @(
    'Run,NetAnnualizedSharpe'
    'run-1,0.25'
    'run-2,0.250'
))
if ((Select-BestSharpe -Rows $rows -Pass 2).Run -ne 'run-1') {
    throw 'Expected the first grid row to win a tie.'
}
$invalid = @(ConvertFrom-Csv @(
    'Run,NetAnnualizedSharpe'
    'run-1,'
    'run-2,NaN'
    'run-3,Infinity'
    'run-4,-Infinity'
    'run-5,1e999'
    'run-6,invalid'
))
$rows = $invalid + [pscustomobject]@{ Run = 'run-7'; NetAnnualizedSharpe = '0' }
if ((Select-BestSharpe -Rows $rows -Pass 3).Run -ne 'run-7') {
    throw 'Expected zero Sharpe to win over undefined and non-finite scores.'
}
foreach ($rows in @(@{ Rows = $invalid }, @{ Rows = @() })) {
    $message = $null
    try { Select-BestSharpe -Rows $rows.Rows -Pass 4 | Out-Null }
    catch { $message = $_.Exception.Message }
    if ($message -ne 'No valid in-sample Sharpe for pass 4.') {
        throw 'Expected a failure that identifies the pass when no scores are valid.'
    }
}
Write-Output 'Sharpe selection: PASS (ranking, ties, invalid scores and no valid candidate)'

. (Join-Path $PSScriptRoot '..\..\tools\internal\WriteEquityChart.ps1')
$daily = @('Date,Equity',',10000','2025.01.01,10010','2025.01.02,10014','2025.01.03,10025','2025.01.04,10030') | ConvertFrom-Csv
$busyDeals = @(1..8 | ForEach-Object { [pscustomobject]@{ time = '2025.01.01 12:00:00' } })
$slowDaily = @('Date,Equity',',10000','2025.01.01,10004','2025.01.02,10005','2025.01.03,10010','2025.01.04,10012') | ConvertFrom-Csv
$slowDeals = @([pscustomobject]@{ time = '2025.01.01 12:00:00' })
$busyGross = Get-EquityMetrics @(Get-CostAdjustedEquity $daily $busyDeals '2025-01-01' 0)
$slowGross = Get-EquityMetrics @(Get-CostAdjustedEquity $slowDaily $slowDeals '2025-01-01' 0)
$busyNet = Get-EquityMetrics @(Get-CostAdjustedEquity $daily $busyDeals '2025-01-01' 4)
$slowNet = Get-EquityMetrics @(Get-CostAdjustedEquity $slowDaily $slowDeals '2025-01-01' 4)
if ($busyGross.Sharpe -le $slowGross.Sharpe -or $busyNet.Sharpe -ge $slowNet.Sharpe) {
    throw 'The fixture must reverse the Sharpe ranking after execution costs.'
}
$rows = @(
    [pscustomobject]@{ Run = 'busy'; AnnualizedSharpe = $busyGross.Sharpe; NetAnnualizedSharpe = $busyNet.Sharpe }
    [pscustomobject]@{ Run = 'slow'; AnnualizedSharpe = $slowGross.Sharpe; NetAnnualizedSharpe = $slowNet.Sharpe }
)
if ((Select-BestSharpe -Rows $rows -Pass 5).Run -ne 'slow') {
    throw 'Selection must use the Sharpe after execution costs.'
}
Write-Output 'Sharpe selection after execution costs: PASS'
