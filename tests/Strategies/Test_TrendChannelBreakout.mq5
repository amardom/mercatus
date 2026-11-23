#property strict
#include "../../experts/PositionTarget.mqh"
#include "../../strategies/TrendChannelBreakout/TrendChannelBreakout.mqh"
#include "Test_Assertions.mqh"

int OnStart()
{
   MqlRates bars[];
   int signal_bar = Lookback;
   load_closes(bars, Lookback + 1, 100);
   for(int i = 0; i < signal_bar; i++)
   {
      bars[i].high = i < Lookback / 2 ? 105 : 101;
      bars[i].low = i < Lookback / 2 ? 95 : 99;
   }
   bars[signal_bar].high = 110;
   bars[signal_bar].low = 90;
   bars[signal_bar].close = 106;
   if(!expect_target("long breakout excludes signal bar", bars, -1, TARGET_LONG)) return 1;
   if(!expect_target("short exits to flat despite long breakout", bars, 1, TARGET_FLAT, TARGET_SHORT)) return 1;
   bars[signal_bar].close = 94;
   if(!expect_target("short breakout excludes signal bar", bars, -1, TARGET_SHORT)) return 1;
   if(!expect_target("long exits to flat despite short breakout", bars, 1, TARGET_FLAT, TARGET_LONG)) return 1;
   bars[signal_bar].close = 98;
   if(!expect_target("long exits using half channel", bars, 1, TARGET_FLAT, TARGET_LONG)) return 1;
   if(!expect_target("short stays open", bars, 1, TARGET_SHORT, TARGET_SHORT)) return 1;
   bars[signal_bar].close = 102;
   if(!expect_target("short exits using half channel", bars, 1, TARGET_FLAT, TARGET_SHORT)) return 1;
   if(!expect_target("long stays open", bars, 1, TARGET_LONG, TARGET_LONG)) return 1;
   if(!expect_target("entry uses full channel", bars, -1, TARGET_FLAT)) return 1;
   bars[signal_bar].close = 105;
   if(!expect_target("touch does not open", bars, -1, TARGET_FLAT)) return 1;
   bars[signal_bar].close = 99;
   if(!expect_target("touch does not close", bars, 1, TARGET_LONG, TARGET_LONG)) return 1;
   ArrayResize(bars, Lookback);
   PositionTarget target = TARGET_FLAT;
   if(compute_strategy_signal(bars, -1, TARGET_FLAT, target)) return 1;
   Print("Strategy test: TrendChannelBreakout PASS");
   return 0;
}
