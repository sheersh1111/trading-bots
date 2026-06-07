//+------------------------------------------------------------------+
//| h1_touch_m5_bos_m2_fvg_trade.mq5                                 |
//| H1 up-leg high → M5 touch + extension cap → bear M5 BOS → bear M2 FVG |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.01"
#property description "H1 up-leg high touch; extension cap vs H1 height; bear M5 BOS; bear M2 FVG near M5 up-leg high."

#include <Trade\Trade.mqh>

input bool     InputSwitchChartToM2              = true;
input int      InputWarmupBarsPerTf              = 500;
input int      InputH1RangeBarsForHeight         = 120;
input double   InputMaxExtBeyondH1PctOfHeight    = 7.1;
input int      InputTouchLookbackM5Bars         = 48;
input double   InputFvgNearBandPctOfH1Height     = 4.0;
input int      InputM2FvgMaxScanShift            = 80;
input double   InputM2FvgMinGapPctOfM2Range      = 0.0;
input int      InputM2FvgRangeBars               = 200;
input bool     InputTradeEnabled                 = true;
input double   InputRiskPercentTotal             = 1.0;
input double   InputSlPctOfM2ChartHeight         = 2.0;
input int      InputTradeM2ChartHeightBars       = 200;
input ulong    InputMagicNumber                  = 9100711;
input int      InputSlippagePoints               = 20;
input string   InputCommentPrefix                = "H1M5M2";
input bool     InputOneSetupPerH1Leg             = true;

CTrade g_trade;

struct Swing
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection;
};

struct SwingState
{
   Swing    currentSwingLeg;
   Swing    swingHistory[20];
   int      swingHistoryCount;
   double   priceAnchorLevel;
};

const string GV_PLAN = "H1M5M2FVG_";

SwingState g_h1;
SwingState g_m5;

datetime g_lastH1Open = 0;
datetime g_lastM5Open = 0;

//--- Short path: H1 completed up-leg high
bool     g_sh_active;
double   g_sh_h1High;
datetime g_sh_h1LegEnd;
bool     g_sh_touched;
datetime g_sh_firstTouchBarOpen;
double   g_sh_maxHighSinceTouch;
bool     g_sh_invalidExt;
bool     g_sh_used;

//+------------------------------------------------------------------+
void SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                   const double highPrice, const double lowPrice, const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.swingDirection = swingDirection;
   swingState.currentSwingLeg.legHighPrice   = highPrice;
   swingState.currentSwingLeg.legLowPrice    = lowPrice;
   swingState.currentSwingLeg.legStartTime   = iTime(_Symbol, timeframe, lastClosedBarShift);
}

void SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice)
{
   if(highPrice > swingState.currentSwingLeg.legHighPrice)
      swingState.currentSwingLeg.legHighPrice = highPrice;
   if(lowPrice < swingState.currentSwingLeg.legLowPrice)
      swingState.currentSwingLeg.legLowPrice = lowPrice;
}

void SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);
   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int i = 1; i < 20; i++)
         swingState.swingHistory[i - 1] = swingState.swingHistory[i];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

void ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh)
{
   const double o = iOpen(_Symbol, timeframe, sh);
   const double c = iClose(_Symbol, timeframe, sh);
   const double hi = iHigh(_Symbol, timeframe, sh);
   const double lo = iLow(_Symbol, timeframe, sh);

   const int candleDirection = (c > o) ? 1 : ((c < o) ? -1 : 0);
   const double barRange = hi - lo;

   if(swingState.currentSwingLeg.swingDirection == 0)
   {
      if(candleDirection == 0)
         return;
      SwingStartNew(swingState, timeframe, candleDirection, hi, lo, sh);
      swingState.priceAnchorLevel = (hi + lo) / 2.0;
      return;
   }

   double sumR = 0.0;
   const int barsTotal = iBars(_Symbol, timeframe);
   int       cnt = 0;
   for(int k = sh + 1; k <= sh + 5; k++)
   {
      if(k >= barsTotal)
         break;
      sumR += (iHigh(_Symbol, timeframe, k) - iLow(_Symbol, timeframe, k));
      cnt++;
   }
   const double avgR = (cnt > 0) ? sumR / (double)cnt : 0.0;
   const bool decent = (barRange > (avgR * 0.6));
   if(decent && candleDirection == swingState.currentSwingLeg.swingDirection)
      swingState.priceAnchorLevel = (hi + lo) / 2.0;

   int nextDir = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && c < swingState.priceAnchorLevel)
      nextDir = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && c > swingState.priceAnchorLevel)
      nextDir = 1;

   if(nextDir == swingState.currentSwingLeg.swingDirection)
   {
      SwingExtend(swingState, hi, lo);
   }
   else
   {
      SwingExtend(swingState, hi, lo);
      SwingClose(swingState, timeframe, sh);

      Swing closed = swingState.swingHistory[swingState.swingHistoryCount - 1];
      double nh = hi, nl = lo;
      if(closed.swingDirection == 1 && nextDir == -1)
         nh = MathMax(hi, closed.legHighPrice);
      else if(closed.swingDirection == -1 && nextDir == 1)
         nl = MathMin(lo, closed.legLowPrice);

      SwingStartNew(swingState, timeframe, nextDir, nh, nl, sh);
      swingState.priceAnchorLevel = (hi + lo) / 2.0;
   }
}

