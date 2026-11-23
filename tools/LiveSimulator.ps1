param(
    [Parameter(Mandatory)][string]$Strategy,
    [Parameter(Mandatory)][string]$Config,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 90
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'internal\WriteEquityChart.ps1')

$output = & (Join-Path $PSScriptRoot 'internal\InvokeSimulator.ps1') -Strategy $Strategy -Config $Config -FixedParameters -TimeoutSeconds $TimeoutSeconds
$summary = $output.SummaryPath
$row = Import-Csv -LiteralPath $summary
$run = Split-Path $summary -Parent
$culture = [Globalization.CultureInfo]::InvariantCulture
$from = [datetime]::ParseExact($row.From, 'yyyy-MM-dd', $culture)
$to = [datetime]::ParseExact($row.To, 'yyyy-MM-dd', $culture)
$simulation = Join-Path $run $row.Run
$daily = @(Import-Csv -LiteralPath (Join-Path $simulation 'equity.csv'))
$deals = @(Import-Csv -LiteralPath (Join-Path $simulation 'deals.csv'))
$extraCost = [decimal]::Parse($row.ExtraCostPerExecutionUSD, $culture)
$curve = @(Get-CostAdjustedEquity $daily $deals $row.From $extraCost)
$curve | Export-Csv -LiteralPath (Join-Path $run 'equity.csv') -NoTypeInformation

$chart = Write-EquityChart $curve $from $to $run $Strategy $row.Symbol $row.Timeframe 'Live simulation equity' -Segments @($row) -ParameterNames $output.ParameterNames -ExtraCost $extraCost
Write-Output $summary
Write-Output $chart
