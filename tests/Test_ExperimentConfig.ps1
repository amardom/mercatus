Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$reader = Join-Path $PSScriptRoot '..\tools\internal\ReadExperiment.ps1'
$temp = Join-Path $env:TEMP ('mercatus-config-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$configPath = Join-Path $temp 'experiment.ini'
$strategyPath = Join-Path $temp 'TestStrategy.mqh'
$base = @'
[Backtest]
Symbol=EURUSD
Timeframe=H4
From=2020-01-01
To=2021-01-01

[Parameters]
Fast=2,4
Slow=12,24
'@

function Read-TestConfig {
    param([string]$Text, [bool]$Fixed = $false)
    $Config = $configPath
    $strategyFile = $strategyPath
    $FixedParameters = $Fixed
    $Text | Set-Content -LiteralPath $Config -Encoding ASCII
    . $reader
    [pscustomobject]@{
        Grid = @($grid)
        Inputs = @($inputs)
        ExtraCost = $extraCost
        WarmupYears = $warmupYears
        From = $from
        To = $to
        Symbol = $spec.Symbol
        Timeframe = $spec.Timeframe
    }
}

try {
    @('input int Fast = 2;', 'input int Slow = 12;') |
        Set-Content -LiteralPath $strategyPath -Encoding ASCII
    $result = Read-TestConfig $base
    $combinations = @($result.Grid | ForEach-Object { "$($_.Fast)/$($_.Slow)" }) -join ','
    if ($combinations -ne '2/12,2/24,4/12,4/24' -or
        ($result.Inputs -join ',') -ne 'Fast,Slow' -or
        $result.ExtraCost -ne 0 -or $result.WarmupYears -ne 0 -or
        $result.From -ne [datetime]'2020-01-01' -or $result.To -ne [datetime]'2021-01-01' -or
        $result.Symbol -ne 'EURUSD' -or $result.Timeframe -ne 'H4') {
        throw 'Incorrect grid, dates or default settings.'
    }

    $fixedText = $base.Replace('Fast=2,4', 'Fast=4').Replace('Slow=12,24', 'Slow=24')
    $fixedResult = Read-TestConfig $fixedText -Fixed $true
    if ($fixedResult.Grid.Count -ne 1 -or $fixedResult.Grid[0].Fast -ne 4 -or
        $fixedResult.Grid[0].Slow -ne 24) { throw 'Incorrect fixed parameters.' }

    $duplicates = Read-TestConfig ($base.Replace('Fast=2,4', 'Fast=2,2,4'))
    if ($duplicates.Grid.Count -ne 4) { throw 'Duplicate parameter values must not duplicate runs.' }

    $originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
    try {
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]'fr-FR'
        $options = Read-TestConfig ($base.Replace('[Backtest]', "[Backtest]" + [Environment]::NewLine +
            "ExtraCostPerExecutionUSD=0.10" + [Environment]::NewLine + 'WarmupYears=1'))
        if ($options.ExtraCost -ne [decimal]'0.10' -or $options.WarmupYears -ne 1) {
            throw 'Costs and warmup must be independent of the system decimal separator.'
        }
    } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture }

    $result = Read-TestConfig $base
    if ($result.ExtraCost -ne 0 -or $result.WarmupYears -ne 0) {
        throw 'Optional settings must reset between experiments.'
    }
    foreach ($years in 0,10) {
        $result = Read-TestConfig ($base.Replace('[Backtest]', "[Backtest]" +
            [Environment]::NewLine + "WarmupYears=$years"))
        if ($result.WarmupYears -ne $years) { throw 'Valid warmup boundary rejected.' }
    }
    $commented = Read-TestConfig ("; experiment" + [Environment]::NewLine + "# settings" +
        [Environment]::NewLine + $base.Replace('Fast=2,4', '  Fast = 2, 4  '))
    if ($commented.Grid.Count -ne 4) { throw 'Whitespace or configuration comments changed the grid.' }

    $cases = @(
        @{ Name = 'reversed dates'; Text = $base.Replace('To=2021-01-01', 'To=2019-01-01'); Error = 'From must precede To.' }
        @{ Name = 'equal dates'; Text = $base.Replace('To=2021-01-01', 'To=2020-01-01'); Error = 'From must precede To.' }
        @{ Name = 'invalid date'; Text = $base.Replace('From=2020-01-01', 'From=2020-02-30'); Error = '*ParseExact*' }
        @{ Name = 'duplicate section'; Text = $base + [Environment]::NewLine + '[Backtest]'; Error = 'Duplicate section:*' }
        @{ Name = 'duplicate setting'; Text = $base.Replace('Symbol=EURUSD', "Symbol=EURUSD" + [Environment]::NewLine + 'Symbol=USDJPY'); Error = 'Duplicate key:*' }
        @{ Name = 'duplicate parameter'; Text = $base + [Environment]::NewLine + 'Fast=8'; Error = 'Duplicate key:*' }
        @{ Name = 'unknown setting'; Text = $base.Replace('Symbol=EURUSD', "Symbol=EURUSD" + [Environment]::NewLine + 'Unknown=1'); Error = 'Expected Symbol*' }
        @{ Name = 'missing symbol'; Text = $base.Replace('Symbol=EURUSD', ''); Error = 'Expected Symbol*' }
        @{ Name = 'missing timeframe'; Text = $base.Replace('Timeframe=H4', ''); Error = 'Expected Symbol*' }
        @{ Name = 'invalid timeframe'; Text = $base.Replace('Timeframe=H4', 'Timeframe=H99'); Error = 'Expected Symbol*' }
        @{ Name = 'invalid symbol'; Text = $base.Replace('Symbol=EURUSD', 'Symbol=EUR/USD'); Error = 'Expected Symbol*' }
        @{ Name = 'missing parameter'; Text = $base.Replace('Slow=12,24', ''); Error = 'Expected integer strategy parameters:*' }
        @{ Name = 'unknown parameter'; Text = $base.Replace('Slow=12,24', 'Other=12'); Error = 'Expected integer strategy parameters:*' }
        @{ Name = 'decimal parameter'; Text = $base.Replace('Fast=2,4', 'Fast=2.5'); Error = 'Invalid integer for Fast.' }
        @{ Name = 'text parameter'; Text = $base.Replace('Fast=2,4', 'Fast=abc'); Error = 'Invalid integer for Fast.' }
        @{ Name = 'integer overflow'; Text = $base.Replace('Fast=2,4', 'Fast=2147483648'); Error = 'Invalid integer for Fast.' }
        @{ Name = 'empty grid element'; Text = $base.Replace('Fast=2,4', 'Fast=2,,4'); Error = 'Invalid integer for Fast.' }
        @{ Name = 'fixed fast grid'; Text = $base; Fixed = $true; Error = 'Live requires one fixed value for Fast.' }
        @{ Name = 'fixed slow grid'; Text = $base.Replace('Fast=2,4', 'Fast=2'); Fixed = $true; Error = 'Live requires one fixed value for Slow.' }
    )
    foreach ($cost in '-0.10','0,10','NaN','Infinity','1e3','999999999999999999999999999999999') {
        $cases += @{
            Name = "invalid cost $cost"
            Text = $base.Replace('[Backtest]', "[Backtest]" + [Environment]::NewLine + "ExtraCostPerExecutionUSD=$cost")
            Error = 'ExtraCostPerExecutionUSD must be*'
        }
    }
    foreach ($years in '-1','11','1.5','abc','2147483648') {
        $cases += @{
            Name = "invalid warmup $years"
            Text = $base.Replace('[Backtest]', "[Backtest]" + [Environment]::NewLine + "WarmupYears=$years")
            Error = 'WarmupYears must be*'
        }
    }
    foreach ($case in $cases) {
        $fixed = $case.ContainsKey('Fixed') -and $case.Fixed
        $message = $null
        try { Read-TestConfig $case.Text -Fixed $fixed | Out-Null }
        catch { $message = $_.Exception.Message }
        if (!$message -or $message -notlike $case.Error) {
            throw "Configuration case '$($case.Name)' failed. Expected '$($case.Error)', got '$message'."
        }
    }
    Write-Output "Experiment config: PASS (grids, fixed inputs, defaults, locale and $($cases.Count) invalid cases)"
} finally {
    Remove-Item -LiteralPath $configPath,$strategyPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp
}
