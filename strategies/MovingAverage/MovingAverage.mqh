input int Fast = 2;
input int Slow = 4;

int get_strategy_lookback()
{
   return Fast > 0 && Fast < Slow ? Slow : 0;
}

bool compute_strategy_signal(const MqlRates &bars[], const int bars_held, const PositionTarget current, PositionTarget &target)
{
   int count = ArraySize(bars);
   if(get_strategy_lookback() == 0 || count < Slow || ArrayGetAsSeries(bars))
      return false;
   double fast_sum = 0.0;
   double slow_sum = 0.0;
   for(int i = count - Slow; i < count; i++)
   {
      if(!MathIsValidNumber(bars[i].close)) return false;
      slow_sum += bars[i].close;
      if(i >= count - Fast) fast_sum += bars[i].close;
   }
   if(!MathIsValidNumber(fast_sum) || !MathIsValidNumber(slow_sum)) return false;
   target = (fast_sum / Fast > slow_sum / Slow) ? TARGET_LONG : TARGET_FLAT;
   return true;
}
