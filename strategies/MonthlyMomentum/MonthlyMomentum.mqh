input int LookbackMonths = 12;

int get_strategy_lookback()
{
   return LookbackMonths >= 1 && LookbackMonths <= 120 ? 1 : 0;
}

bool compute_monthly_target(const MqlRates &bars[], const datetime decision_time, PositionTarget &target)
{
   int count = ArraySize(bars);
   if(get_strategy_lookback() == 0 || count < 2 || ArrayGetAsSeries(bars)) return false;
   MqlDateTime month;
   if(!TimeToStruct(decision_time, month)) return false;
   month.day = 1;
   month.hour = 0;
   month.min = 0;
   month.sec = 0;
   datetime end = StructToTime(month);
   int index = month.year * 12 + month.mon - 1 - LookbackMonths;
   month.year = index / 12;
   month.mon = index % 12 + 1;
   datetime start = StructToTime(month);

   int first = -1;
   int last = -1;
   for(int i = 0; i < count; i++)
   {
      if(bars[i].time <= 0 || (i > 0 && bars[i].time <= bars[i - 1].time)) return false;
      if(bars[i].time < start) first = i;
      if(bars[i].time < end) last = i;
   }
   if(first < 0 || last <= first) return false;
   double initial_close = bars[first].close;
   double final_close = bars[last].close;
   if(!MathIsValidNumber(initial_close) || !MathIsValidNumber(final_close) ||
      initial_close <= 0.0 || final_close <= 0.0) return false;

   target = TARGET_FLAT;
   if(final_close > initial_close) target = TARGET_LONG;
   if(final_close < initial_close) target = TARGET_SHORT;
   return true;
}

bool compute_strategy_signal(const MqlRates &bars[], const int bars_held, const PositionTarget current, PositionTarget &target)
{
   if(_Period != PERIOD_D1) return false;
   MqlRates months[];
   int required = LookbackMonths + 1;
   if(CopyRates(_Symbol, PERIOD_MN1, 1, required, months) != required) return false;
   return compute_monthly_target(months, TimeCurrent(), target);
}
