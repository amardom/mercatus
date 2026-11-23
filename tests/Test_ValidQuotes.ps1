param([string]$MetaTraderDirectory = (Join-Path $env:ProgramFiles 'MetaTrader 5'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Get-Process terminal64 -ErrorAction SilentlyContinue) { throw 'Close MetaTrader 5 before running this test.' }
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$simulator = Get-Content -LiteralPath (Join-Path $project 'experts\Simulator.mq5') -Raw
$handler = [regex]::Match($simulator, '(?s)void process_tick\(\)\s*\{.*?\r?\n\}(?=\s*void OnTick\(\))')
if (!$handler.Success) { throw 'Could not locate the simulator tick handler.' }
$positions = Get-Content -LiteralPath (Join-Path $project 'experts\PositionTarget.mqh') -Raw
$token = [guid]::NewGuid().ToString('N')
$name = "Test_ValidQuotes_$token"
$temp = Join-Path $env:TEMP "mercatus-quotes-$token"
$terminalRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
$data = @(Get-ChildItem -LiteralPath $terminalRoot -Directory | Where-Object {
    $origin = Join-Path $_.FullName 'origin.txt'
    (Test-Path -LiteralPath $origin) -and (Get-Content -LiteralPath $origin -Raw).Trim() -eq $MetaTraderDirectory.TrimEnd('\')
})
if ($data.Count -ne 1) { throw 'Could not locate the desktop MT5 data folder.' }
$binary = Join-Path $data[0].FullName "MQL5\Scripts\$name.ex5"
New-Item -ItemType Directory -Path $temp | Out-Null

function Invoke-TestProcess($file, $arguments) {
    $process = Start-Process -FilePath $file -ArgumentList $arguments -WindowStyle Hidden -PassThru
    try {
        if (!$process.WaitForExit(120000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Timed out: $file"
        }
        return $process.ExitCode
    } finally { $process.Dispose() }
}

try {
    $source = Join-Path $temp "$name.mq5"
    $mocks = @'
MqlTick quote = {};
datetime bar_time = D'2026.01.05 02:00';
datetime last_bar = 0;
double peak_equity = 10000;
double contract_size = 1;
double trade_volume = 1;
bool account_currency_is_base = false;
bool entries_blocked = false;
bool failed = false;
int blocked_count = 0;
int decision_file = INVALID_HANDLE;
int history_calls = 0;
int bar_calls = 0;
int executions = 0;
const ulong magic = 20260105;

bool read_quote(const string symbol, MqlTick &result) { result = quote; return true; }
double read_equity(const ENUM_ACCOUNT_INFO_DOUBLE property) { return 10000; }
int position_count() { return 0; }
datetime read_bar(const string symbol, const ENUM_TIMEFRAMES period, const int shift)
{
   bar_calls++;
   return bar_time;
}
int read_history(const string symbol, const ENUM_TIMEFRAMES period, const int start, const int count, MqlRates &bars[])
{
   history_calls++;
   ArrayResize(bars, count);
   ZeroMemory(bars);
   return count;
}
int get_strategy_lookback() { return 1; }
bool compute_strategy_signal(const MqlRates &bars[], const int held, const PositionTarget current, PositionTarget &target)
{
   target = TARGET_LONG;
   return true;
}
void stop_test(const string reason) { failed = true; Print(reason); }
void update_drawdown(const double equity) {}
bool execute_deal(const ENUM_ORDER_TYPE type, const double volume, const double price, const MqlTick &tick, const ulong position = 0)
{
   if(type != ORDER_TYPE_BUY || volume != 1 || price != 102.02 || tick.bid != 102) failed = true;
   executions++;
   return true;
}
#define SymbolInfoTick read_quote
#define AccountInfoDouble read_equity
#define PositionsTotal position_count
#define iTime read_bar
#define CopyRates read_history
'@
    $checks = @'
int check_quotes()
{
   quote.bid = 0;
   quote.ask = 102.02;
   process_tick();
   quote.bid = 102;
   quote.ask = 0;
   process_tick();
   quote.bid = 0;
   quote.ask = 0;
   process_tick();
   if(failed || last_bar != 0 || bar_calls != 0 || history_calls != 0 || executions != 0) return 1;
   quote.bid = 102;
   quote.ask = 102.02;
   process_tick();
   if(failed || last_bar != bar_time || history_calls != 1 || executions != 1) return 1;
   process_tick();
   if(failed || history_calls != 1 || executions != 1) return 1;
   Print("Valid quotes: PASS");
   return 0;
}
int OnStart()
{
   string output = MQLInfoString(MQL_PROGRAM_NAME) + ".csv";
   decision_file = FileOpen(output, FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(decision_file == INVALID_HANDLE) return 1;
   int result = check_quotes();
   FileClose(decision_file);
   FileDelete(output);
   return result;
}
'@
    @('#property strict', $positions, $mocks, $handler.Value, $checks) |
        Set-Content -LiteralPath $source -Encoding ASCII
    $code = Invoke-TestProcess (Join-Path $MetaTraderDirectory 'MetaEditor64.exe') @(('/compile:"' + $source + '"'), '/log')
    $log = Get-Content -LiteralPath ([IO.Path]::ChangeExtension($source, '.log')) -Raw
    if ($code -notin 0,1 -or $log -notmatch 'Result: 0 errors, 0 warnings') { throw $log }
    Copy-Item -LiteralPath ([IO.Path]::ChangeExtension($source, '.ex5')) -Destination $binary
    $config = Join-Path $temp 'run.ini'
    @('[Experts]', 'Enabled=0', 'AllowLiveTrading=0', 'AllowDllImport=0',
      '[StartUp]', 'Symbol=EURUSD', 'Period=H1', "Script=$name.ex5",
      'ShutdownTerminal=1') | Set-Content -LiteralPath $config -Encoding ASCII
    $code = Invoke-TestProcess (Join-Path $MetaTraderDirectory 'terminal64.exe') @(('/config:"' + $config + '"'))
    $pattern = [regex]::Escape($name) + '.*Valid quotes: PASS'
    $logs = Join-Path $data[0].FullName 'MQL5\Logs'
    if ($code -ne 0 -or !(Get-ChildItem -LiteralPath $logs -Filter '*.log' -File | Select-String -Pattern $pattern -Quiet)) {
        throw 'Valid quote handling failed. See the MT5 Experts log.'
    }
    Write-Output 'Valid quotes: PASS (invalid quotes, same-bar recovery and single execution)'
} finally {
    Remove-Item -LiteralPath $binary -ErrorAction SilentlyContinue
    $resolved = (Resolve-Path -LiteralPath $temp).ProviderPath
    $expected = Join-Path ([IO.Path]::GetFullPath($env:TEMP)) "mercatus-quotes-$token"
    if ($resolved -cne $expected) { throw 'Unexpected test workspace.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
