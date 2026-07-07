//+------------------------------------------------------------------+
//| SmcZones.mqh
//| SMC zones and FVG
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_SMCZONES
#define H4_LQ_V3_SMCZONES

bool SMCZoneTypeIsBullish(const ENUM_SMC_ZONE_TYPE type)
{
   return type < ZONE_BEAR_WEEKLY_FVG;
}

//+------------------------------------------------------------------+
bool SMCZoneTypeIsSwingLiquidity(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BULL_SWING_M15_LOW:
      case ZONE_BEAR_SWING_W1_HIGH:
      case ZONE_BEAR_SWING_DAILY_HIGH:
      case ZONE_BEAR_SWING_H4_HIGH:
      case ZONE_BEAR_SWING_M15_HIGH:
         return true;
      default:
         return false;
   }
}

//+------------------------------------------------------------------+
bool SMCZoneTypeIsMtfFvg(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:
      case ZONE_BULL_DAILY_FVG:
      case ZONE_BULL_H4_FVG:
      case ZONE_BULL_M15_FVG:
      case ZONE_BEAR_WEEKLY_FVG:
      case ZONE_BEAR_DAILY_FVG:
      case ZONE_BEAR_H4_FVG:
      case ZONE_BEAR_M15_FVG:
         return true;
      default:
         return false;
   }
}

//+------------------------------------------------------------------+
bool SMCZonePassesCurrentPriceSideFilter(const ENUM_SMC_ZONE_TYPE type,
                                          const double top, const double bottom)
{
   if(top <= bottom)
      return false;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(currentPrice <= 0.0)
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   if(currentPrice <= 0.0)
      currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   if(currentPrice <= 0.0)
      return true;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   if(SMCZoneTypeIsBullish(type))
      return top < currentPrice - eps;
   return bottom > currentPrice + eps;
}

//+------------------------------------------------------------------+
int GetZoneTimeframeStrength(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:
      case ZONE_BEAR_WEEKLY_FVG:
         return 4;
      case ZONE_BULL_DAILY_FVG:
      case ZONE_BULL_PROTECTED_DAILY_LOW:
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BEAR_DAILY_FVG:
      case ZONE_BEAR_PROTECTED_DAILY_HIGH:
      case ZONE_BEAR_SWING_DAILY_HIGH:
         return 3;
      case ZONE_BULL_H4_FVG:
      case ZONE_BULL_PROTECTED_H4_LOW:
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BEAR_H4_FVG:
      case ZONE_BEAR_PROTECTED_H4_HIGH:
      case ZONE_BEAR_SWING_H4_HIGH:
         return 2;
      case ZONE_BULL_M15_FVG:
      case ZONE_BULL_PROTECTED_M15_LOW:
      case ZONE_BULL_SWING_M15_LOW:
      case ZONE_BEAR_M15_FVG:
      case ZONE_BEAR_PROTECTED_M15_HIGH:
      case ZONE_BEAR_SWING_M15_HIGH:
         return 1;
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BEAR_SWING_W1_HIGH:
         return 4;
   }
   return 0;
}

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES SMCZoneTypeToTimeframe(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:
      case ZONE_BEAR_WEEKLY_FVG:
         return PERIOD_W1;
      case ZONE_BULL_DAILY_FVG:
      case ZONE_BULL_PROTECTED_DAILY_LOW:
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BEAR_DAILY_FVG:
      case ZONE_BEAR_PROTECTED_DAILY_HIGH:
      case ZONE_BEAR_SWING_DAILY_HIGH:
         return PERIOD_D1;
      case ZONE_BULL_H4_FVG:
      case ZONE_BULL_PROTECTED_H4_LOW:
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BEAR_H4_FVG:
      case ZONE_BEAR_PROTECTED_H4_HIGH:
      case ZONE_BEAR_SWING_H4_HIGH:
         return PERIOD_H4;
      case ZONE_BULL_M15_FVG:
      case ZONE_BULL_PROTECTED_M15_LOW:
      case ZONE_BULL_SWING_M15_LOW:
      case ZONE_BEAR_M15_FVG:
      case ZONE_BEAR_PROTECTED_M15_HIGH:
      case ZONE_BEAR_SWING_M15_HIGH:
         return PERIOD_M15;
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BEAR_SWING_W1_HIGH:
         return PERIOD_W1;
   }
   return PERIOD_CURRENT;
}

//+------------------------------------------------------------------+
bool SMCGetMtfSwingTracker(const ENUM_TIMEFRAMES timeframe, MTFSwingTracker &tracker)
{
   switch(timeframe)
   {
      case PERIOD_W1:  tracker = g_mtfSwingW1;  return true;
      case PERIOD_D1:  tracker = g_mtfSwingD1;  return true;
      case PERIOD_H4:  tracker = g_mtfSwingH4;  return true;
      case PERIOD_M15: tracker = g_mtfSwingM15; return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Per-TF MTF swing leg access — completed legs + unbroken extremes. |
//+------------------------------------------------------------------+
bool MtfIsSwingTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   return timeframe == PERIOD_W1 || timeframe == PERIOD_D1
       || timeframe == PERIOD_H4 || timeframe == PERIOD_M15;
}

//+------------------------------------------------------------------+
bool MtfCopySwingState(const ENUM_TIMEFRAMES timeframe, SwingState &outSwingState)
{
   MTFSwingTracker tracker;
   if(!SMCGetMtfSwingTracker(timeframe, tracker))
      return false;
   outSwingState = tracker.swing;
   return true;
}

//+------------------------------------------------------------------+
bool MtfTryNthCompletedSwingLeg(const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                                 const int nFromLatest,
                                 double &outLegHigh, double &outLegLow,
                                 datetime &outLegStartTime, datetime &outLegEndTime)
{
   outLegHigh      = 0.0;
   outLegLow       = 0.0;
   outLegStartTime = 0;
   outLegEndTime   = 0;
   if(!MtfIsSwingTimeframe(timeframe) || swingDirection == 0 || nFromLatest < 1)
      return false;

   SwingState swingState;
   if(!MtfCopySwingState(timeframe, swingState))
      return false;

   int legsFound = 0;
   for(int i = swingState.swingHistoryCount - 1; i >= 0; i--)
   {
      const Swing leg = swingState.swingHistory[i];
      if(leg.swingDirection != swingDirection || leg.legEndTime == 0)
         continue;
      legsFound++;
      if(legsFound == nFromLatest)
      {
         outLegHigh      = leg.legHighPrice;
         outLegLow       = leg.legLowPrice;
         outLegStartTime = leg.legStartTime;
         outLegEndTime   = leg.legEndTime;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool MtfTryLatestCompletedUpLegHigh(const ENUM_TIMEFRAMES timeframe, double &outHigh,
                                     datetime &outLegEndTime)
{
   datetime legStart = 0;
   double   legLow   = 0.0;
   return MtfTryNthCompletedSwingLeg(timeframe, 1, 1, outHigh, legLow, legStart, outLegEndTime);
}

//+------------------------------------------------------------------+
bool MtfTryLatestCompletedDownLegLow(const ENUM_TIMEFRAMES timeframe, double &outLow,
                                      datetime &outLegEndTime)
{
   datetime legStart = 0;
   double   legHigh  = 0.0;
   return MtfTryNthCompletedSwingLeg(timeframe, -1, 1, legHigh, outLow, legStart, outLegEndTime);
}

//+------------------------------------------------------------------+
bool MtfTryLatestUnbrokenSwingHigh(const ENUM_TIMEFRAMES timeframe, double &outLevel)
{
   SwingState swingState;
   if(!MtfCopySwingState(timeframe, swingState))
      return false;
   return SMCTryGetLatestUnbrokenSwingHigh(swingState, timeframe, outLevel);
}

//+------------------------------------------------------------------+
bool MtfTryLatestUnbrokenSwingLow(const ENUM_TIMEFRAMES timeframe, double &outLevel)
{
   SwingState swingState;
   if(!MtfCopySwingState(timeframe, swingState))
      return false;
   return SMCTryGetLatestUnbrokenSwingLow(swingState, timeframe, outLevel);
}

//+------------------------------------------------------------------+
bool MtfTryDetectBosCrossOnBar(const ENUM_TIMEFRAMES timeframe, const int barShift,
                                int &outDirection, double &outBrokenLevel,
                                datetime &outBarOpenTime, datetime &outLegEndTime)
{
   outDirection   = 0;
   outBrokenLevel = 0.0;
   outBarOpenTime = 0;
   outLegEndTime  = 0;

   SwingState swingState;
   if(!MtfCopySwingState(timeframe, swingState))
      return false;

   double legHigh = 0.0;
   double legLow  = 0.0;
   return SMCTryDetectBosOnBar(swingState, timeframe, barShift, outDirection, outBrokenLevel,
                               outBarOpenTime, outLegEndTime, legHigh, legLow);
}

//+------------------------------------------------------------------+
double SMCSwingLevelBufferForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const double pointSize = (_Point > 0.0 ? _Point : 0.00001);
   if(InputSmcBrokenLevelBufferPercentChart <= 0.0)
      return pointSize;

   const int lookbackBars = MathMax(3, InputSmcFvgLookbackBars);
   const double chartHeight =
      ReferenceChartHeightForTimeframeBarCount(timeframe, lookbackBars);
   if(chartHeight <= 0.0)
      return pointSize;

   return chartHeight * (InputSmcBrokenLevelBufferPercentChart / 100.0);
}

//+------------------------------------------------------------------+
double SMCSwingLevelBufferForZoneType(const ENUM_SMC_ZONE_TYPE type)
{
   return SMCSwingLevelBufferForTimeframe(SMCZoneTypeToTimeframe(type));
}

//+------------------------------------------------------------------+
void SMCResetActiveZones()
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      g_activeZones[i].type               = (ENUM_SMC_ZONE_TYPE)0;
      g_activeZones[i].topPrice           = 0.0;
      g_activeZones[i].bottomPrice        = 0.0;
      g_activeZones[i].isActive           = false;
      g_activeZones[i].isClustered        = false;
      g_activeZones[i].isMitigated        = false;
      g_activeZones[i].isBreached         = false;
      g_activeZones[i].isExpired          = false;
      g_activeZones[i].zoneOriginBarTime  = 0;
   }

   for(int i = 0; i < SMC_ZONE_MITIGATION_LEDGER_CAPACITY; i++)
      g_zoneMitigationLedger[i].inUse = false;

   SMCResetMtfFvgInstances();
}

//+------------------------------------------------------------------+
bool SMCActiveZoneOverlapsPrices(const SMCZoneRecord &zone, const ENUM_SMC_ZONE_TYPE type,
                                  const double top, const double bottom, const double mergeBuffer)
{
   if(!zone.isActive || zone.type != type)
      return false;
   return top > zone.bottomPrice - mergeBuffer && bottom < zone.topPrice + mergeBuffer;
}

//+------------------------------------------------------------------+
int SMCFindActiveZoneSlotByTypeAndPrice(const ENUM_SMC_ZONE_TYPE type,
                                         const double top, const double bottom)
{
   const double mergeBuffer = SMCSwingLevelBufferForZoneType(type);
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(SMCActiveZoneOverlapsPrices(g_activeZones[i], type, top, bottom, mergeBuffer))
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
int SMCFindActiveZoneSlotByTypeAndOrigin(const ENUM_SMC_ZONE_TYPE type,
                                          const datetime originBarTime)
{
   if(originBarTime <= 0)
      return -1;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(g_activeZones[i].type != type)
         continue;
      if(g_activeZones[i].zoneOriginBarTime == originBarTime)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void SMCDeactivateZoneLedgerSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return;

   SMCDeleteAllZoneRectangleObjectsForSlot(slotIndex);
   g_activeZones[slotIndex].isActive           = false;
   g_activeZones[slotIndex].isClustered        = false;
   g_activeZones[slotIndex].isMitigated         = false;
   g_activeZones[slotIndex].isBreached          = false;
   g_activeZones[slotIndex].isExpired           = false;
   g_activeZones[slotIndex].zoneOriginBarTime   = 0;
}

//+------------------------------------------------------------------+
int SMCAllocZoneLedgerSlot()
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
      {
         SMCDeleteAllZoneRectangleObjectsForSlot(i);
         return i;
      }
   }

   int          evictIdx    = -1;
   datetime     oldestOrigin = 0;
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
      {
         evictIdx = i;
         break;
      }
      if(evictIdx < 0
         || (g_activeZones[i].zoneOriginBarTime > 0
             && (oldestOrigin == 0 || g_activeZones[i].zoneOriginBarTime < oldestOrigin)))
      {
         oldestOrigin = g_activeZones[i].zoneOriginBarTime;
         evictIdx     = i;
      }
   }

   if(evictIdx < 0)
      return -1;

   SMCDeactivateZoneLedgerSlot(evictIdx);
   return evictIdx;
}

