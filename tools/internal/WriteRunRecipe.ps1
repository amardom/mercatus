function Get-RunGitState {
    param([string]$ProjectRoot)

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    $prefix = @('-C', $ProjectRoot)
    if ($wsl -and $ProjectRoot -match '^\\\\(?:wsl\.localhost|wsl\$)\\([^\\]+)\\(.+)$') {
        $git = $wsl
        $prefix = @('-d', $Matches[1], '-e', 'git', '-C', ('/' + $Matches[2].Replace('\', '/')))
    }
    if (!$git) { return @{ Commit = $null; Dirty = $null } }
    $ErrorActionPreference = 'Continue'
    $commit = & $git.Source @prefix rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return @{ Commit = $null; Dirty = $null } }
    $changes = @(& $git.Source @prefix status --porcelain 2>$null)
    $dirty = if ($LASTEXITCODE -eq 0) { $changes.Count -gt 0 } else { $null }
    return @{ Commit = [string]$commit; Dirty = $dirty }
}
