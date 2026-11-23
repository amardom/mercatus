#property strict
#include "PositionTarget.mqh"
#include "SelectedStrategy.mqh"


input string RunId = "manual";
input double DrawdownLimit = 0.15;
input datetime TradingFrom = 0;

const ulong magic = 20260105;
datetime last_bar = 0;
double peak_equity = 0.0;
bool failed = false;
bool entries_blocked = false;
double max_drawdown = 0.0;
datetime first_tick = 0;
datetime last_tick = 0;
long tick_count = 0;
int spread_samples = 0;
double spread_points_sum = 0.0;
double max_spread_points = 0.0;
long equity_day = -1;
int equity_file = INVALID_HANDLE;
double closing_equity;
double previous_close;
double initial_balance;
int return_count = 0;
double mean_return = 0.0;
double return_m2 = 0.0;
bool valid_returns = true;

void record_daily_return(const double equity)
{
   FileWrite(equity_file, TimeToString((datetime)(equity_day * 86400), TIME_DATE), DoubleToString(equity, 8));
   if(previous_close <= 0.0 || !MathIsValidNumber(equity))
   {
      valid_returns = false;
      return;
   }
   double daily_return = equity / previous_close - 1.0;
   previous_close = equity;
   return_count++;
   double delta = daily_return - mean_return;
   mean_return += delta / return_count;
   return_m2 += delta * (daily_return - mean_return);
}

string format_annualized_sharpe()
{
   if(!valid_returns || return_count < 2 || return_m2 <= 0.0) return "";
   double sharpe = MathSqrt(252.0) * mean_return / MathSqrt(return_m2 / (return_count - 1));
   return MathIsValidNumber(sharpe) ? DoubleToString(sharpe, 8) : "";
}
double contract_size;
double trade_volume;
bool account_currency_is_base;
int decision_file = INVALID_HANDLE;
int blocked_count = 0;

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
   contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   trade_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   string account_currency = AccountInfoString(ACCOUNT_CURRENCY);
   account_currency_is_base = account_currency == SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   if((!account_currency_is_base && account_currency != SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT)) ||
      SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX ||
      contract_size <= 0.0 || trade_volume <= 0.0) return INIT_FAILED;
   if(get_strategy_lookback() <= 0 || !MathIsValidNumber(DrawdownLimit) || DrawdownLimit <= 0.0 || DrawdownLimit > 1.0) return INIT_PARAMETERS_INCORRECT;
   if(StringLen(RunId) == 0 || StringFind(RunId, "\\") >= 0 || StringFind(RunId, "/") >= 0 || StringFind(RunId, "..") >= 0)
      return INIT_PARAMETERS_INCORRECT;
   peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   previous_close = peak_equity;
   initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   equity_file = FileOpen("Mercatus\\" + RunId + "-equity.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(equity_file == INVALID_HANDLE) return INIT_FAILED;
   FileWrite(equity_file, "Date", "Equity");
   FileWrite(equity_file, "", DoubleToString(peak_equity, 8));
   decision_file = FileOpen("Mercatus\\" + RunId + "-decisions.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(decision_file == INVALID_HANDLE) return INIT_FAILED;
   FileWrite(decision_file, "time", "signal", "entry_blocked", "equity", "drawdown", "current_exposure", "target_exposure", "bid", "ask", "active_parameters");
   return INIT_SUCCEEDED;
}

void stop_test(const string reason)
{
   failed = true;
   Print("Mercatus backtest failure: ", reason, " error=", GetLastError());
   ExpertRemove();
}

bool execute_deal(const ENUM_ORDER_TYPE type, const double volume, const double price, const MqlTick &tick, const ulong position = 0)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.magic = magic;
   request.type = type;
   request.volume = volume;
   request.price = price;
   request.position = position;
   request.type_filling = ORDER_FILLING_FOK;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE) == SYMBOL_TRADE_EXECUTION_MARKET &&
      (SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE) & SYMBOL_FILLING_FOK) == 0)
      request.type_filling = ORDER_FILLING_IOC;
   if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
   {
      PrintFormat("Trade rejected: %u %s", result.retcode, result.comment);
      return false;
   }
   double spread_points = (tick.ask - tick.bid) / _Point;
   spread_samples++;
   spread_points_sum += spread_points;
   max_spread_points = MathMax(max_spread_points, spread_points);
   return true;
}

