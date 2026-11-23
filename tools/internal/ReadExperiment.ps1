$sections = @{}
$section = $null
foreach ($line in Get-Content -LiteralPath $Config) {
    $line = $line.Trim()
    if (!$line -or $line -match '^[;#]') { continue }
    if ($line -match '^\[(Backtest|Parameters)\]$') {
        $section = $Matches[1]
        if ($sections.ContainsKey($section)) { throw "Duplicate section: $section" }
        $sections[$section] = [ordered]@{}
    } elseif ($section -and $line -match '^(\w+)\s*=\s*(.+)$') {
        if ($sections[$section].Contains($Matches[1])) { throw "Duplicate key: $line" }
        $sections[$section][$Matches[1]] = $Matches[2].Trim()
    } else { throw "Invalid config line: $line" }
}
$spec = $sections['Backtest']
$parameters = $sections['Parameters']
$allowed = @('Symbol', 'Timeframe', 'From', 'To', 'ExtraCostPerExecutionUSD', 'WarmupYears')
if (!$spec -or !$parameters -or @($spec.Keys | Where-Object { $_ -notin $allowed }).Count -or !$spec['From'] -or !$spec['To'] -or
    $spec['Symbol'] -cnotmatch '^[A-Za-z0-9_.#-]+$' -or
    $spec['Timeframe'] -cnotmatch '^(M(1|2|3|4|5|6|10|12|15|20|30)|H(1|2|3|4|6|8|12)|D1)$') {
    throw 'Expected Symbol, Timeframe, From and To under [Backtest], and a [Parameters] section.'
}
$warmupYears = 0
if ($spec.Contains('WarmupYears') -and
    (![int]::TryParse($spec['WarmupYears'], [ref]$warmupYears) -or $warmupYears -lt 0 -or $warmupYears -gt 10)) {
    throw 'WarmupYears must be an integer from 0 to 10.'
}
$culture = [Globalization.CultureInfo]::InvariantCulture
$extraCost = [decimal]0
if ($spec.Contains('ExtraCostPerExecutionUSD')) {
    $value = $spec['ExtraCostPerExecutionUSD']
    if ($value -notmatch '^\d+(\.\d+)?$' -or
        -not [decimal]::TryParse($value, [Globalization.NumberStyles]::AllowDecimalPoint, $culture, [ref]$extraCost) -or
        $extraCost -gt [decimal]::MaxValue / [int]::MaxValue) {
        throw 'ExtraCostPerExecutionUSD must be a nonnegative decimal in USD (use a dot).'
    }
}
$from = [datetime]::ParseExact($spec.From, 'yyyy-MM-dd', $culture)
$to = [datetime]::ParseExact($spec.To, 'yyyy-MM-dd', $culture)
if ($from -ge $to) { throw 'From must precede To.' }
$inputs = @([regex]::Matches((Get-Content -LiteralPath $strategyFile -Raw), '(?m)^\s*input\s+int\s+(\w+)\s*=') |
    ForEach-Object { $_.Groups[1].Value })
if ($inputs.Count -ne $parameters.Count -or @($inputs | Where-Object { $_ -cnotin $parameters.Keys }).Count) {
    throw "Expected integer strategy parameters: $($inputs -join ', ')."
}
$grid = @([ordered]@{})
foreach ($key in $inputs) {
    if ($FixedParameters -and $parameters[$key].Contains(',')) {
        throw "Live requires one fixed value for $key."
    }
    $values = @($parameters[$key].Split(',') | ForEach-Object {
        $value = 0
        if (![int]::TryParse($_.Trim(), [ref]$value)) { throw "Invalid integer for $key." }
        $value
    } | Select-Object -Unique)
    $grid = @(foreach ($previous in $grid) {
        foreach ($value in $values) {
            $combination = [ordered]@{}
            foreach ($name in $previous.Keys) { $combination[$name] = $previous[$name] }
            $combination[$key] = $value
            $combination
        }
    })
}