void WarmupSwingState(SwingState &st, const ENUM_TIMEFRAMES tf)
{
   if(InputWarmupBarsPerTf <= 0)
      return;
   const int n = (int)MathMin(iBars(_Symbol, tf) - 2, InputWarmupBarsPerTf);
   for(int k = n; k >= 1; k--)
      ProcessSwingStepAtShift(st, tf, k);
}

//+------------------------------------------------------------------+
bool TryDetectBosOnLastClosedBar(SwingState &st, const ENUM_TIMEFRAMES tf, bool &outBullishBos)
{
   outBullishBos = false;
   if(st.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, tf, 1);
   const double prevClose  = iClose(_Symbol, tf, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int hi = st.swingHistoryCount - 1; hi >= 0; hi--)
   {
      if(st.swingHistory[hi].swingDirection != 1)
         continue;
      const double lvl = st.swingHistory[hi].legHighPrice;
      if(closePrice > lvl + pointSize && prevClose <= lvl + pointSize)
      {
         outBullishBos = true;
         return true;
      }
      break;
   }
   for(int hi = st.swingHistoryCount - 1; hi >= 0; hi--)
   {
      if(st.swingHistory[hi].swingDirection != -1)
         continue;
      const double lvl = st.swingHistory[hi].legLowPrice;
      if(closePrice < lvl - pointSize && prevClose >= lvl - pointSize)
      {
         outBullishBos = false;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
double ReferenceChartHeight(const ENUM_TIMEFRAMES tf, const int barCount)
{
   if(barCount < 1 || iBars(_Symbol, tf) < barCount + 1)
      return 0.0;
   double hh = -1.0e100;
   double ll = 1.0e100;
   for(int i = 1; i <= barCount; i++)
   {
      hh = MathMax(hh, iHigh(_Symbol, tf, i));
      ll = MathMin(ll, iLow(_Symbol, tf, i));
   }
   return hh - ll;
}

double M2RangeHeight(const int barCount)
{
   if(barCount < 1 || iBars(_Symbol, PERIOD_M2) < barCount + 1)
      return 0.0;
   double hi = -1.0e100;
   double lo = 1.0e100;
   for(int i = 1; i <= barCount; i++)
   {
      hi = MathMax(hi, iHigh(_Symbol, PERIOD_M2, i));
      lo = MathMin(lo, iLow(_Symbol, PERIOD_M2, i));
   }
   return hi - lo;
}

bool M2FvgGapPassesMinSize(const double zLo, const double zHi)
{
   if(InputM2FvgMinGapPctOfM2Range <= 0.0)
      return true;
   const double gap = MathAbs(zHi - zLo);
   if(gap <= 0.0)
      return false;
   const double rh = M2RangeHeight(InputM2FvgRangeBars);
   if(rh <= 0.0)
      return true;
   return gap >= rh * (InputM2FvgMinGapPctOfM2Range / 100.0);
}

bool TryM2FairValueGapAtShift(const int s, bool &outBull, double &outZlo, double &outZhi)
{
   outBull = false;
   outZlo = outZhi = 0.0;
   if(s < 1 || iBars(_Symbol, PERIOD_M2) < s + 3)
      return false;

   const double l1 = iLow(_Symbol, PERIOD_M2, s);
   const double h1 = iHigh(_Symbol, PERIOD_M2, s);
   const double h3 = iHigh(_Symbol, PERIOD_M2, s + 2);
   const double l3 = iLow(_Symbol, PERIOD_M2, s + 2);

   if(l1 > h3)
   {
      outBull = true;
      outZlo = h3;
      outZhi = l1;
      return M2FvgGapPassesMinSize(outZlo, outZhi);
   }
   if(h1 < l3)
   {
      outBull = false;
      outZlo = h1;
      outZhi = l3;
      return M2FvgGapPassesMinSize(outZlo, outZhi);
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryLatestCompletedH1UpLeg(double &outHigh, datetime &outLegEnd)
{
   for(int i = g_h1.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_h1.swingHistory[i].swingDirection == 1)
      {
         outHigh   = g_h1.swingHistory[i].legHighPrice;
         outLegEnd = g_h1.swingHistory[i].legEndTime;
         return true;
      }
   }
   return false;
}

double LatestM5UpLegHigh()
{
   for(int i = g_m5.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m5.swingHistory[i].swingDirection == 1)
         return g_m5.swingHistory[i].legHighPrice;
   }
   if(g_m5.currentSwingLeg.swingDirection == 1)
      return g_m5.currentSwingLeg.legHighPrice;
   return 0.0;
}

bool FvgZoneNearPrice(const double zLo, const double zHi, const double refPrice, const double band)
{
   const double a = MathMin(zLo, zHi);
   const double b = MathMax(zLo, zHi);
   const double loP = refPrice - band;
   const double hiP = refPrice + band;
   return (b >= loP && a <= hiP);
}

//+------------------------------------------------------------------+
void ApplyTradeFillingModeFromSymbol()
{
   const long fillingMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(fillingMode == 0)
      return;
   if((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

double NormalizePriceToTick(const double price)
{
   const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

double CalculateVolumeForFixedRisk(const ENUM_ORDER_TYPE orderTypeForCalc, const double entryPrice,
                                   const double stopLossPrice, const double riskMoney)
{
   double profitAtStop = 0.0;
   if(!OrderCalcProfit(orderTypeForCalc, _Symbol, 1.0, entryPrice, stopLossPrice, profitAtStop))
      return 0.0;

   const double lossPerLot = (profitAtStop < 0.0) ? -profitAtStop : profitAtStop;
   if(lossPerLot <= 0.0)
      return 0.0;

   double volume = riskMoney / lossPerLot;
   const double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double volumeMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double volumeMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(volumeStep > 0.0)
      volume = MathFloor(volume / volumeStep) * volumeStep;
   if(volume < volumeMin)
      volume = volumeMin;
   if(volume > volumeMax)
      volume = volumeMax;

   return volume;
}

bool StopsDistanceOk(const bool isBuy, const double entryPrice, const double stopLossPrice,
                     const double takeProfitPrice)
{
   const int    stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double pointSize        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minDistance      = (double)stopsLevelPoints * pointSize;
   if(minDistance <= 0.0)
      return true;

   if(isBuy)
   {
      if(MathAbs(entryPrice - stopLossPrice) < minDistance)
         return false;
      if(MathAbs(takeProfitPrice - entryPrice) < minDistance)
         return false;
   }
   else
   {
      if(MathAbs(stopLossPrice - entryPrice) < minDistance)
         return false;
      if(MathAbs(entryPrice - takeProfitPrice) < minDistance)
         return false;
   }
   return true;
}

bool HasPlanTagActive(const string &planKey)
{
   if(GlobalVariableCheck(GV_PLAN + planKey))
      return true;

   const string needle = InputCommentPrefix + "|" + planKey;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InputMagicNumber)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), needle) >= 0)
         return true;
   }

   for(int j = PositionsTotal() - 1; j >= 0; j--)
   {
      const ulong pt = PositionGetTicket(j);
      if(pt == 0 || !PositionSelectByTicket(pt))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InputMagicNumber)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), needle) >= 0)
         return true;
   }
   return false;
}

