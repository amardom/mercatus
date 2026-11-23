#property strict
#include "../../experts/PositionTarget.mqh"
#include "../../strategies/MovingAverage/MovingAverage.mqh"
#include "Test_Assertions.mqh"

int OnStart()
{
   MqlRates bars[];
   load_closes(bars, 4, 100);
   if(!expect_target("equal averages", bars, -1, TARGET_FLAT)) return 1;
   bars[3].close = 104;
   if(!expect_target("fast above slow", bars, -1, TARGET_LONG)) return 1;
   bars[3].close = 96;
   if(!expect_target("fast below slow", bars, -1, TARGET_FLAT)) return 1;
   ArrayResize(bars, 3);
   PositionTarget target;
   if(compute_strategy_signal(bars, -1, TARGET_FLAT, target)) return 1;
   Print("Strategy test: MovingAverage PASS");
   return 0;
}