void update_drawdown(const double equity)
{
   peak_equity = MathMax(peak_equity, equity);
   double drawdown = peak_equity > 0.0 ? 1.0 - equity / peak_equity : 1.0;
   max_drawdown = MathMax(max_drawdown, drawdown);
   if(drawdown >= DrawdownLimit) entries_blocked = true;
}

void process_tick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) { stop_test("missing tick"); return; }
   if(tick.bid <= 0.0 || tick.ask <= 0.0) return;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   update_drawdown(equity);
   double drawdown = peak_equity > 0.0 ? 1.0 - equity / peak_equity : 1.0;
   datetime current_bar = iTime(_Symbol, _Period, 0);
   if(current_bar <= 0 || current_bar == last_bar) return;
   last_bar = current_bar;
#ifdef MERCATUS_SCHEDULE
   apply_schedule(tick.time);
#endif
   int lookback = get_strategy_lookback();
   MqlRates history[];
   if(CopyRates(_Symbol, _Period, 1, lookback, history) != lookback)
   { stop_test("insufficient closed history"); return; }
   if(PositionsTotal() > 1) { stop_test("unexpected position count"); return; }
   ulong ticket = 0;
   double volume = 0.0;
   PositionTarget current = TARGET_FLAT;
   if(PositionsTotal() == 1)
   {
      ticket = PositionGetTicket(0);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != magic)
      { stop_test("unexpected position"); return; }
      current = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? TARGET_LONG : TARGET_SHORT;
      volume = PositionGetDouble(POSITION_VOLUME);
   }
   int bars_held = -1;
   if(ticket != 0)
   {
      bars_held = iBarShift(_Symbol, _Period, (datetime)PositionGetInteger(POSITION_TIME));
      if(bars_held < 0) { stop_test("missing position entry bar"); return; }
   }
   PositionTarget signal = TARGET_FLAT;
   if(!compute_strategy_signal(history, bars_held, current, signal) ||
      (signal != TARGET_LONG && signal != TARGET_SHORT && signal != TARGET_FLAT))
   { stop_test("invalid strategy signal"); return; }
   double exposure_rate = account_currency_is_base ? 1.0 : tick.ask;
   double current_exposure = volume * exposure_rate * contract_size;
   double entry_exposure = trade_volume * exposure_rate * contract_size;

   if(ticket != 0 && current != signal)
   {
      ENUM_ORDER_TYPE close_type = current == TARGET_LONG ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double close_price = current == TARGET_LONG ? tick.bid : tick.ask;
      if(!execute_deal(close_type, volume, close_price, tick, ticket) || PositionsTotal() != 0)
      { stop_test("close failed"); return; }
      current = TARGET_FLAT;
      update_drawdown(AccountInfoDouble(ACCOUNT_EQUITY));
   }

   bool opening = signal != TARGET_FLAT && current == TARGET_FLAT;
   bool blocked = opening && entries_blocked;
   string active_parameters = "";
#ifdef MERCATUS_SCHEDULE
   active_parameters = format_active_parameters();
#endif
   string signal_name = signal == TARGET_LONG ? "LONG" : (signal == TARGET_SHORT ? "SHORT" : "CASH");
   FileWrite(decision_file, TimeToString(tick.time, TIME_DATE | TIME_SECONDS),
             signal_name, blocked, equity, drawdown, current_exposure,
             signal == TARGET_FLAT ? 0.0 : entry_exposure, tick.bid, tick.ask, active_parameters);
   if(blocked) { blocked_count++; return; }
   if(opening)
   {
      ENUM_ORDER_TYPE open_type = signal == TARGET_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double open_price = signal == TARGET_LONG ? tick.ask : tick.bid;
      if(!execute_deal(open_type, trade_volume, open_price, tick)) stop_test("open failed");
   }
}


