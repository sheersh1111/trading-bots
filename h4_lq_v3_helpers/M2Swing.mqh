//+------------------------------------------------------------------+
//| M2Swing.mqh
//| M2 swing step and visuals
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_M2SWING
#define H4_LQ_V3_M2SWING

void WarmupM2SwingFromHistory()
{
   if(InputM2SwingWarmupBars <= 0)
      return;
   const int bars = iBars(_Symbol, InputM2NarrativeTimeframe);
   const int minNeed = 8;
   if(bars < minNeed)
      return;
   const int n = (int)MathMin(bars - 2, InputM2SwingWarmupBars);
   if(n < 1)
      return;
   for(int k = n; k >= 1; k--)
   {
      ProcessSwingStepAtShift(g_m2Swing, InputM2NarrativeTimeframe, k, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL,
                              true);
   }
}

//+------------------------------------------------------------------+
void PushLiquidityPoolFromClosedSwing(const double poolLowPrice, const double poolHighPrice,
                                      const bool isSupplyPool)
{
   if(poolLowPrice >= poolHighPrice)
      return;

   if(g_liquidityPoolCount < LiquidityPoolCapacity)
   {
      g_liquidityPools[g_liquidityPoolCount].poolLowPrice  = poolLowPrice;
      g_liquidityPools[g_liquidityPoolCount].poolHighPrice = poolHighPrice;
      g_liquidityPools[g_liquidityPoolCount].isSupplyPool   = isSupplyPool;
      g_liquidityPoolCount++;
   }
   else
   {
      for(int poolShiftIndex = 1; poolShiftIndex < LiquidityPoolCapacity; poolShiftIndex++)
         g_liquidityPools[poolShiftIndex - 1] = g_liquidityPools[poolShiftIndex];
      g_liquidityPools[LiquidityPoolCapacity - 1].poolLowPrice  = poolLowPrice;
      g_liquidityPools[LiquidityPoolCapacity - 1].poolHighPrice = poolHighPrice;
      g_liquidityPools[LiquidityPoolCapacity - 1].isSupplyPool  = isSupplyPool;
   }
}

//+------------------------------------------------------------------+
void SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                   const double highPrice, const double lowPrice, const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.swingDirection = swingDirection;
   swingState.currentSwingLeg.legHighPrice   = highPrice;
   swingState.currentSwingLeg.legLowPrice    = lowPrice;
   swingState.currentSwingLeg.keyLevelId     = 0;
   swingState.currentSwingLeg.legStartTime   = iTime(_Symbol, timeframe, lastClosedBarShift);
}

//+------------------------------------------------------------------+
void SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice)
{
   if(highPrice > swingState.currentSwingLeg.legHighPrice)
      swingState.currentSwingLeg.legHighPrice = highPrice;
   if(lowPrice < swingState.currentSwingLeg.legLowPrice)
      swingState.currentSwingLeg.legLowPrice = lowPrice;
}

