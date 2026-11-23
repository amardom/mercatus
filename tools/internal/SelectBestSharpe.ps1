function Select-BestSharpe {
    param([object[]]$Rows, [int]$Pass)

    $culture = [Globalization.CultureInfo]::InvariantCulture
    $winner = $null
    $bestScore = [double]::NegativeInfinity
    foreach ($row in $Rows) {
        $score = 0.0
        if (![double]::TryParse($row.NetAnnualizedSharpe, [Globalization.NumberStyles]::Float, $culture, [ref]$score) -or
            [double]::IsNaN($score) -or [double]::IsInfinity($score)) { continue }
        if ($score -gt $bestScore) {
            $winner = $row
            $bestScore = $score
        }
    }
    if ($null -eq $winner) { throw "No valid in-sample Sharpe for pass $Pass." }
    return $winner
}