bool TryPlaceFvgSplitPending(const int patternShiftS, const bool bullGap,
                             const double zL, const double zH,
                             const datetime tOld, const datetime tNew,
                             const string &planKey)
{
   if(!InputTradeEnabled)
      return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return false;

   if(HasPlanTagActive(planKey))
      return false;

   if(patternShiftS < 1 || iBars(_Symbol, PERIOD_M2) < patternShiftS + 3)
      return false;

   const int    midSh   = patternShiftS + 1;
   const double midHigh = iHigh(_Symbol, PERIOD_M2, midSh);
   const double midLow  = iLow(_Symbol, PERIOD_M2, midSh);

   const double chartH = M2RangeHeight(InputTradeM2ChartHeightBars);
   if(chartH <= 0.0)
      return false;

   const double buf = chartH * (InputSlPctOfM2ChartHeight / 100.0);
   if(buf <= 0.0)
      return false;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double entryRaw =
      (MathAbs(bid - zL) <= MathAbs(bid - zH)) ? zL : zH;
   const double entry = NormalizePriceToTick(entryRaw);

   double sl;
   if(bullGap)
   {
      sl = NormalizePriceToTick(midLow - buf);
      if(sl >= entry || entry >= ask)
         return false;
   }
   else
   {
      sl = NormalizePriceToTick(midHigh + buf);
      if(sl <= entry || entry <= bid)
         return false;
   }

   const double rDist = MathAbs(entry - sl);
   if(rDist <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
      return false;

   const ENUM_ORDER_TYPE calcType = bullGap ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   const double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   const double riskMoney = balance * (InputRiskPercentTotal / 100.0);
   if(riskMoney <= 0.0)
      return false;

   double totalVol = CalculateVolumeForFixedRisk(calcType, entry, sl, riskMoney);
   if(totalVol <= 0.0)
      return false;

   const double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double vMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vEach = totalVol / 3.0;
   if(vStep > 0.0)
      vEach = MathFloor(vEach / vStep) * vStep;
   if(vEach < vMin)
      return false;

   double tp1, tp2, tp3;
   if(bullGap)
   {
      tp1 = NormalizePriceToTick(entry + rDist);
      tp2 = NormalizePriceToTick(entry + 2.0 * rDist);
      tp3 = NormalizePriceToTick(entry + 3.0 * rDist);
   }
   else
   {
      tp1 = NormalizePriceToTick(entry - rDist);
      tp2 = NormalizePriceToTick(entry - 2.0 * rDist);
      tp3 = NormalizePriceToTick(entry - 3.0 * rDist);
   }

   if(!StopsDistanceOk(bullGap, entry, sl, tp1) ||
      !StopsDistanceOk(bullGap, entry, sl, tp2) ||
      !StopsDistanceOk(bullGap, entry, sl, tp3))
      return false;

   g_trade.SetExpertMagicNumber(InputMagicNumber);
   g_trade.SetDeviationInPoints(InputSlippagePoints);

   const string c1 = InputCommentPrefix + "|" + planKey + "|1R";
   const string c2 = InputCommentPrefix + "|" + planKey + "|2R";
   const string c3 = InputCommentPrefix + "|" + planKey + "|3R";

   bool o1, o2, o3;
   if(bullGap)
   {
      o1 = g_trade.BuyLimit(vEach, entry, _Symbol, sl, tp1, ORDER_TIME_GTC, 0, c1);
      o2 = g_trade.BuyLimit(vEach, entry, _Symbol, sl, tp2, ORDER_TIME_GTC, 0, c2);
      o3 = g_trade.BuyLimit(vEach, entry, _Symbol, sl, tp3, ORDER_TIME_GTC, 0, c3);
   }
   else
   {
      o1 = g_trade.SellLimit(vEach, entry, _Symbol, sl, tp1, ORDER_TIME_GTC, 0, c1);
      o2 = g_trade.SellLimit(vEach, entry, _Symbol, sl, tp2, ORDER_TIME_GTC, 0, c2);
      o3 = g_trade.SellLimit(vEach, entry, _Symbol, sl, tp3, ORDER_TIME_GTC, 0, c3);
   }

   if(o1 && o2 && o3)
   {
      GlobalVariableSet(GV_PLAN + planKey, (double)TimeCurrent());
      return true;
   }

   const string partialTag = InputCommentPrefix + "|" + planKey;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InputMagicNumber)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), partialTag) >= 0)
         g_trade.OrderDelete(ticket);
   }
   return false;
}

