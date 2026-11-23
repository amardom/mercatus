Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\internal\WriteEquityChart.ps1')
$output = Join-Path $env:TEMP ('mercatus-chart-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
$curve = @(
    [pscustomobject]@{ Date = '2025-01-01'; EquityUSD = 10000 }
    [pscustomobject]@{ Date = '2025-01-02'; EquityUSD = 10003 }
    [pscustomobject]@{ Date = '2025-01-03'; EquityUSD = 10001 }
)
$segments = @(
    [pscustomobject]@{ From = '2025-01-01'; To = '2025-01-02'; Fast = 2; Slow = 12 }
    [pscustomobject]@{ From = '2025-01-02'; To = '2025-01-04'; Fast = 4; Slow = 24 }
)
$daily = @(
    [pscustomobject]@{ Date = ''; Equity = '100' }
    [pscustomobject]@{ Date = '2025.01.01'; Equity = '111' }
    [pscustomobject]@{ Date = '2025.01.03'; Equity = '113' }
)
$deals = @(
    [pscustomobject]@{ time = '2025.01.01 12:00:00' }
    [pscustomobject]@{ time = '2025.01.03 08:00:00' }
    [pscustomobject]@{ time = '2025.01.03 08:00:00' }
)
$adjusted = @(Get-CostAdjustedEquity $daily $deals '2025-01-01' 2)
if (($adjusted.EquityUSD -join ',') -ne '100,109,107') {
    throw 'Expected cumulative execution costs, including both fills at the same timestamp.'
}
$metrics = Get-EquityMetrics $adjusted
$r1 = 0.09
$r2 = -2.0 / 109
$expected = [Math]::Sqrt(252) * (($r1 + $r2) / 2) / ([Math]::Abs($r1 - $r2) / [Math]::Sqrt(2))
if ([Math]::Abs($metrics.Sharpe - $expected) -gt 1e-10 -or $metrics.ReturnPct -ne 7 -or
    [Math]::Abs($metrics.DailyDrawdownPct - 200.0 / 109) -gt 1e-10) {
    throw 'Expected metrics from the cost-adjusted daily equity.'
}
try {
    foreach ($count in 1,2) {
        $active = if ($count -eq 1) {
            [pscustomobject]@{ From = '2025-01-01'; To = '2025-01-04'; Fast = 2; Slow = 12 }
        } else { $segments }
        $chart = Write-EquityChart $curve ([datetime]'2025-01-01') ([datetime]'2025-01-04') $output MovingAverage 'EUR&USD' H1 'Equity <test>' -Segments $active -ParameterNames Fast,Slow -ExtraCost 0.10
        [xml]$svg = Get-Content -LiteralPath $chart -Raw
        if ($svg.OuterXml -notmatch 'Return \+0\.01% \| Ann\. Sharpe .+ \| Max daily drawdown 0\.02%' -or
            $svg.OuterXml -notmatch 'USD 0\.10 extra per execution') {
            throw 'The chart is missing the summary metrics or the surcharge.'
        }
        $values = @($svg.SelectNodes('//*[@class="parameter-values"]'))
        $periods = @($svg.SelectNodes('//*[@class="parameter-period"]'))
        if ($values.Count -ne $count -or $periods.Count -ne $count -or
            @($svg.svg.g.polyline.points -split ' ').Count -ne $curve.Count) {
            throw 'Unexpected number of parameters or curve observations in the SVG.'
        }
        for ($i = 0; $i -lt $count; $i++) {
            $segment = @($active)[$i]
            if ($values[$i].InnerText -ne "Fast=$($segment.Fast) | Slow=$($segment.Slow)" -or
                $periods[$i].InnerText -ne "$($segment.From) to $($segment.To)") {
                throw "Incorrect parameters for chart segment $($i + 1)."
            }
        }
    }
} finally {
    Remove-Item -LiteralPath (Join-Path $output 'equity.svg') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $output
}
Write-Output 'Equity chart: PASS (fixed parameters and rolling schedule)'