//+------------------------------------------------------------------+
void SMCApplyFreshZoneStateToSlot(const int slotIndex, const datetime originBarTime)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return;

   g_activeZones[slotIndex].isMitigated = false;
   g_activeZones[slotIndex].isBreached  = false;
   g_activeZones[slotIndex].isExpired   = false;
   if(originBarTime > 0)
      g_activeZones[slotIndex].zoneOriginBarTime = originBarTime;

   const int ledgerIndex = SMCFindMitigationLedgerIndex(g_activeZones[slotIndex].type,
                                                        g_activeZones[slotIndex].topPrice,
                                                        g_activeZones[slotIndex].bottomPrice, true,
                                                        g_activeZones[slotIndex].zoneOriginBarTime);
   if(ledgerIndex < 0)
      return;

   g_zoneMitigationLedger[ledgerIndex].isMitigated       = false;
   g_zoneMitigationLedger[ledgerIndex].isBreached        = false;
   g_zoneMitigationLedger[ledgerIndex].isExpired         = false;
   g_zoneMitigationLedger[ledgerIndex].zoneOriginBarTime = g_activeZones[slotIndex].zoneOriginBarTime;
}

//+------------------------------------------------------------------+
bool SMCLedgerOverlapsZonePrices(const SMCZoneMitigationLedgerEntry &entry,
                                  const ENUM_SMC_ZONE_TYPE type,
                                  const double top, const double bottom,
                                  const double mergeBuffer)
{
   if(!entry.inUse || entry.type != type)
      return false;
   return top > entry.bottomPrice - mergeBuffer && bottom < entry.topPrice + mergeBuffer;
}

//+------------------------------------------------------------------+
int SMCFindMitigationLedgerIndex(const ENUM_SMC_ZONE_TYPE type, const double top,
                                  const double bottom, const bool createIfMissing,
                                  const datetime originBarTime = 0)
{
   const double mergeBuffer = SMCSwingLevelBufferForZoneType(type);
   int          freeIndex   = -1;

   if(originBarTime > 0 && SMCZoneTypeIsSwingLiquidity(type))
   {
      for(int i = 0; i < SMC_ZONE_MITIGATION_LEDGER_CAPACITY; i++)
      {
         if(!g_zoneMitigationLedger[i].inUse)
         {
            if(freeIndex < 0)
               freeIndex = i;
            continue;
         }
         if(g_zoneMitigationLedger[i].type == type
            && g_zoneMitigationLedger[i].zoneOriginBarTime == originBarTime)
            return i;
      }

      if(!createIfMissing || freeIndex < 0)
         return -1;

      g_zoneMitigationLedger[freeIndex].inUse               = true;
      g_zoneMitigationLedger[freeIndex].type                = type;
      g_zoneMitigationLedger[freeIndex].topPrice            = top;
      g_zoneMitigationLedger[freeIndex].bottomPrice         = bottom;
      g_zoneMitigationLedger[freeIndex].isMitigated         = false;
      g_zoneMitigationLedger[freeIndex].isBreached          = false;
      g_zoneMitigationLedger[freeIndex].isExpired           = false;
      g_zoneMitigationLedger[freeIndex].zoneOriginBarTime   = originBarTime;
      return freeIndex;
   }

   for(int i = 0; i < SMC_ZONE_MITIGATION_LEDGER_CAPACITY; i++)
   {
      if(!g_zoneMitigationLedger[i].inUse)
      {
         if(freeIndex < 0)
            freeIndex = i;
         continue;
      }
      if(SMCLedgerOverlapsZonePrices(g_zoneMitigationLedger[i], type, top, bottom, mergeBuffer))
         return i;
   }

   if(!createIfMissing || freeIndex < 0)
      return -1;

   g_zoneMitigationLedger[freeIndex].inUse               = true;
   g_zoneMitigationLedger[freeIndex].type                = type;
   g_zoneMitigationLedger[freeIndex].topPrice            = top;
   g_zoneMitigationLedger[freeIndex].bottomPrice         = bottom;
   g_zoneMitigationLedger[freeIndex].isMitigated  = false;
   g_zoneMitigationLedger[freeIndex].isBreached   = false;
   g_zoneMitigationLedger[freeIndex].isExpired    = false;
   const ENUM_TIMEFRAMES originTf = SMCZoneTypeToTimeframe(type);
   g_zoneMitigationLedger[freeIndex].zoneOriginBarTime   =
      (originTf != PERIOD_CURRENT ? iTime(_Symbol, originTf, 1) : 0);
   return freeIndex;
}

