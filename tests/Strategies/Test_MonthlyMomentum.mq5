#property strict
#include "../../experts/PositionTarget.mqh"
#include "../../strategies/MonthlyMomentum/MonthlyMomentum.mqh"

bool expect_monthly(const string name, const MqlRates &bars[], const datetime now, const PositionTarget expected)
{
   PositionTarget actual = TARGET_FLAT;
   if(compute_monthly_target(bars, now, actual) && actual == expected) return true;
   Print("Strategy test failed: ", name, " actual=", EnumToString(actual));
   return false;
}

int OnStart()
{
   MqlRates bars[];
   ArrayResize(bars, 5);
   bars[0].time = D'2023.12.29';
   bars[1].time = D'2024.01.31';
   bars[2].time = D'2024.12.31';
   bars[3].time = D'2025.01.15';
   bars[4].time = D'2025.01.31';
   bars[0].close = 100;
   bars[1].close = 110;
   bars[2].close = 120;
   bars[3].close = 1;
   bars[4].close = 90;
   if(!expect_monthly("twelve completed months", bars, D'2025.01.01', TARGET_LONG)) return 1;
   if(!expect_monthly("ignores current month and later data", bars, D'2025.01.20', TARGET_LONG)) return 1;
   if(!expect_monthly("updates at next month boundary", bars, D'2025.02.01', TARGET_SHORT)) return 1;
   bars[2].close = 100;
   if(!expect_monthly("zero return stays flat", bars, D'2025.01.01', TARGET_FLAT)) return 1;
   bars[2].close = 80;
   if(!expect_monthly("negative return shorts", bars, D'2025.01.01', TARGET_SHORT)) return 1;
   bars[2].close = 0;
   PositionTarget target = TARGET_FLAT;
   if(compute_monthly_target(bars, D'2025.01.01', target)) return 1;
   bars[2].close = 120;
   bars[0].time = D'2024.01.01';
   if(compute_monthly_target(bars, D'2025.01.01', target)) return 1;
   bars[0].time = D'2023.12.29';
   ArraySetAsSeries(bars, true);
   if(compute_monthly_target(bars, D'2025.01.01', target)) return 1;
   ArraySetAsSeries(bars, false);
   bars[0].time = bars[1].time;
   if(compute_monthly_target(bars, D'2025.01.01', target)) return 1;
   ArrayResize(bars, 1);
   if(compute_monthly_target(bars, D'2025.01.01', target)) return 1;

   MqlRates leap[];
   ArrayResize(leap, 2);
   leap[0].time = D'2023.02.28';
   leap[0].close = 100;
   leap[1].time = D'2024.02.29';
   leap[1].close = 101;
   if(!expect_monthly("leap year uses calendar months", leap, D'2024.03.01', TARGET_LONG)) return 1;
   MqlRates months[];
   ArrayResize(months, 13);
   for(int i = 0; i < 13; i++)
   {
      MqlDateTime date = {};
      date.year = 2022 + (11 + i) / 12;
      date.mon = (11 + i) % 12 + 1;
      date.day = 1;
      months[i].time = StructToTime(date);
      months[i].close = 100 + i;
   }
   if(!expect_monthly("January start with thirteen monthly closes", months, D'2024.01.02', TARGET_LONG)) return 1;
   if(!expect_monthly("same direction through January", months, D'2024.01.31', TARGET_LONG)) return 1;
   if(get_strategy_lookback() != 1) return 1;
   Print("Strategy test: MonthlyMomentum PASS");
   return 0;
}
