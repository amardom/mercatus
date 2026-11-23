#property strict

int fail_fixture(const string stage)
{
   Print("Fixture failure: ", stage, " error=", GetLastError());
   return 1;
}

bool set_integer(const string symbol, const ENUM_SYMBOL_INFO_INTEGER property, const long value)
{
   bool ok = CustomSymbolSetInteger(symbol, property, value);
   if(!ok) Print("Integer property failed: ", EnumToString(property), " error=", GetLastError());
   return ok;
}

bool set_double(const string symbol, const ENUM_SYMBOL_INFO_DOUBLE property, const double value)
{
   bool ok = CustomSymbolSetDouble(symbol, property, value);
   if(!ok) Print("Double property failed: ", EnumToString(property), " error=", GetLastError());
   return ok;
}

int create_fixture(const string symbol, const int variant)
{

   bool custom = false;
   if(SymbolExist(symbol, custom))
   {
      if(!custom) return fail_fixture("symbol is not custom");
   }
   else if(!CustomSymbolCreate(symbol, "Mercatus")) return fail_fixture("create");
   if(!CustomSymbolSetString(symbol, SYMBOL_CURRENCY_BASE, "USD") ||
      !CustomSymbolSetString(symbol, SYMBOL_CURRENCY_PROFIT, "USD") ||
      !CustomSymbolSetString(symbol, SYMBOL_CURRENCY_MARGIN, "USD")) return fail_fixture("currencies");
   if(!set_integer(symbol, SYMBOL_DIGITS, 2) ||
      !set_integer(symbol, SYMBOL_TRADE_CALC_MODE, SYMBOL_CALC_MODE_FOREX) ||
      !set_integer(symbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_FULL) ||
      !set_integer(symbol, SYMBOL_TRADE_EXEMODE, SYMBOL_TRADE_EXECUTION_INSTANT) ||
      !set_integer(symbol, SYMBOL_FILLING_MODE, SYMBOL_FILLING_FOK | SYMBOL_FILLING_IOC) ||
      !set_integer(symbol, SYMBOL_ORDER_MODE, SYMBOL_ORDER_MARKET) ||
      !set_integer(symbol, SYMBOL_SPREAD, 2) ||
      !set_integer(symbol, SYMBOL_SPREAD_FLOAT, false) ||
      !set_integer(symbol, SYMBOL_CHART_MODE, SYMBOL_CHART_MODE_BID) ||
      !set_integer(symbol, SYMBOL_SWAP_MODE, SYMBOL_SWAP_MODE_DISABLED) ||
      !set_double(symbol, SYMBOL_POINT, 0.01) ||
      !set_double(symbol, SYMBOL_TRADE_TICK_SIZE, 0.01) ||
      !set_double(symbol, SYMBOL_TRADE_TICK_VALUE, 0.01) ||
      !set_double(symbol, SYMBOL_TRADE_CONTRACT_SIZE, 1.0) ||
      !set_double(symbol, SYMBOL_VOLUME_MAX, 1000.0) ||
      !set_double(symbol, SYMBOL_VOLUME_STEP, 1.0) ||
      !set_double(symbol, SYMBOL_VOLUME_MIN, 1.0)) return fail_fixture("properties");
   for(int day = 0; day < 7; day++)
   {
      if(!CustomSymbolSetSessionQuote(symbol, (ENUM_DAY_OF_WEEK)day, 0, 0, 86399) ||
         !CustomSymbolSetSessionTrade(symbol, (ENUM_DAY_OF_WEEK)day, 0, 0, 86399)) return fail_fixture("sessions");
   }
   datetime start = D'2025.12.29 00:00';
   datetime end = D'2026.01.07 00:00';
   datetime fixture = D'2026.01.05 00:00';
   double prices[] = {100,101,102,103,104,103,102,101,100,99,98,99,100,101,102,103,102,101,100,99,98,97,96,95};
   if(variant != 0)
   {
      fixture = D'2026.01.08';
      end = D'2026.01.17';
   }
   int minutes = (int)((end - start) / 60);
   MqlRates rates[];
   MqlTick ticks[];
   ArrayResize(rates, minutes);
   ArrayResize(ticks, minutes * 2);
   ZeroMemory(rates);
   ZeroMemory(ticks);
   for(int i = 0; i < minutes; i++)
   {
      datetime time = start + i * 60;
      int hour = (int)((time - fixture) / 3600);
      double price = time < fixture ? 100.0 : (hour < 24 ? prices[hour] : 95.0);
      if(variant != 0 && time >= fixture)
      {
         int day = hour / 24;
         price = prices[hour % 24] + day;
         if(variant == 2 && time >= D'2026.01.12')
            price = 150.0 - 2.0 * prices[hour % 24] + day + 100.0;
      }
      rates[i].time = time;
      rates[i].open = price;
      rates[i].high = price;
      rates[i].low = price;
      rates[i].close = price;
      rates[i].tick_volume = 2;
      rates[i].spread = 2;
      for(int j = 0; j < 2; j++)
      {
         int index = i * 2 + j;
         ticks[index].time = time + (j == 0 ? 0 : 59);
         ticks[index].time_msc = (long)ticks[index].time * 1000;
         ticks[index].bid = price;
         ticks[index].ask = NormalizeDouble(price + 0.02, 2);
         ticks[index].flags = TICK_FLAG_BID | TICK_FLAG_ASK;
      }
   }
   if(CustomRatesReplace(symbol, start, end, rates) != minutes) return fail_fixture("rates");
   if(!SymbolSelect(symbol, true)) return fail_fixture("selection");
   if(CustomTicksReplace(symbol, (long)start * 1000, (long)end * 1000, ticks) != minutes * 2) return fail_fixture("ticks");
   PrintFormat("Mercatus fixture: %d bars, %d ticks (%s)", minutes, minutes * 2, symbol);
   return 0;
}

int OnStart()
{
   if(create_fixture("MERCATUS_SYNTH", 0) != 0) return 1;
   if(create_fixture("MERCATUS_PAST_A", 1) != 0) return 1;
   return create_fixture("MERCATUS_PAST_B", 2);
}