//+------------------------------------------------------------------+
void SMCApplyMitigationLedgerToSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY || !g_activeZones[slotIndex].isActive)
      return;

   const ENUM_SMC_ZONE_TYPE type   = g_activeZones[slotIndex].type;
   const double             top    = g_activeZones[slotIndex].topPrice;
   const double             bottom = g_activeZones[slotIndex].bottomPrice;
   const datetime           origin = g_activeZones[slotIndex].zoneOriginBarTime;
   const int ledgerIndex = SMCFindMitigationLedgerIndex(type, top, bottom, true, origin);
   if(ledgerIndex < 0)
      return;

   g_zoneMitigationLedger[ledgerIndex].topPrice    = top;
   g_zoneMitigationLedger[ledgerIndex].bottomPrice = bottom;
   g_activeZones[slotIndex].isMitigated  = g_zoneMitigationLedger[ledgerIndex].isMitigated;
   g_activeZones[slotIndex].isBreached   = g_zoneMitigationLedger[ledgerIndex].isBreached;
   g_activeZones[slotIndex].isExpired    = g_zoneMitigationLedger[ledgerIndex].isExpired;
   g_activeZones[slotIndex].zoneOriginBarTime   = g_zoneMitigationLedger[ledgerIndex].zoneOriginBarTime;
   if(g_activeZones[slotIndex].zoneOriginBarTime == 0)
   {
      const ENUM_TIMEFRAMES originTf = SMCZoneTypeToTimeframe(type);
      if(originTf != PERIOD_CURRENT)
      {
         g_activeZones[slotIndex].zoneOriginBarTime = iTime(_Symbol, originTf, 1);
         g_zoneMitigationLedger[ledgerIndex].zoneOriginBarTime =
            g_activeZones[slotIndex].zoneOriginBarTime;
      }
   }
}

//+------------------------------------------------------------------+
void SMCSaveZoneMitigationToLedger(const SMCZoneRecord &zone)
{
   const int ledgerIndex =
      SMCFindMitigationLedgerIndex(zone.type, zone.topPrice, zone.bottomPrice, true,
                                   zone.zoneOriginBarTime);
   if(ledgerIndex < 0)
      return;

   g_zoneMitigationLedger[ledgerIndex].type               = zone.type;
   g_zoneMitigationLedger[ledgerIndex].topPrice           = zone.topPrice;
   g_zoneMitigationLedger[ledgerIndex].bottomPrice        = zone.bottomPrice;
   g_zoneMitigationLedger[ledgerIndex].isMitigated  = zone.isMitigated;
   g_zoneMitigationLedger[ledgerIndex].isBreached   = zone.isBreached;
   g_zoneMitigationLedger[ledgerIndex].isExpired    = zone.isExpired;
   g_zoneMitigationLedger[ledgerIndex].zoneOriginBarTime    = zone.zoneOriginBarTime;
}

//+------------------------------------------------------------------+
bool SMCZonePastExpiryBarLimit(const ENUM_SMC_ZONE_TYPE type, const datetime zoneOriginBarTime)
{
   if(zoneOriginBarTime == 0 || InputSmcZoneExpiryBars <= 0)
      return false;

   const ENUM_TIMEFRAMES tf = SMCZoneTypeToTimeframe(type);
   if(tf == PERIOD_CURRENT)
      return false;

   const int originShift = iBarShift(_Symbol, tf, zoneOriginBarTime, true);
   if(originShift < 0)
      return true;

   return originShift > InputSmcZoneExpiryBars;
}

//+------------------------------------------------------------------+
datetime SMCZoneRectangleTimeRight(const ENUM_TIMEFRAMES timeframe, const datetime zoneOriginBarTime)
{
   if(zoneOriginBarTime <= 0)
      return 0;

   const int periodSec = PeriodSeconds(timeframe);
   if(periodSec <= 0)
      return zoneOriginBarTime;

   const int expiryBars = (InputSmcZoneExpiryBars > 0 ? InputSmcZoneExpiryBars : 292);
   return zoneOriginBarTime + (datetime)(periodSec * expiryBars);
}

//+------------------------------------------------------------------+
void SMCExpireZonesPastBarLimit()
{
   SMCExpireZonesPastBarLimitForTimeframe(PERIOD_W1);
   SMCExpireZonesPastBarLimitForTimeframe(PERIOD_D1);
   SMCExpireZonesPastBarLimitForTimeframe(PERIOD_H4);
   SMCExpireZonesPastBarLimitForTimeframe(PERIOD_M15);
}

//+------------------------------------------------------------------+
void SMCExpireZonesPastBarLimitForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive || g_activeZones[i].isExpired)
         continue;
      if(SMCZoneTypeToTimeframe(g_activeZones[i].type) != timeframe)
         continue;

      if(SMCZonePastExpiryBarLimit(g_activeZones[i].type, g_activeZones[i].zoneOriginBarTime))
      {
         g_activeZones[i].isExpired = true;
         SMCSaveZoneMitigationToLedger(g_activeZones[i]);
      }
   }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool SMCBarWicksIntoZone(const double top, const double bottom,
                          const double barHigh, const double barLow, const double eps)
{
   return (barHigh >= bottom - eps && barLow <= top + eps);
}

//+------------------------------------------------------------------+
bool SMCBarClosesOutsideZone(const double top, const double bottom,
                              const double barClose, const double eps)
{
   return (barClose < bottom - eps || barClose > top + eps);
}

//+------------------------------------------------------------------+
//| Gap/skip: close on far side of zone (bull below bottom, bear above top). |
//+------------------------------------------------------------------+
bool SMCBarClosesThroughZoneOppositeSide(const ENUM_SMC_ZONE_TYPE zoneType,
                                          const double top, const double bottom,
                                          const double barClose, const double eps)
{
   if(barClose <= 0.0)
      return false;
   if(SMCZoneTypeIsBullish(zoneType))
      return barClose < bottom - eps;
   return barClose > top + eps;
}

//+------------------------------------------------------------------+
bool SMCZoneOriginBarDeferMitigation(const datetime barOpen, const datetime zoneOriginBarTime)
{
   return (zoneOriginBarTime > 0 && barOpen > 0 && barOpen <= zoneOriginBarTime);
}

//+------------------------------------------------------------------+
bool SMCZoneDeferMitigationOnThisBar(const ENUM_SMC_ZONE_TYPE zoneType,
                                      const datetime barOpen,
                                      const datetime zoneOriginBarTime)
{
   if(SMCZoneTypeIsMtfFvg(zoneType))
      return false;
   return SMCZoneOriginBarDeferMitigation(barOpen, zoneOriginBarTime);
}

//+------------------------------------------------------------------+
//| Step 1 breach (wick OR close-through). Step 2 mitigate once breached + close outside (same or later bar). |
//+------------------------------------------------------------------+
bool SMCApplyZoneBreachAndMitigationOnClosedBar(bool &isBreached, bool &isMitigated,
                                                 const ENUM_SMC_ZONE_TYPE zoneType,
                                                 const double top, const double bottom,
                                                 const double barHigh, const double barLow,
                                                 const double barClose, const double eps,
                                                 const datetime barOpen,
                                                 const datetime zoneOriginBarTime,
                                                 int &outBias)
{
   outBias = 0;
   if(isMitigated || top <= bottom)
      return false;
   if(SMCZoneDeferMitigationOnThisBar(zoneType, barOpen, zoneOriginBarTime))
      return false;
   if(barClose <= 0.0 || barHigh <= 0.0 || barLow <= 0.0)
      return false;

   const bool wickBreach         = SMCBarWicksIntoZone(top, bottom, barHigh, barLow, eps);
   const bool closeThroughBreach = SMCBarClosesThroughZoneOppositeSide(zoneType, top, bottom, barClose, eps);
   const bool closeOutside       = SMCBarClosesOutsideZone(top, bottom, barClose, eps);

   if(!isBreached && (wickBreach || closeThroughBreach))
      isBreached = true;

   if(!isBreached || !closeOutside)
      return false;

   int zoneBias = 0;
   if(SMCZoneBarCloseRejectionBias(top, bottom, barClose, eps, zoneBias))
      outBias = zoneBias;

   isMitigated = true;
   return true;
}

//+------------------------------------------------------------------+
void SMCApplyZoneBreachOnClosedBar(bool &isBreached,
                                    const ENUM_SMC_ZONE_TYPE zoneType,
                                    const double top, const double bottom,
                                    const double barHigh, const double barLow,
                                    const double barClose,
                                    const double eps,
                                    const datetime barOpen,
                                    const datetime zoneOriginBarTime)
{
   if(top <= bottom || isBreached)
      return;
   if(SMCZoneDeferMitigationOnThisBar(zoneType, barOpen, zoneOriginBarTime))
      return;

   if(SMCBarWicksIntoZone(top, bottom, barHigh, barLow, eps))
      isBreached = true;
   else if(barClose > 0.0
           && SMCBarClosesThroughZoneOppositeSide(zoneType, top, bottom, barClose, eps))
      isBreached = true;
}

