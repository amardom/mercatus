bool expect_target(const string name, const MqlRates &bars[], const int bars_held, const PositionTarget expected, const PositionTarget current = TARGET_FLAT)
{
   PositionTarget actual = TARGET_FLAT;
   if(compute_strategy_signal(bars, bars_held, current, actual) && actual == expected) return true;
   Print("Strategy test failed: ", name, ", target=", EnumToString(actual));
   return false;
}

void load_closes(MqlRates &bars[], const int count, const double close)
{
   ArrayResize(bars, count);
   for(int i = 0; i < count; i++) bars[i].close = close;
}