//+------------------------------------------------------------------+
void DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                       const double labelPrice, const bool isUplegSwingDirection, const int keyLevelIdForLabel)
{
   const string chartObjectName = chartObjectNamePrefix + IntegerToString((long)labelBarTime);
   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

   const double symbolPointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double labelVerticalOffset =
      isUplegSwingDirection ? (labelPrice + symbolPointSize * 8.0) : (labelPrice - symbolPointSize * 8.0);

   if(!ObjectCreate(0, chartObjectName, OBJ_TEXT, 0, labelBarTime, labelVerticalOffset))
      return;

   string txt = isUplegSwingDirection ? "High" : "Low";
   if(keyLevelIdForLabel > 0)
      txt = StringFormat("%s #%d", txt, keyLevelIdForLabel);

   ObjectSetString(0, chartObjectName, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, isUplegSwingDirection ? clrDodgerBlue : clrOrange);
   ObjectSetInteger(0, chartObjectName, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, chartObjectName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, chartObjectName, OBJPROP_ANCHOR,
                    isUplegSwingDirection ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void DeleteMtfSwingLegChartObjects()
{
   ObjectsDeleteAll(0, PFX_MTF_W1_TR, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_W1_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_D1_TR, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_D1_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_H4_TR, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_H4_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_M15_TR, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_M15_LBL, -1, -1);
}

//+------------------------------------------------------------------+
bool MtfSwingLegDrawEnabled(const ENUM_TIMEFRAMES timeframe)
{
   if(!H4LqChartDrawEnabled())
      return false;
   switch(timeframe)
   {
      case PERIOD_W1:  return InputDrawMtfSwingLegsW1;
      case PERIOD_D1:  return InputDrawMtfSwingLegsD1;
      case PERIOD_H4:  return InputDrawMtfSwingLegsH4;
      case PERIOD_M15: return InputDrawMtfSwingLegsM15;
   }
   return false;
}

//+------------------------------------------------------------------+
color MtfSwingLegLineColor(const ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_W1:  return InputMtfSwingLegColorW1;
      case PERIOD_D1:  return InputMtfSwingLegColorD1;
      case PERIOD_H4:  return InputMtfSwingLegColorH4;
      case PERIOD_M15: return InputMtfSwingLegColorM15;
   }
   return clrSilver;
}

//+------------------------------------------------------------------+
void MtfSwingLegObjectPrefixes(const ENUM_TIMEFRAMES timeframe, string &trendPrefix, string &labelPrefix)
{
   trendPrefix = "";
   labelPrefix = "";
   switch(timeframe)
   {
      case PERIOD_W1:
         trendPrefix = PFX_MTF_W1_TR;
         labelPrefix = PFX_MTF_W1_LBL;
         break;
      case PERIOD_D1:
         trendPrefix = PFX_MTF_D1_TR;
         labelPrefix = PFX_MTF_D1_LBL;
         break;
      case PERIOD_H4:
         trendPrefix = PFX_MTF_H4_TR;
         labelPrefix = PFX_MTF_H4_LBL;
         break;
      case PERIOD_M15:
         trendPrefix = PFX_MTF_M15_TR;
         labelPrefix = PFX_MTF_M15_LBL;
         break;
   }
}

//+------------------------------------------------------------------+
void DrawMtfClosedSwingLegVisual(const Swing &leg, const ENUM_TIMEFRAMES timeframe)
{
   if(!MtfSwingLegDrawEnabled(timeframe) || leg.swingDirection == 0 || leg.legStartTime == 0 || leg.legEndTime == 0)
      return;

   string trendPrefix = "";
   string labelPrefix = "";
   MtfSwingLegObjectPrefixes(timeframe, trendPrefix, labelPrefix);
   if(trendPrefix == "" || labelPrefix == "")
      return;

   const string chartObjectName =
      trendPrefix + IntegerToString((long)leg.legStartTime) + "_" + IntegerToString((long)leg.legEndTime);

   double trendLineStartPrice;
   double trendLineEndPrice;
   if(leg.swingDirection == 1)
   {
      trendLineStartPrice = leg.legLowPrice;
      trendLineEndPrice   = leg.legHighPrice;
   }
   else
   {
      trendLineStartPrice = leg.legHighPrice;
      trendLineEndPrice   = leg.legLowPrice;
   }

   datetime tRightDraw = leg.legEndTime;
   if(tRightDraw <= leg.legStartTime)
      tRightDraw = leg.legStartTime + (datetime)PeriodSeconds(timeframe);

   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

   if(ObjectCreate(0, chartObjectName, OBJ_TREND, 0, leg.legStartTime, trendLineStartPrice,
                   tRightDraw, trendLineEndPrice))
   {
      ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, MtfSwingLegLineColor(timeframe));
      ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }

   const bool isUplegSwingDirection = (leg.swingDirection == 1);
   DrawSwingLegLabel(labelPrefix, leg.legEndTime, trendLineEndPrice, isUplegSwingDirection, 0);
}