//+------------------------------------------------------------------+
void SMCApplyZoneMitigationOnClosedBar(bool &isMitigated, bool &isBreached,
                                        const ENUM_SMC_ZONE_TYPE zoneType,
                                        const double top, const double bottom,
                                        const double barHigh, const double barLow,
                                        const double barClose, const double eps,
                                        const datetime barOpen,
                                        const datetime zoneOriginBarTime,
                                        int &outBias)
{
   SMCApplyZoneBreachAndMitigationOnClosedBar(isBreached, isMitigated, zoneType,
                                              top, bottom, barHigh, barLow, barClose, eps,
                                              barOpen, zoneOriginBarTime, outBias);
}

//+------------------------------------------------------------------+
void SMCAdvanceZoneBreachLedgerOnBarClose(const ENUM_TIMEFRAMES timeframe)
{
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   const double barHigh   = iHigh(_Symbol, timeframe, 1);
   const double barLow    = iLow(_Symbol, timeframe, 1);
   const double barClose  = iClose(_Symbol, timeframe, 1);
   const datetime barOpen = iTime(_Symbol, timeframe, 1);
   if(barHigh <= 0.0 || barLow <= 0.0 || barClose <= 0.0)
      return;

   for(int i = 0; i < SMC_ZONE_MITIGATION_LEDGER_CAPACITY; i++)
   {
      if(!g_zoneMitigationLedger[i].inUse || g_zoneMitigationLedger[i].isMitigated
         || g_zoneMitigationLedger[i].isExpired)
         continue;
      if(SMCZoneTypeToTimeframe(g_zoneMitigationLedger[i].type) != timeframe)
         continue;

      int unusedBias = 0;
      SMCApplyZoneBreachAndMitigationOnClosedBar(g_zoneMitigationLedger[i].isBreached,
                                                  g_zoneMitigationLedger[i].isMitigated,
                                                  g_zoneMitigationLedger[i].type,
                                                  g_zoneMitigationLedger[i].topPrice,
                                                  g_zoneMitigationLedger[i].bottomPrice,
                                                  barHigh, barLow, barClose, eps, barOpen,
                                                  g_zoneMitigationLedger[i].zoneOriginBarTime,
                                                  unusedBias);
   }
}

//+------------------------------------------------------------------+
void SMCUpdateZoneBreachForActiveZonesTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   SMCApplyZoneExitBiasAndMitigationForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void SMCUpdateMtfFvgZoneBreachForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   // Unified in SMCApplyZoneExitBiasAndMitigationForTimeframe.
}

//+------------------------------------------------------------------+
void SMCUpdateActiveZonesMitigation()
{
   SMCUpdateActiveZonesMitigationForTimeframe(PERIOD_W1);
   SMCUpdateActiveZonesMitigationForTimeframe(PERIOD_D1);
   SMCUpdateActiveZonesMitigationForTimeframe(PERIOD_H4);
   SMCUpdateActiveZonesMitigationForTimeframe(PERIOD_M15);
}

//+------------------------------------------------------------------+
void SMCUpdateActiveZonesMitigationForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   SMCApplyZoneExitBiasAndMitigationForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
//| Breach (wick or close-through) then mitigate (close-outside) same bar; bias on exit. |
//+------------------------------------------------------------------+
void SMCApplyZoneExitBiasAndMitigationForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   const double barHigh   = iHigh(_Symbol, timeframe, 1);
   const double barLow    = iLow(_Symbol, timeframe, 1);
   const double barClose  = iClose(_Symbol, timeframe, 1);
   const datetime barOpen = iTime(_Symbol, timeframe, 1);
   if(barHigh <= 0.0 || barLow <= 0.0 || barClose <= 0.0 || barOpen == 0)
      return;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive || g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
         continue;

      const ENUM_SMC_ZONE_TYPE zoneType = g_activeZones[i].type;
      if(SMCZoneTypeToTimeframe(zoneType) != timeframe)
         continue;

      const int ledgerIndex = SMCFindMitigationLedgerIndex(zoneType,
                                                            g_activeZones[i].topPrice,
                                                            g_activeZones[i].bottomPrice, false,
                                                            g_activeZones[i].zoneOriginBarTime);
      if(ledgerIndex >= 0 && g_zoneMitigationLedger[ledgerIndex].isBreached)
         g_activeZones[i].isBreached = true;

      int zoneBias = 0;
      const bool mitigatedNow = SMCApplyZoneBreachAndMitigationOnClosedBar(
         g_activeZones[i].isBreached,
         g_activeZones[i].isMitigated,
         zoneType,
         g_activeZones[i].topPrice,
         g_activeZones[i].bottomPrice,
         barHigh, barLow, barClose, eps, barOpen,
         g_activeZones[i].zoneOriginBarTime,
         zoneBias);

      if(zoneBias != 0)
         ProfessionalBiasSetDirection(timeframe, zoneBias, barOpen);

      if(mitigatedNow)
      {
         g_activeZones[i].isActive = false;
         SMCSaveZoneMitigationToLedger(g_activeZones[i]);
         SMCDeleteAllZoneRectangleObjectsForSlot(i);
      }
      else if(g_activeZones[i].isBreached)
         SMCSaveZoneMitigationToLedger(g_activeZones[i]);
   }

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         continue;
      if(g_mtfFvgInstances[f].timeframe != timeframe)
         continue;

      int zoneBias = 0;
      const bool mitigatedNow = SMCApplyZoneBreachAndMitigationOnClosedBar(
         g_mtfFvgInstances[f].isBreached,
         g_mtfFvgInstances[f].isMitigated,
         g_mtfFvgInstances[f].type,
         g_mtfFvgInstances[f].topPrice,
         g_mtfFvgInstances[f].bottomPrice,
         barHigh, barLow, barClose, eps, barOpen,
         g_mtfFvgInstances[f].zoneOriginBarTime,
         zoneBias);

      if(zoneBias != 0)
         ProfessionalBiasSetDirection(timeframe, zoneBias, barOpen);

      if(mitigatedNow)
      {
         SMCMitigateOverlappingMtfFvgPeers(f);
         g_mtfFvgInstances[f].inUse = false;
         SMCDeleteMtfFvgRectangleForInstance(g_mtfFvgInstances[f].type,
                                             g_mtfFvgInstances[f].zoneOriginBarTime);
      }
   }
}

//+------------------------------------------------------------------+
bool SMCZoneRegistrationAllowed(const ENUM_SMC_ZONE_TYPE type,
                                 const double top, const double bottom)
{
   if(SMCZoneTypeIsSwingLiquidity(type))
      return true;

   if(SMCZonePassesCurrentPriceSideFilter(type, top, bottom))
      return true;

   const int ledgerIndex = SMCFindMitigationLedgerIndex(type, top, bottom, false);
   if(ledgerIndex >= 0 && g_zoneMitigationLedger[ledgerIndex].inUse
      && !g_zoneMitigationLedger[ledgerIndex].isMitigated
      && !g_zoneMitigationLedger[ledgerIndex].isExpired)
      return true;

   return false;
}

//+------------------------------------------------------------------+
int RegisterOrMergeZone(const ENUM_SMC_ZONE_TYPE newType, const double top,
                         const double bottom, const datetime originBarTime = 0,
                         const bool forceFreshZoneState = false)
{
   if(newType < 0 || newType >= SMC_ZONE_TYPE_COUNT)
      return -1;
   if(top <= bottom)
      return -1;
   if(SMCZoneTypeIsMtfFvg(newType))
      return -1;
   if(!SMCZoneRegistrationAllowed(newType, top, bottom))
      return -1;

   datetime origin = originBarTime;
   if(origin <= 0)
   {
      const ENUM_TIMEFRAMES originTf = SMCZoneTypeToTimeframe(newType);
      if(originTf != PERIOD_CURRENT)
         origin = iTime(_Symbol, originTf, 1);
   }

   int slot = -1;
   if(SMCZoneTypeIsSwingLiquidity(newType) && origin > 0)
      slot = SMCFindActiveZoneSlotByTypeAndOrigin(newType, origin);
   else
      slot = SMCFindActiveZoneSlotByTypeAndPrice(newType, top, bottom);
   if(slot < 0)
   {
      slot = SMCAllocZoneLedgerSlot();
      if(slot < 0)
         return -1;

      SMCDeleteAllZoneRectangleObjectsForSlot(slot);

      g_activeZones[slot].type               = newType;
      g_activeZones[slot].topPrice           = top;
      g_activeZones[slot].bottomPrice        = bottom;
      g_activeZones[slot].isActive           = true;
      g_activeZones[slot].isClustered        = false;
      g_activeZones[slot].zoneOriginBarTime  = origin;
      if(forceFreshZoneState)
         SMCApplyFreshZoneStateToSlot(slot, origin);
      else
      {
         g_activeZones[slot].isMitigated = false;
         g_activeZones[slot].isBreached  = false;
         g_activeZones[slot].isExpired   = false;
      }
      SMCApplyMitigationLedgerToSlot(slot);
      return slot;
   }

   g_activeZones[slot].topPrice    = top;
   g_activeZones[slot].bottomPrice = bottom;
   if(origin > 0)
      g_activeZones[slot].zoneOriginBarTime = origin;
   if(forceFreshZoneState)
      SMCApplyFreshZoneStateToSlot(slot, origin);
   SMCApplyMitigationLedgerToSlot(slot);
   return slot;
}