//+------------------------------------------------------------------+
void RefreshH1KeyWatchTargets()
{
   double h;
   datetime te;
   if(TryLatestCompletedH1UpLeg(h, te))
   {
      if(!g_sh_active || te != g_sh_h1LegEnd)
      {
         g_sh_active = true;
         g_sh_h1High = h;
         g_sh_h1LegEnd = te;
         g_sh_touched = false;
         g_sh_firstTouchBarOpen = 0;
         g_sh_maxHighSinceTouch = 0.0;
         g_sh_invalidExt = false;
         g_sh_used = false;
      }
   }
   else
      g_sh_active = false;
}

void UpdateTouchAndExtensionShort()
{
   if(!g_sh_active || (InputOneSetupPerH1Leg && g_sh_used))
      return;

   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double h1Ref = ReferenceChartHeight(PERIOD_H1, InputH1RangeBarsForHeight);
   if(h1Ref <= 0.0)
      return;

   const double extPx = h1Ref * (InputMaxExtBeyondH1PctOfHeight / 100.0);
   const int    maxS  = (int)MathMin(InputTouchLookbackM5Bars, iBars(_Symbol, PERIOD_M5) - 1);

   if(!g_sh_touched)
   {
      for(int s = maxS; s >= 0; s--)
      {
         if(iTime(_Symbol, PERIOD_M5, s) < g_sh_h1LegEnd)
            continue;
         if(iHigh(_Symbol, PERIOD_M5, s) >= g_sh_h1High - 3.0 * pt)
         {
            g_sh_touched = true;
            g_sh_firstTouchBarOpen = iTime(_Symbol, PERIOD_M5, s);
            g_sh_maxHighSinceTouch = iHigh(_Symbol, PERIOD_M5, s);
            break;
         }
      }
   }

   if(g_sh_touched)
   {
      for(int s = 0; s <= maxS; s++)
      {
         if(iTime(_Symbol, PERIOD_M5, s) < g_sh_firstTouchBarOpen)
            continue;
         g_sh_maxHighSinceTouch = MathMax(g_sh_maxHighSinceTouch, iHigh(_Symbol, PERIOD_M5, s));
      }
      if(g_sh_maxHighSinceTouch > g_sh_h1High + extPx)
         g_sh_invalidExt = true;
   }
}