//+------------------------------------------------------------------+
string M2SwingCompletedTrendObjectName(const datetime legStartTime, const datetime legEndTime)
{
   return PFX_M2_TREND + IntegerToString((long)legStartTime) + "_" + IntegerToString((long)legEndTime);
}

//+------------------------------------------------------------------+
bool SetM2SwingTrendSegment(const string objectName, const datetime timeStart, const double priceStart,
                            const datetime timeEnd, const double priceEnd, const color lineColor,
                            const bool rayRight)
{
   if(timeStart == 0 || timeEnd == 0)
      return false;

   datetime t1 = timeStart;
   datetime t2 = timeEnd;
   if(t2 <= t1)
      t2 = t1 + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);

   if(ObjectFind(0, objectName) < 0)
   {
      if(!ObjectCreate(0, objectName, OBJ_TREND, 0, t1, priceStart, t2, priceEnd))
         return false;
      ObjectSetInteger(0, objectName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objectName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objectName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, objectName, OBJPROP_RAY_RIGHT, rayRight);
      ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, objectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
   else
   {
      ObjectSetInteger(0, objectName, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, objectName, OBJPROP_PRICE, 0, priceStart);
      ObjectSetInteger(0, objectName, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, objectName, OBJPROP_PRICE, 1, priceEnd);
      ObjectSetInteger(0, objectName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objectName, OBJPROP_RAY_RIGHT, rayRight);
   }
   return true;
}

//+------------------------------------------------------------------+
// plot_swing_h1_m5_copy SwingClose â€” M2 only (no H1 keyLevelId).
//+------------------------------------------------------------------+
void SwingCloseM2Leg(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                     const string chartObjectNamePrefix, const string labelPrefix,
                     const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.keyLevelId = 0;

   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   if(timeframe == InputM2NarrativeTimeframe && H4LqChartDrawEnabled(InputDrawM2SwingLegs))
      ObjectDelete(0, PFX_M2_TREND + "LIVE");

   const string chartObjectName =
      M2SwingCompletedTrendObjectName(swingState.currentSwingLeg.legStartTime,
                                      swingState.currentSwingLeg.legEndTime);

   double trendLineStartPrice;
   double trendLineEndPrice;
   if(swingState.currentSwingLeg.swingDirection == 1)
   {
      trendLineStartPrice = swingState.currentSwingLeg.legLowPrice;
      trendLineEndPrice   = swingState.currentSwingLeg.legHighPrice;
   }
   else
   {
      trendLineStartPrice = swingState.currentSwingLeg.legHighPrice;
      trendLineEndPrice   = swingState.currentSwingLeg.legLowPrice;
   }

   if(H4LqChartDrawEnabled(InputDrawM2SwingLegs))
   {
      SetM2SwingTrendSegment(chartObjectName, swingState.currentSwingLeg.legStartTime, trendLineStartPrice,
                             swingState.currentSwingLeg.legEndTime, trendLineEndPrice, swingLineColor, false);

      const bool isUplegSwingDirection = (swingState.currentSwingLeg.swingDirection == 1);
      DrawSwingLegLabel(labelPrefix, swingState.currentSwingLeg.legEndTime, trendLineEndPrice,
                        isUplegSwingDirection, swingState.currentSwingLeg.keyLevelId);
   }

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
void UpdateM2LiveSwingLegVisualCore(const SwingState &swingState, const double legHighPrice,
                                    const double legLowPrice)
{
   if(!H4LqChartDrawEnabled(InputDrawM2SwingLegs) || swingState.currentSwingLeg.swingDirection == 0)
      return;

   datetime tEnd = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tEnd <= swingState.currentSwingLeg.legStartTime)
      tEnd = swingState.currentSwingLeg.legStartTime + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);

   double trendLineStartPrice;
   double trendLineEndPrice;
   if(swingState.currentSwingLeg.swingDirection == 1)
   {
      trendLineStartPrice = legLowPrice;
      trendLineEndPrice   = legHighPrice;
   }
   else
   {
      trendLineStartPrice = legHighPrice;
      trendLineEndPrice   = legLowPrice;
   }

   SetM2SwingTrendSegment(PFX_M2_TREND + "LIVE", swingState.currentSwingLeg.legStartTime,
                          trendLineStartPrice, tEnd, trendLineEndPrice, InputM2SwingLineColor, false);
}