//+------------------------------------------------------------------+
bool SMCDetectFvgAtMiddleShift(const ENUM_TIMEFRAMES timeframe, const int middleShift,
                                bool &outIsBullish, double &outBottom, double &outTop)
{
   outIsBullish = false;
   outBottom    = 0.0;
   outTop       = 0.0;

   const int oldestShift = middleShift + 1;
   const int newestShift = middleShift - 1;
   if(middleShift < 1 || oldestShift >= iBars(_Symbol, timeframe))
      return false;

   const double oldestHigh = iHigh(_Symbol, timeframe, oldestShift);
   const double oldestLow  = iLow(_Symbol, timeframe, oldestShift);
   const double newestHigh = iHigh(_Symbol, timeframe, newestShift);
   const double newestLow  = iLow(_Symbol, timeframe, newestShift);

   if(newestLow > oldestHigh)
   {
      outIsBullish = true;
      outBottom    = oldestHigh;
      outTop       = newestLow;
      return outTop > outBottom;
   }

   if(newestHigh < oldestLow)
   {
      outIsBullish = false;
      outBottom    = newestHigh;
      outTop       = oldestLow;
      return outTop > outBottom;
   }

   return false;
}

//+------------------------------------------------------------------+
bool SMCFvgGapMeetsMinPercentOfChart(const ENUM_TIMEFRAMES timeframe,
                                      const double gapBottom, const double gapTop)
{
   const double gapSize = gapTop - gapBottom;
   if(gapSize <= 0.0)
      return false;

   if(InputSmcFvgMinGapPercentChart <= 0.0)
      return true;

   const int lookbackBars = MathMax(3, InputSmcFvgLookbackBars);
   const double chartHeight = ReferenceChartHeightForTimeframeBarCount(timeframe, lookbackBars);
   if(chartHeight <= 0.0)
      return false;

   const double minGap = chartHeight * (InputSmcFvgMinGapPercentChart / 100.0);
   return gapSize >= minGap;
}

//+------------------------------------------------------------------+
bool SMCFvgMitigated(const ENUM_TIMEFRAMES timeframe, const int formationNewestShift,
                      const bool isBullish, const double bottomPrice, const double topPrice)
{
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   for(int shift = formationNewestShift - 1; shift >= 0; shift--)
   {
      const double barClose = iClose(_Symbol, timeframe, shift);
      if(isBullish && barClose < bottomPrice - eps)
         return true;
      if(!isBullish && barClose > topPrice + eps)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double SMCFvgPriceFacingInsetForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   if(InputSmcFvgZonePriceFacingInsetPercentChart <= 0.0)
      return 0.0;

   const int lookbackBars = MathMax(3, InputSmcFvgLookbackBars);
   const double chartHeight = ReferenceChartHeightForTimeframeBarCount(timeframe, lookbackBars);
   if(chartHeight <= 0.0)
      return 0.0;

   return chartHeight * (InputSmcFvgZonePriceFacingInsetPercentChart / 100.0);
}

//+------------------------------------------------------------------+
bool SMCApplyMtfFvgGapZoneEdges(const ENUM_TIMEFRAMES timeframe, const bool isBullish,
                                 const double gapBottom, const double gapTop,
                                 double &outBottom, double &outTop)
{
   outBottom = gapBottom;
   outTop    = gapTop;

   const double inset = SMCFvgPriceFacingInsetForTimeframe(timeframe);
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minGap    = (pointSize > 0.0 ? pointSize : 0.00001);

   if(inset > 0.0)
   {
      if(isBullish)
         outTop = gapTop - inset;
      else
         outBottom = gapBottom + inset;
   }

   return outTop > outBottom + minGap;
}

//+------------------------------------------------------------------+
void SMCResetMtfFvgInstances()
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
      g_mtfFvgInstances[i].inUse = false;

   SMCDeleteMtfFvgZoneRectanglesForTimeframe(PERIOD_W1);
   SMCDeleteMtfFvgZoneRectanglesForTimeframe(PERIOD_D1);
   SMCDeleteMtfFvgZoneRectanglesForTimeframe(PERIOD_H4);
   SMCDeleteMtfFvgZoneRectanglesForTimeframe(PERIOD_M15);
}

//+------------------------------------------------------------------+
int SMCFindMtfFvgInstanceIndex(const ENUM_SMC_ZONE_TYPE type, const datetime originBarTime)
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
   {
      if(!g_mtfFvgInstances[i].inUse)
         continue;
      if(g_mtfFvgInstances[i].type != type)
         continue;
      if(g_mtfFvgInstances[i].zoneOriginBarTime == originBarTime)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
int SMCAllocMtfFvgInstanceIndex()
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
   {
      if(!g_mtfFvgInstances[i].inUse)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void SMCUpsertMtfFvgInstance(const ENUM_SMC_ZONE_TYPE type, const double bottom, const double top,
                                const datetime originBarTime)
{
   if(!SMCZoneTypeIsMtfFvg(type) || top <= bottom || originBarTime <= 0)
      return;

   int idx = SMCFindMtfFvgInstanceIndex(type, originBarTime);
   if(idx < 0)
   {
      idx = SMCAllocMtfFvgInstanceIndex();
      if(idx < 0)
         return;

      g_mtfFvgInstances[idx].inUse              = true;
      g_mtfFvgInstances[idx].type               = type;
      g_mtfFvgInstances[idx].timeframe          = SMCZoneTypeToTimeframe(type);
      g_mtfFvgInstances[idx].isMitigated = false;
      g_mtfFvgInstances[idx].isBreached  = false;
      g_mtfFvgInstances[idx].isExpired   = false;
      g_mtfFvgInstances[idx].zoneOriginBarTime  = originBarTime;
   }

   g_mtfFvgInstances[idx].topPrice    = top;
   g_mtfFvgInstances[idx].bottomPrice = bottom;
}

//+------------------------------------------------------------------+
bool SMCPriceRangesOverlap(const double topA, const double bottomA,
                            const double topB, const double bottomB, const double eps)
{
   return topA > bottomB - eps && bottomA < topB + eps;
}

//+------------------------------------------------------------------+
void SMCMitigateOverlappingMtfFvgPeers(const int sourceIndex)
{
   if(sourceIndex < 0 || sourceIndex >= SMC_MTF_FVG_INSTANCE_CAPACITY)
      return;
   if(!g_mtfFvgInstances[sourceIndex].inUse)
      return;

   const ENUM_SMC_ZONE_TYPE sourceType = g_mtfFvgInstances[sourceIndex].type;
   const ENUM_TIMEFRAMES    sourceTf   = g_mtfFvgInstances[sourceIndex].timeframe;
   const double             sourceTop  = g_mtfFvgInstances[sourceIndex].topPrice;
   const double             sourceBot  = g_mtfFvgInstances[sourceIndex].bottomPrice;
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(f == sourceIndex)
         continue;
      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         continue;
      if(g_mtfFvgInstances[f].type != sourceType)
         continue;
      if(g_mtfFvgInstances[f].timeframe != sourceTf)
         continue;
      if(!SMCPriceRangesOverlap(sourceTop, sourceBot,
                                g_mtfFvgInstances[f].topPrice, g_mtfFvgInstances[f].bottomPrice, eps))
         continue;

      g_mtfFvgInstances[f].isMitigated = true;
      g_mtfFvgInstances[f].inUse       = false;
      SMCDeleteMtfFvgRectangleForInstance(g_mtfFvgInstances[f].type,
                                          g_mtfFvgInstances[f].zoneOriginBarTime);
   }
}

//+------------------------------------------------------------------+
void SMCUpdateMtfFvgInstancesMitigationForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   // FVG exit bias + mitigation handled in SMCApplyZoneExitBiasAndMitigationForTimeframe.
}

//+------------------------------------------------------------------+
void SMCExpireMtfFvgInstancesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
   {
      if(!g_mtfFvgInstances[i].inUse || g_mtfFvgInstances[i].isExpired)
         continue;
      if(g_mtfFvgInstances[i].timeframe != timeframe)
         continue;

      if(SMCZonePastExpiryBarLimit(g_mtfFvgInstances[i].type, g_mtfFvgInstances[i].zoneOriginBarTime))
         g_mtfFvgInstances[i].isExpired = true;
   }
}

//+------------------------------------------------------------------+
string SMCMtfFvgRectangleObjectName(const ENUM_SMC_ZONE_TYPE zoneType, const datetime originBarTime)
{
   const ENUM_TIMEFRAMES zoneTf = SMCZoneTypeToTimeframe(zoneType);
   return LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(zoneTf) + "_FVG_"
          + IntegerToString((long)originBarTime);
}

