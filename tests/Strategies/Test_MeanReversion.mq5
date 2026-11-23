#property strict
#include "../../experts/PositionTarget.mqh"
#include "../../strategies/MeanReversion/MeanReversion.mqh"
#include "Test_Assertions.mqh"

int OnStart()
{
   MqlRates bars[];
   load_closes(bars, 25, 100);
   bars[24].close = 95;
   if(!expect_target("zero variance", bars, -1, TARGET_FLAT)) return 1;
   for(int i = 0; i < 24; i++) bars[i].close = i % 2 == 0 ? 99 : 101;
   bars[24].close = 97;
   if(!expect_target("long below two deviations", bars, -1, TARGET_LONG)) return 1;
   bars[24].close = 103;
   if(!expect_target("short above two deviations", bars, -1, TARGET_SHORT)) return 1;
   bars[24].close = 98;
   if(!expect_target("inside entry band", bars, -1, TARGET_FLAT)) return 1;
   if(!expect_target("hold long", bars, 23, TARGET_LONG, TARGET_LONG)) return 1;
   if(!expect_target("long time exit", bars, 24, TARGET_FLAT, TARGET_LONG)) return 1;
   if(!expect_target("short closes without reversing", bars, 1, TARGET_FLAT, TARGET_SHORT)) return 1;
   bars[24].close = 102;
   if(!expect_target("hold short", bars, 23, TARGET_SHORT, TARGET_SHORT)) return 1;
   if(!expect_target("short time exit", bars, 24, TARGET_FLAT, TARGET_SHORT)) return 1;
   if(!expect_target("long closes without reversing", bars, 1, TARGET_FLAT, TARGET_LONG)) return 1;
   bars[24].close = 100;
   if(!expect_target("long exits at mean", bars, 1, TARGET_FLAT, TARGET_LONG)) return 1;
   if(!expect_target("short exits at mean", bars, 1, TARGET_FLAT, TARGET_SHORT)) return 1;
   ArrayResize(bars, 24);
   PositionTarget target = TARGET_FLAT;
   if(compute_strategy_signal(bars, -1, TARGET_FLAT, target)) return 1;
   Print("Strategy test: MeanReversion PASS");
   return 0;
}
