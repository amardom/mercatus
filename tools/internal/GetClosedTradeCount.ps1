function Get-ClosedTradeCount {
    param($Deals, [string]$From, [string]$To)

    $fromDate = $From.Replace('-', '.')
    $toDate = $To.Replace('-', '.')
    return @($Deals | Where-Object {
        $_.entry -eq '1' -and $_.time -ge $fromDate -and $_.time -lt $toDate
    }).Count
}