//+------------------------------------------------------------------+
void SMCDeleteMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const string prefix = LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(timeframe) + "_FVG_";
   ObjectsDeleteAll(0, prefix, -1, -1);
}

//+------------------------------------------------------------------+
void SMCDeleteMtfFvgRectangleForInstance(const ENUM_SMC_ZONE_TYPE zoneType,
                                            const datetime originBarTime)
{
   const string objName = SMCMtfFvgRectangleObjectName(zoneType, originBarTime);
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
}

//+------------------------------------------------------------------+
void SMCDrawMtfFvgRectangleForInstance(const int instanceIndex)
{
   if(instanceIndex < 0 || instanceIndex >= SMC_MTF_FVG_INSTANCE_CAPACITY)
      return;
   if(!g_mtfFvgInstances[instanceIndex].inUse || g_mtfFvgInstances[instanceIndex].isMitigated
      || g_mtfFvgInstances[instanceIndex].isExpired)
      return;

   const ENUM_TIMEFRAMES timeframe = g_mtfFvgInstances[instanceIndex].timeframe;
   if(!MtfSwingLegDrawEnabled(timeframe))
      return;

   const datetime timeLeft = g_mtfFvgInstances[instanceIndex].zoneOriginBarTime;
   const datetime timeRight = SMCZoneRectangleTimeRight(timeframe, timeLeft);
   const string objName = SMCMtfFvgRectangleObjectName(g_mtfFvgInstances[instanceIndex].type,
                                                        g_mtfFvgInstances[instanceIndex].zoneOriginBarTime);
   const double top    = g_mtfFvgInstances[instanceIndex].topPrice;
   const double bottom = g_mtfFvgInstances[instanceIndex].bottomPrice;
   if(timeLeft <= 0 || timeRight <= 0 || top <= bottom)
      return;

   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_RECTANGLE, 0, timeLeft, top, timeRight, bottom))
         return;
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, timeLeft);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, top);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeRight);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, bottom);
   }

   const color rectColor = SMCZoneTypeIsBullish(g_mtfFvgInstances[instanceIndex].type)
                           ? clrLimeGreen : clrDeepPink;
   ObjectSetInteger(0, objName, OBJPROP_COLOR, rectColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_FILL, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void SMCSyncMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
   {
      if(g_mtfFvgInstances[i].timeframe != timeframe)
         continue;

      if(g_mtfFvgInstances[i].inUse && !g_mtfFvgInstances[i].isMitigated && !g_mtfFvgInstances[i].isExpired)
         SMCDrawMtfFvgRectangleForInstance(i);
      else if(g_mtfFvgInstances[i].zoneOriginBarTime > 0)
         SMCDeleteMtfFvgRectangleForInstance(g_mtfFvgInstances[i].type,
                                             g_mtfFvgInstances[i].zoneOriginBarTime);
   }
}

//+------------------------------------------------------------------+
void SMCDrawMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   SMCSyncMtfFvgZoneRectanglesForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void SMCMapUnmitigatedFvgsForTimeframe(const ENUM_TIMEFRAMES timeframe,
                                        const ENUM_SMC_ZONE_TYPE bullZoneType,
                                        const ENUM_SMC_ZONE_TYPE bearZoneType)
{
   const int lookback = MathMax(3, InputSmcFvgLookbackBars);

   for(int middleShift = 2; middleShift <= lookback; middleShift++)
   {
      bool   isBullish = false;
      double bottom = 0.0;
      double top    = 0.0;
      if(!SMCDetectFvgAtMiddleShift(timeframe, middleShift, isBullish, bottom, top))
         continue;

      const ENUM_SMC_ZONE_TYPE zoneType = isBullish ? bullZoneType : bearZoneType;
      double regBottom = 0.0;
      double regTop    = 0.0;
      if(!SMCApplyMtfFvgGapZoneEdges(timeframe, isBullish, bottom, top, regBottom, regTop))
         continue;

      if(!SMCFvgGapMeetsMinPercentOfChart(timeframe, regBottom, regTop))
         continue;

      const int formationNewestShift = middleShift - 1;
      if(SMCFvgMitigated(timeframe, formationNewestShift, isBullish, regBottom, regTop))
         continue;

      const datetime origin = iTime(_Symbol, timeframe, middleShift);
      if(origin <= 0)
         continue;

      SMCUpsertMtfFvgInstance(zoneType, regBottom, regTop, origin);
   }
}

