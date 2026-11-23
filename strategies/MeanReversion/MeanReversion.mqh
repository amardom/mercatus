input int Lookback = 24;


int get_strategy_lookback()
{
   return Lookback >= 2 && Lookback < INT_MAX ? Lookback + 1 : 0;
}

bool compute_strategy_signal(const MqlRates &bars[], const int bars_held, const PositionTarget current, PositionTarget &target)
{
   int required = get_strategy_lookback();
   int count = ArraySize(bars);
   if(required == 0 || count < required || ArrayGetAsSeries(bars)) return false;

   int first = count - required;
   double mean = 0.0;
   double sum_squares = 0.0;
   for(int i = first; i < count - 1; i++)
   {
      double close = bars[i].close;
      if(!MathIsValidNumber(close)) return false;
      double delta = close - mean;
      mean += delta / (i - first + 1);
      sum_squares += delta * (close - mean);
   }

   double close = bars[count - 1].close;
   if(!MathIsValidNumber(close) || !MathIsValidNumber(sum_squares)) return false;
   if(current != TARGET_FLAT)
   {
      if(bars_held < 0 || (current != TARGET_LONG && current != TARGET_SHORT)) return false;
      bool reached_mean = current == TARGET_LONG ? close >= mean : close <= mean;
      target = reached_mean || bars_held >= Lookback ? TARGET_FLAT : current;
      return true;
   }

   double deviation = MathSqrt(MathMax(0.0, sum_squares / (Lookback - 1)));
   target = TARGET_FLAT;
   if(deviation > 0.0)
   {
      if(close < mean - 2.0 * deviation) target = TARGET_LONG;
      if(close > mean + 2.0 * deviation) target = TARGET_SHORT;
   }
   return true;
}
