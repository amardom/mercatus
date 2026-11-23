# Mercatus

A local MQL5 laboratory for Forex strategies using MT5 Strategy Tester.

## Setup

Install MetaTrader 5 on Windows, sign in to MetaQuotes-Demo, then close MT5.
Run commands from the repository root in Windows PowerShell.
The tools use the standard MT5 installation and its configured data folder.

## Run

Walk-forward backtest:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Backtester.ps1 -Strategy MovingAverage -Config .\strategies\MovingAverage\MovingAverage.inib
~~~

The interval is split into nine segments. Each of five rolling passes selects
parameters on four segments by net annualized Sharpe and applies them to the
next segment. The five out-of-sample segments run continuously, carrying
balance, positions and risk state.

Historical simulation with fixed parameters:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\LiveSimulator.ps1 -Strategy MovingAverage -Config .\strategies\MovingAverage\MovingAverage.inil
~~~

Use one fixed value per input in .inil and one value or a comma-separated grid
in .inib. From is inclusive; To is exclusive. Dates use MT5 server time.
Optional [Backtest] settings:

- ExtraCostPerExecutionUSD=0.10 adds a surcharge to every buy or sell execution.
  The default is zero. It enters net Sharpe selection and the published curve.
  MT5 risk decisions use equity before this surcharge.
- WarmupYears=1 loads an earlier period, excluding it from trades and metrics.
- Increase -TimeoutSeconds for large history downloads.
  Backtester accepts -NoOpenChart for unattended runs.

## Output

Results are saved under outputs/walkforward/ or outputs/backtest/.

- summary.csv contains results and costs.
- schedule.csv and out_of_sample.csv describe the walk-forward segments.
- equity.csv and equity.svg show daily equity after all modeled costs.
- recipe.json, saved configurations and per-run files record the experiment.

Runs use USD 10,000, 1:100 margin leverage and the symbol's minimum lot.
Supported Forex pairs have USD as their base or quote currency.
A 15% equity drawdown blocks new entries for the remainder of the run.
Positions close according to the strategy or at the end of the test.
Sharpe uses daily returns, sample standard deviation, 252 days and a zero
risk-free rate. MT5 may generate ticks where real ticks are unavailable;
review the native reports and tester logs when assessing data coverage.

## Add a strategy

Create a folder whose files share its name:

~~~text
strategies/YourStrategy/
    YourStrategy.mqh
    YourStrategy.inib
    YourStrategy.inil
~~~

Declare integer inputs with input int and implement these functions in .mqh:

~~~cpp
int get_strategy_lookback();

bool compute_strategy_signal(
   const MqlRates &bars[],
   const int bars_held,
   const PositionTarget current,
   PositionTarget &target
);
~~~

get_strategy_lookback() returns the number of closed bars required.
bars is chronological, with the latest closed bar last.
bars_held is -1 while flat and 0 on the entry bar.
current and target use TARGET_LONG, TARGET_SHORT or TARGET_FLAT.
Return false for invalid inputs. Signals are evaluated on the first valid tick
of each new bar. A reversal closes the current position before opening the
opposite side.

Copy an existing configuration and match every [Parameters] key to an input.
Add tests/Strategies/Test_YourStrategy.mq5 using Test_Assertions.mqh and print
Strategy test: YourStrategy PASS only after all checks pass.
RunTests.ps1 discovers the file automatically.

## Tests

With MT5 closed:

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Strategies\RunTests.ps1
~~~

Tool integration tests are in tests/Backtester/ and tests/LiveSimulator/.
Shared execution, Sharpe and chart tests are at the root of tests/.

## License

[MIT](LICENSE). MetaTrader 5 and broker market data remain subject to their
respective terms.
