//+------------------------------------------------------------------+
//| ChartHud.mqh
//| HUD and bias display
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_CHARTHUD
#define H4_LQ_V3_CHARTHUD

void RefreshLiquidityHuntHud()
{
   if(!H4LqChartDrawEnabled(InputShowLiquidityHuntHud))
   {
      ObjectDelete(0, LQ_OBJ_HUNT_HUD);
      return;
   }
   if(ObjectFind(0, LQ_OBJ_HUNT_HUD) < 0)
   {
      if(!ObjectCreate(0, LQ_OBJ_HUNT_HUD, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_XDISTANCE, 6);
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_YDISTANCE, 18);
      ObjectSetString(0, LQ_OBJ_HUNT_HUD, OBJPROP_FONT, "Tahoma");
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_HIDDEN, false);
   }
   const string txt = InputEnableEngulfHuntAfterH4Breach ? "v3: engulf scan ON" : "v3: engulf scan OFF";
   ObjectSetString(0, LQ_OBJ_HUNT_HUD, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_COLOR,
                    InputEnableEngulfHuntAfterH4Breach ? clrLime : clrSilver);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
string H4TradeDirectionBiasText(const int bias)
{
   if(bias == 1)
      return "bull";
   if(bias == -1)
      return "bear";
   return "neutral";
}

//+------------------------------------------------------------------+
void LogH4TradeDirectionBiasIfChanged()
{
   if(!H4LqLoggingEnabled() || !InputEnableH4BosTradeDirectionBias)
      return;

   const int bias = GetH4TradeDirectionBias();
   if(!g_h4EffectiveBiasLogReady)
   {
      g_h4LastLoggedEffectiveBias = bias;
      g_h4EffectiveBiasLogReady   = true;
      return;
   }

   if(bias == g_h4LastLoggedEffectiveBias)
      return;

   MTFSwingTracker h4Tracker;
   string bosDetail = "no BOS on tracker";
   if(SMCGetMtfSwingTracker(PERIOD_H4, h4Tracker) && h4Tracker.lastBosBarOpenTime > 0)
   {
      bosDetail = StringFormat("%s BOS bar=%s lvl=%.5f",
                               h4Tracker.lastBosDirection == 1 ? "bull" : "bear",
                               TimeToString(h4Tracker.lastBosBarOpenTime, TIME_DATE | TIME_MINUTES),
                               h4Tracker.lastBosLevel);
   }

   LogHuntEvent("H4_BIAS",
                StringFormat("%s -> %s (SMC H4 professional bias; %s)",
                             H4TradeDirectionBiasText(g_h4LastLoggedEffectiveBias),
                             H4TradeDirectionBiasText(bias),
                             bosDetail));
   g_h4LastLoggedEffectiveBias = bias;
}

int GetH4TradeDirectionBias()
{
   if(!InputEnableH4BosTradeDirectionBias)
      return 0;

   return GetProfessionalBias(PERIOD_H4);
}

//+------------------------------------------------------------------+
bool FvgTradeAllowedByH4BosBias(const bool isBullishFairValueGap, string &outBlockReason)
{
   outBlockReason = "";
   if(!InputEnableH4BosTradeDirectionBias)
      return true;

   const int bias = GetH4TradeDirectionBias();
   if(bias == 0)
      return true;

   const int tradeDir = isBullishFairValueGap ? 1 : -1;
   if(tradeDir != bias)
   {
      outBlockReason = StringFormat("H4 BOS overall bias %s blocks %s FVG",
                                    bias == 1 ? "bull" : "bear",
                                    isBullishFairValueGap ? "bull" : "bear");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void DeleteMtfDirectionHudObjects()
{
   ObjectDelete(0, LQ_OBJ_MTF_BIAS_HUD_W1);
   ObjectDelete(0, LQ_OBJ_MTF_BIAS_HUD_D1);
   ObjectDelete(0, LQ_OBJ_MTF_BIAS_HUD_H4);
   ObjectDelete(0, LQ_OBJ_MTF_BIAS_HUD_M15);
}

//+------------------------------------------------------------------+
void RefreshMtfDirectionHudRow(const string objectName, const string tfLabel,
                                const ENUM_TIMEFRAMES timeframe, const int rowIndex)
{
   const int yDistance = 18 + rowIndex * 18;

   if(ObjectFind(0, objectName) < 0)
   {
      if(!ObjectCreate(0, objectName, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, objectName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, objectName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, 8);
      ObjectSetString(0, objectName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
   }

   ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, yDistance);

   const int   bias  = GetProfessionalBias(timeframe);
   string      arrow = ShortToString(0x2014);
   color       col   = clrSilver;
   if(bias == BIAS_BULLISH)
   {
      arrow = ShortToString(0x2191);
      col   = clrLime;
   }
   else if(bias == BIAS_BEARISH)
   {
      arrow = ShortToString(0x2193);
      col   = clrTomato;
   }

   ObjectSetString(0, objectName, OBJPROP_TEXT, tfLabel + " " + arrow);
   ObjectSetInteger(0, objectName, OBJPROP_COLOR, col);
   ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 13);
}

//+------------------------------------------------------------------+
void RefreshMtfDirectionHud()
{
   if(!H4LqChartDrawEnabled(InputShowMtfDirectionHud))
   {
      DeleteMtfDirectionHudObjects();
      return;
   }

   RefreshMtfDirectionHudRow(LQ_OBJ_MTF_BIAS_HUD_W1,  "W1",  PERIOD_W1,  0);
   RefreshMtfDirectionHudRow(LQ_OBJ_MTF_BIAS_HUD_D1,  "D1",  PERIOD_D1,  1);
   RefreshMtfDirectionHudRow(LQ_OBJ_MTF_BIAS_HUD_H4,  "H4",  PERIOD_H4,  2);
   RefreshMtfDirectionHudRow(LQ_OBJ_MTF_BIAS_HUD_M15, "M15", PERIOD_M15, 3);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForFairValueGapFilterM2()
{
   return ReferenceChartHeightForM2BarCount(InputChartRangeBarCount);
}


#endif // H4_LQ_V3_CHARTHUD
