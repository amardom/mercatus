input int Lookback = 24;

int get_strategy_lookback()
{
   return Lookback > 0 && Lookback < INT_MAX ? Lookback + 1 : 0;
}

bool compute_strategy_signal(const MqlRates &bars[], const int bars_held, const PositionTarget current, PositionTarget &target)
{
   int required = get_strategy_lookback();
   int count = ArraySize(bars);
   if(required == 0 || count < required || ArrayGetAsSeries(bars)) return false;
   double latest_close = bars[count - 1].close;
   double earlier_close = bars[count - required].close;
   if(!MathIsValidNumber(latest_close) || !MathIsValidNumber(earlier_close)) return false;
   target = (latest_close > earlier_close) ? TARGET_LONG : (latest_close < earlier_close ? TARGET_SHORT : TARGET_FLAT);
   return true;
}
