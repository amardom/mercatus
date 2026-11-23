#property strict
#include "../../experts/PositionTarget.mqh"
#include "../../strategies/ChannelBreakout/ChannelBreakout.mqh"
#include "Test_Assertions.mqh"

int OnStart()
{
   MqlRates bars[];
   load_closes(bars, 25, 100);
   for(int i = 0; i < 24; i++) bars[i].high = 101;
   bars[24].high = 110;
   bars[24].close = 102;
   if(!expect_target("breakout excludes signal bar high", bars, -1, TARGET_LONG)) return 1;
   bars[24].close = 101;
   if(!expect_target("touch is not a breakout", bars, -1, TARGET_FLAT)) return 1;
   bars[24].close = 100;
   if(!expect_target("close inside channel", bars, -1, TARGET_FLAT)) return 1;
   Print("Strategy test: ChannelBreakout PASS");
   return 0;
}
