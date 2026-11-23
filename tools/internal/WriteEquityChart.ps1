function Get-CostAdjustedEquity {
    param([object[]]$Daily, [object[]]$Deals, [string]$From, [decimal]$ExtraCost)

    $culture = [Globalization.CultureInfo]::InvariantCulture
    if ($Daily.Count -lt 2) { throw 'No daily equity observations.' }
    $dealIndex = 0
    $dealDates = @($Deals | ForEach-Object { $_.time.Substring(0, 10) } | Sort-Object)
    $initial = [decimal]::Parse($Daily[0].Equity, $culture)
    [pscustomobject]@{ Date = $From; EquityUSD = $initial }
    foreach ($point in ($Daily | Select-Object -Skip 1)) {
        while ($dealIndex -lt $dealDates.Count -and $dealDates[$dealIndex] -le $point.Date) {
            $dealIndex++
        }
        $equity = [decimal]::Parse($point.Equity, $culture) - $ExtraCost * $dealIndex
        [pscustomobject]@{ Date = $point.Date.Replace('.', '-'); EquityUSD = $equity }
    }
    if ($dealIndex -ne $dealDates.Count) { throw 'Execution dates extend beyond the equity series.' }
}

function Get-EquityMetrics {
    param([object[]]$Curve)

    $initial = $Curve[0].EquityUSD
    $peak = $initial
    $drawdown = 0.0
    $returns = @(for ($i = 1; $i -lt $Curve.Count; $i++) {
        $equity = $Curve[$i].EquityUSD
        $peak = [Math]::Max([double]$peak, [double]$equity)
        $drawdown = [Math]::Max($drawdown, 1.0 - $equity / $peak)
        $previous = $Curve[$i - 1].EquityUSD
        if ($previous -gt 0) { [double]($equity / $previous - 1) }
    })
    $sharpe = $null
    if ($returns.Count -ge 2 -and $returns.Count -eq $Curve.Count - 1) {
        $mean = ($returns | Measure-Object -Average).Average
        $sumSquares = ($returns | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum
        if ($sumSquares -gt 0) {
            $sharpe = [Math]::Sqrt(252) * $mean / [Math]::Sqrt($sumSquares / ($returns.Count - 1))
        }
    }
    [pscustomobject]@{
        ReturnPct = 100 * ($Curve[-1].EquityUSD / $initial - 1)
        Sharpe = $sharpe
        DailyDrawdownPct = 100 * $drawdown
    }
}

function Write-EquityChart {
    param($curve, $from, $to, $run, $Strategy, $Symbol, $Timeframe, $Title, [object[]]$Segments, [string[]]$ParameterNames, [decimal]$ExtraCost)
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $range = $curve.EquityUSD | Measure-Object -Minimum -Maximum
    $padding = [Math]::Max(1, 0.08 * ($range.Maximum - $range.Minimum))
    $low = $range.Minimum - $padding
    $high = $range.Maximum + $padding
    $points = @(foreach ($point in $curve) {
        $date = [datetime]::ParseExact($point.Date, 'yyyy-MM-dd', $culture)
        $x = 100 + 730 * ($date - $from).TotalDays / ($to - $from).TotalDays
        $y = 330 - 245 * ($point.EquityUSD - $low) / ($high - $low)
        [string]::Format($culture, '{0:F2},{1:F2}', $x, $y)
    }) -join ' '
    $grid = @(for ($i = 0; $i -le 4; $i++) {
        $y = 330 - 245 * $i / 4
        $label = ($low + ($high - $low) * $i / 4).ToString('N2', $culture)
        [string]::Format($culture, '<path d="M100 {0} H830" stroke="#dce3ea"/><text x="90" y="{1}" text-anchor="end">{2}</text>', $y, ($y + 5), $label)
    }) -join [Environment]::NewLine
    $subtitle = [Security.SecurityElement]::Escape($Strategy + ' | ' + $Symbol + ' ' + $Timeframe)
    $titleText = [Security.SecurityElement]::Escape($Title)
    $height = 428 + 22 * $Segments.Count
    $labels = @(for ($i = 0; $i -lt $Segments.Count; $i++) {
        $segment = $Segments[$i]
        $values = ($ParameterNames | ForEach-Object { "$_=$($segment.$_)" }) -join ' | '
        $period = [Security.SecurityElement]::Escape("$($segment.From) to $($segment.To)")
        $values = [Security.SecurityElement]::Escape($values)
        $y = 430 + 22 * $i
        '<text class="parameter-period" x="100" y="{0}">{1}</text><text class="parameter-values" x="320" y="{0}">{2}</text>' -f $y, $period, $values
    }) -join [Environment]::NewLine
    $metrics = Get-EquityMetrics $curve
    $sharpeText = if ($null -eq $metrics.Sharpe) { 'N/A' } else { $metrics.Sharpe.ToString('F2', $culture) }
    $performance = [string]::Format($culture,
        'Return {0:+0.00;-0.00;0.00}% | Ann. Sharpe {1} | Max daily drawdown {2:F2}%',
        $metrics.ReturnPct, $sharpeText, $metrics.DailyDrawdownPct)
    $costText = $ExtraCost.ToString('0.00##########################', $culture)
    $chart = Join-Path $run 'equity.svg'
@"
<svg xmlns="http://www.w3.org/2000/svg" width="880" height="$height" viewBox="0 0 880 $height">
<rect width="880" height="$height" fill="white"/>
<g font-family="Arial, sans-serif" font-size="13" fill="#34465a">
<text x="100" y="35" font-size="23" fill="#10253c">$titleText (USD)</text>
<text x="100" y="60">$subtitle | $performance</text>
$grid
<polyline points="$points" fill="none" stroke="#087e80" stroke-width="2"/>
<text x="100" y="355">$($from.ToString('yyyy-MM-dd', $culture))</text>
<text x="830" y="355" text-anchor="end">$($to.ToString('yyyy-MM-dd', $culture))</text>
<text x="100" y="389">Daily equity after MT5 costs and USD $costText extra per execution</text>
<text x="100" y="410" font-weight="bold">Parameters by period (end date excluded)</text>
$labels
</g>
</svg>
"@ | Set-Content -LiteralPath $chart -Encoding UTF8
    Write-Output $chart
}
