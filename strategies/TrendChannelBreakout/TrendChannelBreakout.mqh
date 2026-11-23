input int Lookback = 48;

int get_strategy_lookback()
{
   return Lookback >= 2 && Lookback < INT_MAX ? Lookback + 1 : 0;
}

bool compute_strategy_signal(const MqlRates &bars[], const int bars_held, const PositionTarget current, PositionTarget &target)
{
   int required = get_strategy_lookback();
   int count = ArraySize(bars);
   if(required == 0 || count < required || ArrayGetAsSeries(bars)) return false;
   if(current != TARGET_FLAT && current != TARGET_LONG && current != TARGET_SHORT) return false;

   int signal_bar = count - 1;
   int length = current == TARGET_FLAT ? Lookback : Lookback / 2;
   int first = signal_bar - length;
   double highest = bars[first].high;
   double lowest = bars[first].low;
   for(int i = first; i < signal_bar; i++)
   {
      if(!MathIsValidNumber(bars[i].high) || !MathIsValidNumber(bars[i].low)) return false;
      highest = MathMax(highest, bars[i].high);
      lowest = MathMin(lowest, bars[i].low);
   }
   double close = bars[signal_bar].close;
   if(!MathIsValidNumber(close)) return false;

   target = current;
   if(current == TARGET_FLAT)
   {
      if(close > highest) target = TARGET_LONG;
      if(close < lowest) target = TARGET_SHORT;
   }
   else if((current == TARGET_LONG && close < lowest) ||
           (current == TARGET_SHORT && close > highest))
      target = TARGET_FLAT;
   return true;
}