//+------------------------------------------------------------------+
bool SMCSwingExtremeViolatedSinceLegEnd(const ENUM_TIMEFRAMES timeframe,
                                         const datetime legStartTime,
                                         const datetime legEndTime,
                                         const bool checkHighViolation,
                                         const double level)
{
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   const int barsTotal = iBars(_Symbol, timeframe);
   if(barsTotal < 2)
      return false;

   for(int barShift = 1; barShift < barsTotal; barShift++)
   {
      const datetime barOpen = iTime(_Symbol, timeframe, barShift);
      if(barOpen == 0)
         continue;

      // Completed leg: only count closes on bars strictly after leg end (not the closing bar itself).
      if(legEndTime > 0)
      {
         if(barOpen <= legEndTime)
            continue;
      }
      else if(legStartTime > 0 && barOpen < legStartTime)
         continue;

      const double barClose = iClose(_Symbol, timeframe, barShift);
      if(checkHighViolation && barClose > level + eps)
         return true;
      if(!checkHighViolation && barClose < level - eps)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool SMCTryGetLatestUnbrokenSwingHigh(const SwingState &swingState,
                                       const ENUM_TIMEFRAMES timeframe,
                                       double &outLevel)
{
   outLevel = 0.0;

   for(int historyIndex = swingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(swingState.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double legHigh = swingState.swingHistory[historyIndex].legHighPrice;
      if(legHigh <= 0.0)
         continue;
      if(!SMCSwingExtremeViolatedSinceLegEnd(timeframe,
                                             swingState.swingHistory[historyIndex].legStartTime,
                                             swingState.swingHistory[historyIndex].legEndTime,
                                             true, legHigh))
      {
         outLevel = legHigh;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
bool SMCTryGetLatestUnbrokenSwingLow(const SwingState &swingState,
                                      const ENUM_TIMEFRAMES timeframe,
                                      double &outLevel)
{
   outLevel = 0.0;

   for(int historyIndex = swingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(swingState.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double legLow = swingState.swingHistory[historyIndex].legLowPrice;
      if(legLow <= 0.0)
         continue;
      if(!SMCSwingExtremeViolatedSinceLegEnd(timeframe,
                                             swingState.swingHistory[historyIndex].legStartTime,
                                             swingState.swingHistory[historyIndex].legEndTime,
                                             false, legLow))
      {
         outLevel = legLow;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
void SMCRegisterDedicatedSwingHighZone(const ENUM_SMC_ZONE_TYPE type, const double level,
                                        const double buffer, const datetime originBarTime = 0,
                                        const bool forceFreshZoneState = false)
{
   if(level <= 0.0 || buffer <= 0.0)
      return;
   RegisterOrMergeZone(type, level + buffer, level, originBarTime, forceFreshZoneState);
}

//+------------------------------------------------------------------+
void SMCRegisterDedicatedSwingLowZone(const ENUM_SMC_ZONE_TYPE type, const double level,
                                         const double buffer, const datetime originBarTime = 0,
                                         const bool forceFreshZoneState = false)
{
   if(level <= 0.0 || buffer <= 0.0)
      return;
   RegisterOrMergeZone(type, level, level - buffer, originBarTime, forceFreshZoneState);
}

//+------------------------------------------------------------------+
void SMCRegisterLiquidityHighZone(const ENUM_SMC_ZONE_TYPE type, const double level, const double buffer)
{
   if(level <= 0.0 || buffer <= 0.0)
      return;
   RegisterOrMergeZone(type, level + buffer, level, 0, false);
}

//+------------------------------------------------------------------+
void SMCRegisterLiquidityLowZone(const ENUM_SMC_ZONE_TYPE type, const double level, const double buffer)
{
   if(level <= 0.0 || buffer <= 0.0)
      return;
   RegisterOrMergeZone(type, level, level - buffer, 0, false);
}

//+------------------------------------------------------------------+
void SMCSeedSwingZonesFromHistory(const MTFSwingTracker &tracker,
                                   const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                                   const ENUM_SMC_ZONE_TYPE bearSwingHighType)
{
   if(tracker.timeframe == 0 || tracker.swing.swingHistoryCount <= 0)
      return;

   const double buffer = SMCSwingLevelBufferForTimeframe(tracker.timeframe);
   for(int historyIndex = 0; historyIndex < tracker.swing.swingHistoryCount; historyIndex++)
   {
      const Swing leg = tracker.swing.swingHistory[historyIndex];
      if(leg.legEndTime <= 0)
         continue;

      if(leg.swingDirection == 1 && leg.legHighPrice > 0.0)
         SMCRegisterDedicatedSwingHighZone(bearSwingHighType, leg.legHighPrice, buffer, leg.legEndTime, false);
      else if(leg.swingDirection == -1 && leg.legLowPrice > 0.0)
         SMCRegisterDedicatedSwingLowZone(bullSwingLowType, leg.legLowPrice, buffer, leg.legEndTime, false);
   }
}

//+------------------------------------------------------------------+
void SMCMapUnbrokenSwingZones(const MTFSwingTracker &tracker,
                               const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                               const ENUM_SMC_ZONE_TYPE bearSwingHighType)
{
   SMCSeedSwingZonesFromHistory(tracker, bullSwingLowType, bearSwingHighType);
}

//+------------------------------------------------------------------+
void SMCRegisterSwingZoneFromJustClosedLeg(const MTFSwingTracker &tracker,
                                             const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                                             const ENUM_SMC_ZONE_TYPE bearSwingHighType,
                                             int &outRegisteredSlot)
{
   outRegisteredSlot = -1;
   if(tracker.swing.swingHistoryCount <= 0)
      return;

   const Swing  closedLeg = tracker.swing.swingHistory[tracker.swing.swingHistoryCount - 1];
   const double buffer    = SMCSwingLevelBufferForTimeframe(tracker.timeframe);
   if(closedLeg.legEndTime <= 0)
      return;

   if(closedLeg.swingDirection == 1 && closedLeg.legHighPrice > 0.0)
      outRegisteredSlot = RegisterOrMergeZone(bearSwingHighType,
                                              closedLeg.legHighPrice + buffer,
                                              closedLeg.legHighPrice,
                                              closedLeg.legEndTime, true);
   else if(closedLeg.swingDirection == -1 && closedLeg.legLowPrice > 0.0)
      outRegisteredSlot = RegisterOrMergeZone(bullSwingLowType,
                                              closedLeg.legLowPrice,
                                              closedLeg.legLowPrice - buffer,
                                              closedLeg.legEndTime, true);
}

//+------------------------------------------------------------------+
void SMCMapProtectedStructuralZone(const MTFSwingTracker &tracker,
                                    const ENUM_SMC_ZONE_TYPE bullProtectedLowType,
                                    const ENUM_SMC_ZONE_TYPE bearProtectedHighType)
{
   if(tracker.lastBosDirection == 0 || tracker.lastBosLevel <= 0.0)
      return;

   const double buffer = SMCSwingLevelBufferForTimeframe(tracker.timeframe);

   if(tracker.lastBosDirection == 1)
   {
      if(tracker.lastBrokenLegLow > 0.0)
         SMCRegisterLiquidityLowZone(bullProtectedLowType, tracker.lastBrokenLegLow, buffer);
   }
   else if(tracker.lastBosDirection == -1)
   {
      if(tracker.lastBrokenLegHigh > 0.0)
         SMCRegisterLiquidityHighZone(bearProtectedHighType, tracker.lastBrokenLegHigh, buffer);
   }
}

//+------------------------------------------------------------------+
void SMCClearActiveZonesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_ZONE_TYPE_COUNT; i++)
   {
      const ENUM_SMC_ZONE_TYPE slotType = g_activeZones[i].isActive
         ? g_activeZones[i].type
         : (ENUM_SMC_ZONE_TYPE)i;
      if(SMCZoneTypeToTimeframe(slotType) != timeframe)
         continue;
      if(SMCZoneTypeIsMtfFvg(slotType))
         continue;

      g_activeZones[i].type               = (ENUM_SMC_ZONE_TYPE)i;
      g_activeZones[i].topPrice           = 0.0;
      g_activeZones[i].bottomPrice        = 0.0;
      g_activeZones[i].isActive           = false;
      g_activeZones[i].isClustered        = false;
      g_activeZones[i].isMitigated  = false;
      g_activeZones[i].isBreached   = false;
      g_activeZones[i].isExpired    = false;
      g_activeZones[i].zoneOriginBarTime  = 0;
   }
}

//+------------------------------------------------------------------+
string SMCZoneTimeframeTag(const ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_W1:  return "W1";
      case PERIOD_D1:  return "D1";
      case PERIOD_H4:  return "H4";
      case PERIOD_M15: return "M15";
   }
   return "TF";
}

//+------------------------------------------------------------------+
string SMCZoneRectangleObjectNameFromRecord(const ENUM_SMC_ZONE_TYPE zoneType,
                                             const int slotIndex,
                                             const datetime zoneOriginBarTime)
{
   if(zoneType < 0 || zoneType >= SMC_ZONE_TYPE_COUNT || zoneOriginBarTime <= 0)
      return "";

   const ENUM_TIMEFRAMES zoneTf = SMCZoneTypeToTimeframe(zoneType);
   return LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(zoneTf) + "_"
          + IntegerToString((int)zoneType) + "_S" + IntegerToString(slotIndex) + "_"
          + IntegerToString((long)zoneOriginBarTime);
}

//+------------------------------------------------------------------+
string SMCZoneRectangleObjectNameForSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return "";

   return SMCZoneRectangleObjectNameFromRecord(g_activeZones[slotIndex].type, slotIndex,
                                               g_activeZones[slotIndex].zoneOriginBarTime);
}

//+------------------------------------------------------------------+
void SMCDeleteZoneRectangleForSlot(const int slotIndex)
{
   const string objName = SMCZoneRectangleObjectNameForSlot(slotIndex);
   if(objName != "" && ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   if(slotIndex >= 0 && slotIndex < SMC_ZONE_TYPE_COUNT)
   {
      const ENUM_SMC_ZONE_TYPE zoneType = (ENUM_SMC_ZONE_TYPE)slotIndex;
      const string legacyName = LQ_OBJ_PREFIX_SMC_ZONE_RECT + IntegerToString(slotIndex);
      if(ObjectFind(0, legacyName) >= 0)
         ObjectDelete(0, legacyName);

      const string legacyTfName = LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(SMCZoneTypeToTimeframe(zoneType))
                                + "_" + IntegerToString(slotIndex);
      if(ObjectFind(0, legacyTfName) >= 0)
         ObjectDelete(0, legacyTfName);
   }
}

//+------------------------------------------------------------------+
//| Delete every non-FVG zone rectangle tied to a ledger slot index.  |
//+------------------------------------------------------------------+
void SMCDeleteAllZoneRectangleObjectsForSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return;

   SMCDeleteZoneRectangleForSlot(slotIndex);

   const string slotToken = "_S" + IntegerToString(slotIndex) + "_";
   const int total = ObjectsTotal(0, 0, -1);
   for(int o = total - 1; o >= 0; o--)
   {
      const string objName = ObjectName(0, o, 0, -1);
      if(StringFind(objName, LQ_OBJ_PREFIX_SMC_ZONE_RECT) != 0)
         continue;
      if(StringFind(objName, "_FVG_") >= 0)
         continue;
      if(StringFind(objName, slotToken) < 0)
         continue;
      ObjectDelete(0, objName);
   }
}

//+------------------------------------------------------------------+
bool SMCZoneChartObjectShouldRemain(const string objName, const ENUM_TIMEFRAMES timeframe)
{
   if(objName == "")
      return false;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive || g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
         continue;
      if(SMCZoneTypeToTimeframe(g_activeZones[i].type) != timeframe)
         continue;
      if(SMCZoneRectangleObjectNameForSlot(i) == objName)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool SMCMtfFvgChartObjectShouldRemain(const string objName, const ENUM_TIMEFRAMES timeframe)
{
   if(objName == "")
      return false;

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         continue;
      if(g_mtfFvgInstances[f].timeframe != timeframe)
         continue;
      if(SMCMtfFvgRectangleObjectName(g_mtfFvgInstances[f].type,
                                      g_mtfFvgInstances[f].zoneOriginBarTime) == objName)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void SMCSweepOrphanZoneChartObjectsForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const string zonePrefix = LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(timeframe) + "_";
   const string fvgPrefix  = zonePrefix + "FVG_";
   const int total = ObjectsTotal(0, 0, -1);

   for(int o = total - 1; o >= 0; o--)
   {
      const string objName = ObjectName(0, o, 0, -1);
      if(StringFind(objName, zonePrefix) != 0)
         continue;

      if(StringFind(objName, fvgPrefix) == 0)
      {
         if(!SMCMtfFvgChartObjectShouldRemain(objName, timeframe))
            ObjectDelete(0, objName);
         continue;
      }

      if(!SMCZoneChartObjectShouldRemain(objName, timeframe))
         ObjectDelete(0, objName);
   }
}

//+------------------------------------------------------------------+
void SMCDrawZoneRectangleForSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return;
   if(!g_activeZones[slotIndex].isActive || g_activeZones[slotIndex].isMitigated || g_activeZones[slotIndex].isExpired)
      return;
   if(SMCZoneTypeIsMtfFvg(g_activeZones[slotIndex].type))
      return;

   const ENUM_TIMEFRAMES timeframe = SMCZoneTypeToTimeframe(g_activeZones[slotIndex].type);
   if(!MtfSwingLegDrawEnabled(timeframe))
      return;

   const datetime timeLeft = (g_activeZones[slotIndex].zoneOriginBarTime > 0
                              ? g_activeZones[slotIndex].zoneOriginBarTime
                              : iTime(_Symbol, timeframe, 1));
   const datetime timeRight = SMCZoneRectangleTimeRight(timeframe, timeLeft);
   const string objName = SMCZoneRectangleObjectNameForSlot(slotIndex);
   const double top = g_activeZones[slotIndex].topPrice;
   const double bottom = g_activeZones[slotIndex].bottomPrice;
   if(timeRight <= 0 || timeLeft <= 0 || top <= bottom || objName == "")
      return;

   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_RECTANGLE, 0, timeLeft, top, timeRight, bottom))
         return;
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, timeLeft);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, top);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeRight);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, bottom);
   }

   const color rectColor = SMCZoneTypeIsBullish(g_activeZones[slotIndex].type) ? clrLimeGreen : clrDeepPink;
   ObjectSetInteger(0, objName, OBJPROP_COLOR, rectColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_FILL, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void SMCSyncZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(SMCZoneTypeIsMtfFvg(g_activeZones[i].type))
         continue;
      if(SMCZoneTypeToTimeframe(g_activeZones[i].type) != timeframe)
         continue;

      if(g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
         SMCDeleteAllZoneRectangleObjectsForSlot(i);
      else
         SMCDrawZoneRectangleForSlot(i);
   }
}

