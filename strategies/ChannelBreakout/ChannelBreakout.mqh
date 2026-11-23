input int Lookback = 24;

int get_strategy_lookback()
{
   return Lookback > 0 && Lookback < INT_MAX ? Lookback + 1 : 0;
}

bool compute_strategy_signal(const MqlRates &bars[], const int bars_held, const PositionTarget current, PositionTarget &target)
{
   int lookback = get_strategy_lookback();
   int count = ArraySize(bars);
   if(lookback == 0 || count < lookback || ArrayGetAsSeries(bars))
      return false;
   int first = count - lookback;
   double highest = bars[first].high;
   for(int i = first; i < count - 1; i++)
   {
      if(!MathIsValidNumber(bars[i].high)) return false;
      highest = MathMax(highest, bars[i].high);
   }
   double close = bars[count - 1].close;
   if(!MathIsValidNumber(close)) return false;
   target = (close > highest) ? TARGET_LONG : TARGET_FLAT;
   return true;
}