void TryShortEntryOnM5Bar()
{
   if(!g_sh_active || (InputOneSetupPerH1Leg && g_sh_used) || !g_sh_touched || g_sh_invalidExt)
      return;

   bool bullBos = false;
   if(!TryDetectBosOnLastClosedBar(g_m5, PERIOD_M5, bullBos))
      return;
   if(bullBos)
      return;

   const datetime bosBarOpen = iTime(_Symbol, PERIOD_M5, 1);
   if(g_sh_firstTouchBarOpen > bosBarOpen)
      return;

   const double h1Ref = ReferenceChartHeight(PERIOD_H1, InputH1RangeBarsForHeight);
   if(h1Ref <= 0.0)
      return;
   const double band = h1Ref * (InputFvgNearBandPctOfH1Height / 100.0);

   const double m5RefHigh = LatestM5UpLegHigh();
   if(m5RefHigh <= 0.0)
      return;

   const int maxS = (int)MathMin(InputM2FvgMaxScanShift, iBars(_Symbol, PERIOD_M2) - 3);
   for(int s = 1; s <= maxS; s++)
   {
      bool bullFvg;
      double zL, zH;
      if(!TryM2FairValueGapAtShift(s, bullFvg, zL, zH))
         continue;
      if(bullFvg)
         continue;

      if(!FvgZoneNearPrice(zL, zH, m5RefHigh, band))
         continue;

      const datetime tNew = iTime(_Symbol, PERIOD_M2, s);
      const datetime tOld = iTime(_Symbol, PERIOD_M2, s + 2);
      const string planKey =
         StringFormat("SH_%lld_%lld_%lld", (long)g_sh_h1LegEnd, (long)bosBarOpen, (long)tOld);

      if(TryPlaceFvgSplitPending(s, false, zL, zH, tOld, tNew, planKey))
      {
         if(InputOneSetupPerH1Leg)
            g_sh_used = true;
         return;
      }
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToM2)
   {
      ChartSetSymbolPeriod(0, _Symbol, PERIOD_M2);
      ChartRedraw(0);
   }

   ZeroMemory(g_h1);
   ZeroMemory(g_m5);
   WarmupSwingState(g_h1, PERIOD_H1);
   WarmupSwingState(g_m5, PERIOD_M5);

   g_trade.SetExpertMagicNumber(InputMagicNumber);
   ApplyTradeFillingModeFromSymbol();

   g_lastH1Open = iTime(_Symbol, PERIOD_H1, 0);
   g_lastM5Open = iTime(_Symbol, PERIOD_M5, 0);

   RefreshH1KeyWatchTargets();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   const datetime tH1 = iTime(_Symbol, PERIOD_H1, 0);
   if(tH1 != g_lastH1Open)
   {
      g_lastH1Open = tH1;
      ProcessSwingStepAtShift(g_h1, PERIOD_H1, 1);
      RefreshH1KeyWatchTargets();
   }

   const datetime tM5 = iTime(_Symbol, PERIOD_M5, 0);
   if(tM5 != g_lastM5Open)
   {
      g_lastM5Open = tM5;
      ProcessSwingStepAtShift(g_m5, PERIOD_M5, 1);
      UpdateTouchAndExtensionShort();
      TryShortEntryOnM5Bar();
   }
   else
      UpdateTouchAndExtensionShort();
}

//+------------------------------------------------------------------+