//+------------------------------------------------------------------+
void UpdateM2LiveSwingLegVisualIf(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe)
{
   if(timeframe != InputM2NarrativeTimeframe)
      return;
   UpdateM2LiveSwingLegVisualCore(swingState, swingState.currentSwingLeg.legHighPrice,
                                  swingState.currentSwingLeg.legLowPrice);
}

//+------------------------------------------------------------------+
void UpdateM2LiveSwingLegVisualOnTick()
{
   if(g_m2Swing.currentSwingLeg.swingDirection == 0)
      return;

   double effHigh = g_m2Swing.currentSwingLeg.legHighPrice;
   double effLow  = g_m2Swing.currentSwingLeg.legLowPrice;
   const double barHigh = iHigh(_Symbol, InputM2NarrativeTimeframe, 0);
   const double barLow  = iLow(_Symbol, InputM2NarrativeTimeframe, 0);
   if(barHigh > effHigh)
      effHigh = barHigh;
   if(barLow < effLow)
      effLow = barLow;

   UpdateM2LiveSwingLegVisualCore(g_m2Swing, effHigh, effLow);
}

//+------------------------------------------------------------------+
//| Realtime segment at priceAnchorLevel â€” close cross vs this flips the M2 leg. |
//+------------------------------------------------------------------+
void UpdateM2SwingAnchorVisualRealtime(const SwingState &swingState)
{
   const string liveName = PFX_M2_ANCHOR + "LIVE";

   if(!H4LqChartDrawEnabled(InputDrawM2SwingAnchorLevel) ||
      swingState.currentSwingLeg.swingDirection == 0 ||
      swingState.priceAnchorLevel <= 0.0)
   {
      ObjectDelete(0, liveName);
      return;
   }

   const datetime tStart = swingState.currentSwingLeg.legStartTime;
   datetime       tEnd   = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tEnd <= tStart)
      tEnd = tStart + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);

   const double anchorPrice = swingState.priceAnchorLevel;

   if(ObjectFind(0, liveName) < 0)
   {
      if(!ObjectCreate(0, liveName, OBJ_TREND, 0, tStart, anchorPrice, tEnd, anchorPrice))
         return;
      ObjectSetInteger(0, liveName, OBJPROP_COLOR, InputM2SwingAnchorColor);
      ObjectSetInteger(0, liveName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, liveName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, liveName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, liveName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, liveName, OBJPROP_BACK, false);
      ObjectSetInteger(0, liveName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, liveName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
   else
   {
      ObjectSetInteger(0, liveName, OBJPROP_TIME, 0, tStart);
      ObjectSetDouble(0, liveName, OBJPROP_PRICE, 0, anchorPrice);
      ObjectSetInteger(0, liveName, OBJPROP_TIME, 1, tEnd);
      ObjectSetDouble(0, liveName, OBJPROP_PRICE, 1, anchorPrice);
      ObjectSetInteger(0, liveName, OBJPROP_COLOR, InputM2SwingAnchorColor);
   }
}

//+------------------------------------------------------------------+
// plot_swing_h1_m5_copy ProcessSwingStepAtShift (M2 timeframe).
//+------------------------------------------------------------------+
void ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh,
                             const color swingLineColor, const string trendPrefix, const string labelPrefix,
                             const bool replayOnly)
{
   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   // Anchor tolerance: M2 = body vs 0.2Ã— prior avg; H4 = wick AND body vs 0.5Ã— prior avg.
   const double lastClosedBarBodyRange = MathAbs(lastClosedBarClose - lastClosedBarOpen);
   const double lastClosedBarWickRange  = lastClosedBarHigh - lastClosedBarLow;

   if(swingState.currentSwingLeg.swingDirection == 0)
   {
      if(candleDirection == 0)
         return;
      SwingStartNew(swingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow, sh);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      if(!replayOnly)
      {
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe);
         UpdateM2SwingAnchorVisualRealtime(swingState);
      }
      return;
   }

   double sumRangeFivePriorBars = 0.0;
   const int barsTotal = iBars(_Symbol, timeframe);
   int       rangeBarCount = 0;
   for(int barShiftIndex = sh + 1; barShiftIndex <= sh + 5; barShiftIndex++)
   {
      if(barShiftIndex >= barsTotal)
         break;
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, barShiftIndex) - iLow(_Symbol, timeframe, barShiftIndex));
      rangeBarCount++;
   }
   const double averageRangeFiveBars = (rangeBarCount > 0) ? sumRangeFivePriorBars / (double)rangeBarCount : 0.0;

   const double anchorDecentMovementMultiplier =
      (timeframe == InputM2NarrativeTimeframe) ? InputM2SwingAnchorMultiplier : 0.2;
   const double minDecentRange = averageRangeFiveBars * anchorDecentMovementMultiplier;
   const bool isDecentMovement =
      (timeframe == InputM2NarrativeTimeframe)
      ? (lastClosedBarBodyRange > minDecentRange)
      : (lastClosedBarWickRange > minDecentRange && lastClosedBarBodyRange > minDecentRange);

   const double anchorForFlipCheck = swingState.priceAnchorLevel;
   int nextSwingDirection = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < anchorForFlipCheck)
      nextSwingDirection = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > anchorForFlipCheck)
      nextSwingDirection = 1;

   if(nextSwingDirection == swingState.currentSwingLeg.swingDirection)
   {
      if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
         swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
      if(!replayOnly)
      {
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe);
         UpdateM2SwingAnchorVisualRealtime(swingState);
      }
   }
   else
   {
      const int closingLegDirection = swingState.currentSwingLeg.swingDirection;

      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

      SwingCloseM2Leg(swingState, timeframe, swingLineColor, trendPrefix, labelPrefix, sh);

      Swing closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
      double newSwingLegHigh = lastClosedBarHigh;
      double newSwingLegLow  = lastClosedBarLow;
      if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
         newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
      else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
         newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

      SwingStartNew(swingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      if(!replayOnly)
      {
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe);
         UpdateM2SwingAnchorVisualRealtime(swingState);
      }
   }
}

//+------------------------------------------------------------------+
void ProcessM2SwingStep()
{
   ProcessSwingStepAtShift(g_m2Swing, InputM2NarrativeTimeframe, 1, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL, false);
}

//+------------------------------------------------------------------+
void SwingCloseH4Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                          const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   const double poolLowPrice  = swingState.currentSwingLeg.legLowPrice;
   const double poolHighPrice = swingState.currentSwingLeg.legHighPrice;
   const bool   isSupplyPool  = (swingState.currentSwingLeg.swingDirection == 1);
   PushLiquidityPoolFromClosedSwing(poolLowPrice, poolHighPrice, isSupplyPool);

   if(lastClosedBarShift == 1)
      DrawMtfClosedSwingLegVisual(swingState.currentSwingLeg, timeframe);

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
void SwingCloseH4ToHistory(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                            const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   if(lastClosedBarShift == 1)
      DrawMtfClosedSwingLegVisual(swingState.currentSwingLeg, timeframe);

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}


#endif // H4_LQ_V3_M2SWING