//+------------------------------------------------------------------+
void SMCCleanupMitigatedExpiredZoneChartObjectsForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(g_activeZones[i].isMitigated || g_activeZones[i].isExpired || !g_activeZones[i].isActive)
      {
         SMCDeleteAllZoneRectangleObjectsForSlot(i);
         continue;
      }

      const ENUM_SMC_ZONE_TYPE zoneType = g_activeZones[i].type;
      if(zoneType < 0 || zoneType >= SMC_ZONE_TYPE_COUNT)
         continue;
      if(SMCZoneTypeIsMtfFvg(zoneType))
         continue;
      if(SMCZoneTypeToTimeframe(zoneType) != timeframe)
         continue;
   }

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(g_mtfFvgInstances[f].timeframe != timeframe)
         continue;
      if(g_mtfFvgInstances[f].zoneOriginBarTime <= 0)
         continue;

      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         SMCDeleteMtfFvgRectangleForInstance(g_mtfFvgInstances[f].type,
                                             g_mtfFvgInstances[f].zoneOriginBarTime);
   }

   SMCSweepOrphanZoneChartObjectsForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void SMCDeleteZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const string prefix = LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(timeframe) + "_";
   const int total = ObjectsTotal(0, 0, -1);
   for(int o = total - 1; o >= 0; o--)
   {
      const string objName = ObjectName(0, o, 0, -1);
      if(StringFind(objName, prefix) == 0 && StringFind(objName, "_FVG_") < 0)
         ObjectDelete(0, objName);
   }
}

//+------------------------------------------------------------------+
void SMCDrawZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   SMCSyncZoneRectanglesForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void SMCRefreshZonesForTimeframe(const ENUM_TIMEFRAMES timeframe, MTFSwingTracker &tracker,
                                  const bool legClosedThisBar)
{
   if(!InputEnableMtfSmcEngine)
      return;

   if(legClosedThisBar)
   {
      int registeredSlot = -1;
      switch(timeframe)
      {
         case PERIOD_W1:
            SMCRegisterSwingZoneFromJustClosedLeg(tracker, ZONE_BULL_SWING_W1_LOW, ZONE_BEAR_SWING_W1_HIGH,
                                                  registeredSlot);
            break;
         case PERIOD_D1:
            SMCRegisterSwingZoneFromJustClosedLeg(tracker, ZONE_BULL_SWING_DAILY_LOW, ZONE_BEAR_SWING_DAILY_HIGH,
                                                  registeredSlot);
            break;
         case PERIOD_H4:
            SMCRegisterSwingZoneFromJustClosedLeg(tracker, ZONE_BULL_SWING_H4_LOW, ZONE_BEAR_SWING_H4_HIGH,
                                                  registeredSlot);
            break;
         case PERIOD_M15:
            SMCRegisterSwingZoneFromJustClosedLeg(tracker, ZONE_BULL_SWING_M15_LOW, ZONE_BEAR_SWING_M15_HIGH,
                                                  registeredSlot);
            break;
         default:
            return;
      }

      if(registeredSlot >= 0)
         SMCDrawZoneRectangleForSlot(registeredSlot);

      SMCApplyZoneExitBiasAndMitigationForTimeframe(timeframe);
      SMCExpireZonesPastBarLimitForTimeframe(timeframe);
      SMCExpireMtfFvgInstancesForTimeframe(timeframe);
      SMCCleanupMitigatedExpiredZoneChartObjectsForTimeframe(timeframe);
      SMCSyncZoneRectanglesForTimeframe(timeframe);
      SMCSyncMtfFvgZoneRectanglesForTimeframe(timeframe);
      return;
   }

   switch(timeframe)
   {
      case PERIOD_W1:
         SMCMapUnmitigatedFvgsForTimeframe(PERIOD_W1, ZONE_BULL_WEEKLY_FVG, ZONE_BEAR_WEEKLY_FVG);
         break;

      case PERIOD_D1:
         SMCMapUnmitigatedFvgsForTimeframe(PERIOD_D1, ZONE_BULL_DAILY_FVG, ZONE_BEAR_DAILY_FVG);
         SMCMapProtectedStructuralZone(tracker,
                                       ZONE_BULL_PROTECTED_DAILY_LOW, ZONE_BEAR_PROTECTED_DAILY_HIGH);
         break;

      case PERIOD_H4:
         SMCMapUnmitigatedFvgsForTimeframe(PERIOD_H4, ZONE_BULL_H4_FVG, ZONE_BEAR_H4_FVG);
         SMCMapProtectedStructuralZone(tracker,
                                       ZONE_BULL_PROTECTED_H4_LOW, ZONE_BEAR_PROTECTED_H4_HIGH);
         break;

      case PERIOD_M15:
         SMCMapUnmitigatedFvgsForTimeframe(PERIOD_M15, ZONE_BULL_M15_FVG, ZONE_BEAR_M15_FVG);
         SMCMapProtectedStructuralZone(tracker,
                                       ZONE_BULL_PROTECTED_M15_LOW, ZONE_BEAR_PROTECTED_M15_HIGH);
         break;

      default:
         return;
   }

   SMCApplyZoneExitBiasAndMitigationForTimeframe(timeframe);
   SMCExpireZonesPastBarLimitForTimeframe(timeframe);
   SMCExpireMtfFvgInstancesForTimeframe(timeframe);
   SMCCleanupMitigatedExpiredZoneChartObjectsForTimeframe(timeframe);
   SMCSyncZoneRectanglesForTimeframe(timeframe);
   SMCSyncMtfFvgZoneRectanglesForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void UpdateSMCZoneMatrix()
{
   if(!InputEnableMtfSmcEngine)
      return;

   SMCSeedSwingZonesFromHistory(g_mtfSwingW1,  ZONE_BULL_SWING_W1_LOW,  ZONE_BEAR_SWING_W1_HIGH);
   SMCSeedSwingZonesFromHistory(g_mtfSwingD1,  ZONE_BULL_SWING_DAILY_LOW, ZONE_BEAR_SWING_DAILY_HIGH);
   SMCSeedSwingZonesFromHistory(g_mtfSwingH4,  ZONE_BULL_SWING_H4_LOW,  ZONE_BEAR_SWING_H4_HIGH);
   SMCSeedSwingZonesFromHistory(g_mtfSwingM15, ZONE_BULL_SWING_M15_LOW, ZONE_BEAR_SWING_M15_HIGH);

   SMCRefreshZonesForTimeframe(PERIOD_W1,  g_mtfSwingW1,  false);
   SMCRefreshZonesForTimeframe(PERIOD_D1,  g_mtfSwingD1,  false);
   SMCRefreshZonesForTimeframe(PERIOD_H4,  g_mtfSwingH4,  false);
   SMCRefreshZonesForTimeframe(PERIOD_M15, g_mtfSwingM15, false);
}

//+------------------------------------------------------------------+
//| Completed H4 swing legs in lookback: up-leg high / down-leg low pivots only.   |
//| Pivot up high: legHigh beats every newer up-leg high; pivot down low: vice versa. |
//+------------------------------------------------------------------+

#endif // H4_LQ_V3_SMCZONES
