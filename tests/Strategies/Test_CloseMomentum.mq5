#property strict
#include "../../experts/PositionTarget.mqh"
#include "../../strategies/CloseMomentum/CloseMomentum.mqh"
#include "Test_Assertions.mqh"

int OnStart()
{
   MqlRates bars[];
   load_closes(bars, 26, 100);
   bars[0].close = 200;
   bars[24].close = 110;
   bars[25].close = 101;
   if(!expect_target("higher than exact lookback close", bars, -1, TARGET_LONG)) return 1;
   bars[25].close = 99;
   if(!expect_target("lower than exact lookback close", bars, -1, TARGET_SHORT)) return 1;
   bars[25].close = 100;
   if(!expect_target("equal lookback close", bars, -1, TARGET_FLAT)) return 1;
   Print("Strategy test: CloseMomentum PASS");
   return 0;
}