void OnTick()
{
   if(TimeCurrent() < TradingFrom) return;
   last_tick = TimeCurrent();
   if(tick_count == 0) first_tick = last_tick;
   tick_count++;
   long day = (long)last_tick / 86400;
   if(equity_day >= 0 && day != equity_day) record_daily_return(closing_equity);
   process_tick();
   equity_day = day;
   closing_equity = AccountInfoDouble(ACCOUNT_EQUITY);
}

double OnTester()
{
   if(!HistorySelect(0, TimeCurrent())) { stop_test("missing deal history"); return -1.0; }
   int deal_file = FileOpen("Mercatus\\" + RunId + "-deals.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(deal_file == INVALID_HANDLE) return -1.0;
   FileWrite(deal_file, "time", "type", "entry", "volume", "price", "profit", "commission", "swap", "fee");
   int trade_count = 0;
   double pnl_before_charges = 0.0;
   double commissions = 0.0;
   double swaps = 0.0;
   double fees = 0.0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      ENUM_DEAL_TYPE type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
      datetime time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      double price = HistoryDealGetDouble(deal, DEAL_PRICE);
      double size = HistoryDealGetDouble(deal, DEAL_VOLUME);
      double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(deal, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(deal, DEAL_SWAP);
      double fee = HistoryDealGetDouble(deal, DEAL_FEE);
      FileWrite(deal_file, TimeToString(time, TIME_DATE | TIME_SECONDS), EnumToString(type),
                HistoryDealGetInteger(deal, DEAL_ENTRY), size, price, profit, commission, swap, fee);
      pnl_before_charges += profit;
      commissions += commission;
      swaps += swap;
      fees += fee;
      trade_count++;
   }
   FileClose(deal_file);
   double net_profit = pnl_before_charges + commissions + swaps + fees;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(equity_day >= 0) record_daily_return(AccountInfoDouble(ACCOUNT_EQUITY));
   int metrics = FileOpen("Mercatus\\" + RunId + "-metrics.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(metrics == INVALID_HANDLE) failed = true;
   else
   {
      FileWrite(metrics, "Executions", "NetProfit", "MaxEquityDrawdownPct", "AnnualizedSharpe",
                "PnLBeforeCharges", "Commission", "Swap", "Fee", "BalanceResidual", "FinalBalance", "BlockedEntries", "OpenPositions",
                "SpreadSamples", "MeanOrderSpreadPoints", "MaxOrderSpreadPoints",
                "FirstTick", "LastTick", "TicksProcessed", "CustomSymbol", "TesterBuild");
      FileWrite(metrics, trade_count, DoubleToString(net_profit, 8), DoubleToString(100.0 * max_drawdown, 8), format_annualized_sharpe(),
                DoubleToString(pnl_before_charges, 8), DoubleToString(commissions, 8),
                DoubleToString(swaps, 8), DoubleToString(fees, 8), DoubleToString(balance - initial_balance - net_profit, 8),
                DoubleToString(balance, 8), blocked_count, PositionsTotal(),
                spread_samples, spread_samples > 0 ? DoubleToString(spread_points_sum / spread_samples, 4) : "",
                spread_samples > 0 ? DoubleToString(max_spread_points, 4) : "",
                tick_count > 0 ? TimeToString(first_tick, TIME_DATE | TIME_SECONDS) : "",
                tick_count > 0 ? TimeToString(last_tick, TIME_DATE | TIME_SECONDS) : "", tick_count,
                (int)SymbolInfoInteger(_Symbol, SYMBOL_CUSTOM), TerminalInfoInteger(TERMINAL_BUILD));
      FileClose(metrics);
   }
   PrintFormat("MercatusSimulator: %s run=%s trades=%d net=%.2f balance=%.2f blocked=%d", failed ? "FAIL" : "PASS", RunId, trade_count, net_profit, balance, blocked_count);
   return failed ? -1.0 : 1.0;
}

void OnDeinit(const int reason)
{
   if(decision_file != INVALID_HANDLE) FileClose(decision_file);
   if(equity_file != INVALID_HANDLE) FileClose(equity_file);
}
