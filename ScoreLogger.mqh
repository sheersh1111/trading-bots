//+------------------------------------------------------------------+
//| ScoreLogger.mqh - setup_zone_types.json write + manual thresholds |
//| v2.8: deinit verify dump gated by InputVerifyPermutationScores (read-mode) |
//| v2.7: log Setups/PositiveScores/TheoreticalMax + P0..P100 (matches optimize_score_adaptive.exe for verification) |
//| v2.6: merge ScoreLogApplyThresholdPercentileValues into ScoreLogApplyThresholdPercentiles |
//| v2.5: drop ScoreAdaptiveXlsx.mqh — thresholds computed in-process only |
//| v2.4: OnInit computes P0..P100 in-process from setup_zone_types.json (tester-safe, no .exe/xlsx) |
//| v2.3: OnInit runs optimizer script + loads percentile thresholds from xlsx |
//| v2.2: read-mode deinit replay → setup_zone_scores.json verification |
//+------------------------------------------------------------------+

#define SCORE_LOG_SETUP_ZONES_JSON  "setup_zone_types.json"
#define SCORE_LOG_VERIFY_SCORES_JSON "setup_zone_scores.json"

double g_scoreThreshP0      = 0.0;
double g_scoreThreshP10     = 0.0;
double g_scoreThreshP20     = 0.0;
double g_scoreThreshP30     = 0.0;
double g_scoreThreshP80     = 0.0;
double g_scoreThreshP90     = 0.0;
double g_scoreThreshP100    = 0.0;
bool   g_scoreThresholdsLoaded = false;

//+------------------------------------------------------------------+
void ScoreLogClearThresholdGlobals()
{
   g_scoreThresholdsLoaded = false;
   g_scoreThreshP0 = g_scoreThreshP10 = g_scoreThreshP20 = g_scoreThreshP30 = 0.0;
   g_scoreThreshP80 = g_scoreThreshP90 = g_scoreThreshP100 = 0.0;
}

struct ScoreLogSetupJsonRecord
{
   string             symbol;
   bool               bull;
   string             barText;
   datetime           barTime;
   double             setupLow;
   double             setupHigh;
   ENUM_SMC_ZONE_TYPE zoneTypes[];
   int                biasW1;
   int                biasD1;
   int                biasH4;
   int                biasM15;
};

ScoreLogSetupJsonRecord g_scoreLogSetupRecords[];

int GetProfessionalBias(const ENUM_TIMEFRAMES timeframe);

//+------------------------------------------------------------------+
string ScoreLogFormatMtfBiasJson(const int biasW1, const int biasD1,
                                  const int biasH4, const int biasM15)
{
   return StringFormat("{\"W1\":%d,\"D1\":%d,\"H4\":%d,\"M15\":%d}",
                       biasW1, biasD1, biasH4, biasM15);
}

//+------------------------------------------------------------------+
void ScoreLogResetBuffer()
{
   ArrayResize(g_scoreLogSetupRecords, 0);
}

//+------------------------------------------------------------------+
string ScoreLogBuildZoneTypeNamesJsonArray(const ENUM_SMC_ZONE_TYPE &zoneTypes[])
{
   const int typeCount = ArraySize(zoneTypes);
   string json = "[";
   for(int i = 0; i < typeCount; i++)
   {
      if(i > 0)
         json += ",";
      json += "\"" + SMCZoneTypeToLogName(zoneTypes[i]) + "\"";
   }
   json += "]";
   return json;
}

//+------------------------------------------------------------------+
void ScoreLogCopyZoneTypes(const ENUM_SMC_ZONE_TYPE &srcTypes[], ENUM_SMC_ZONE_TYPE &dstTypes[])
{
   const int typeCount = ArraySize(srcTypes);
   ArrayResize(dstTypes, typeCount);
   for(int i = 0; i < typeCount; i++)
      dstTypes[i] = srcTypes[i];
}

//+------------------------------------------------------------------+
string ScoreLogBuildSetupJsonObject(const ScoreLogSetupJsonRecord &record)
{
   const string zonesJson = ScoreLogBuildZoneTypeNamesJsonArray(record.zoneTypes);
   const string biasJson  = ScoreLogFormatMtfBiasJson(record.biasW1, record.biasD1,
                                                       record.biasH4, record.biasM15);
   return StringFormat(
      "{\"symbol\":\"%s\",\"bull\":%s,\"bar\":\"%s\",\"setupLow\":%.5f,\"setupHigh\":%.5f,\"zoneTypes\":%s,\"mtfBias\":%s}",
      record.symbol,
      record.bull ? "true" : "false",
      record.barText,
      record.setupLow,
      record.setupHigh,
      zonesJson,
      biasJson);
}

//+------------------------------------------------------------------+
void ScoreLogFlushSetupJsonToFile()
{
   if(!InputScoreLogWriteCsv)
      return;

   const int entryCount = ArraySize(g_scoreLogSetupRecords);
   if(entryCount <= 0)
      return;

   const int writeFlags = FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_WRITE;
   int fileHandle = FileOpen(SCORE_LOG_SETUP_ZONES_JSON, writeFlags);
   if(fileHandle == INVALID_HANDLE)
      return;

   FileWriteString(fileHandle, "[\n");
   for(int i = 0; i < entryCount; i++)
   {
      const string entryJson = ScoreLogBuildSetupJsonObject(g_scoreLogSetupRecords[i]);
      FileWriteString(fileHandle, "  " + entryJson);
      if(i < entryCount - 1)
         FileWriteString(fileHandle, ",\n");
      else
         FileWriteString(fileHandle, "\n");
   }
   FileWriteString(fileHandle, "]\n");
   FileClose(fileHandle);
}

//+------------------------------------------------------------------+
int LogSetupZoneTypesJsonEntry(const bool isBullishTrade,
                                const ENUM_SMC_ZONE_TYPE &zoneTypes[],
                                const double setupLow,
                                const double setupHigh,
                                const datetime setupBarOpenTime = 0)
{
   if(!InputScoreLogWriteCsv)
      return -1;

   const datetime barTime = (setupBarOpenTime != 0)
                            ? setupBarOpenTime
                            : iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   const string barText   = (barTime != 0)
                            ? TimeToString(barTime, TIME_DATE | TIME_MINUTES)
                            : "";

   ScoreLogSetupJsonRecord record;
   record.symbol          = _Symbol;
   record.bull            = isBullishTrade;
   record.barText         = barText;
   record.barTime         = barTime;
   record.setupLow        = setupLow;
   record.setupHigh       = setupHigh;
   record.biasW1          = GetProfessionalBias(PERIOD_W1);
   record.biasD1          = GetProfessionalBias(PERIOD_D1);
   record.biasH4          = GetProfessionalBias(PERIOD_H4);
   record.biasM15         = GetProfessionalBias(PERIOD_M15);
   ScoreLogCopyZoneTypes(zoneTypes, record.zoneTypes);

   const int idx = ArraySize(g_scoreLogSetupRecords);
   ArrayResize(g_scoreLogSetupRecords, idx + 1);
   g_scoreLogSetupRecords[idx] = record;

   ScoreLogFlushSetupJsonToFile();
   return idx;
}

//+------------------------------------------------------------------+
void FlushSetupZoneTypesJsonToFile()
{
   ScoreLogFlushSetupJsonToFile();
}

//+------------------------------------------------------------------+
int ScoreLogOpenSetupJsonForRead()
{
   const int readFlags = FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   int fileHandle = FileOpen(SCORE_LOG_SETUP_ZONES_JSON, readFlags);
   if(fileHandle != INVALID_HANDLE)
      return fileHandle;
   return FileOpen(SCORE_LOG_SETUP_ZONES_JSON, readFlags | FILE_COMMON);
}

//+------------------------------------------------------------------+
string ScoreLogParseJsonStringField(const string line, const string key)
{
   const string pattern = "\"" + key + "\":\"";
   const int pos = StringFind(line, pattern);
   if(pos < 0)
      return "";

   const int start = pos + StringLen(pattern);
   const int endPos = StringFind(line, "\"", start);
   if(endPos < 0)
      return "";
   return StringSubstr(line, start, endPos - start);
}

//+------------------------------------------------------------------+
bool ScoreLogParseJsonBoolField(const string line, const string key)
{
   const string pattern = "\"" + key + "\":";
   const int pos = StringFind(line, pattern);
   if(pos < 0)
      return false;

   const string tail = StringSubstr(line, pos + StringLen(pattern), 5);
   return (StringFind(tail, "true") == 0);
}

//+------------------------------------------------------------------+
int ScoreLogParseJsonBiasField(const string line, const string key)
{
   const string pattern = "\"" + key + "\":";
   const int pos = StringFind(line, pattern);
   if(pos < 0)
      return 0;

   int endPos = pos + StringLen(pattern);
   const int lineLen = StringLen(line);
   while(endPos < lineLen)
   {
      const ushort ch = StringGetCharacter(line, endPos);
      if(ch == ',' || ch == '}')
         break;
      endPos++;
   }
   return (int)StringToInteger(StringSubstr(line, pos + StringLen(pattern), endPos - pos - StringLen(pattern)));
}

//+------------------------------------------------------------------+
void ScoreLogParseZoneTypesFromLine(const string line, ENUM_SMC_ZONE_TYPE &outTypes[])
{
   ArrayResize(outTypes, 0);

   int searchPos = 0;
   while(true)
   {
      const int zoneStart = StringFind(line, "ZONE_", searchPos);
      if(zoneStart < 0)
         break;

      const int zoneEnd = StringFind(line, "\"", zoneStart);
      if(zoneEnd < 0)
         break;

      const string zoneName = StringSubstr(line, zoneStart, zoneEnd - zoneStart);
      ENUM_SMC_ZONE_TYPE zoneType;
      if(SMCZoneTypeFromLogName(zoneName, zoneType))
         AppendUniqueSetupZoneType(zoneType, outTypes);

      searchPos = zoneEnd + 1;
   }
}

//+------------------------------------------------------------------+
void ScoreLogWriteVerifyScoresFromSetupJson()
{
   if(InputScoreLogWriteCsv || !InputVerifyPermutationScores)
      return;

   const int readHandle = ScoreLogOpenSetupJsonForRead();
   if(readHandle == INVALID_HANDLE)
   {
      Print("Score verify: ", SCORE_LOG_SETUP_ZONES_JSON,
            " not found — copy it to MQL5/Files before running verification.");
      return;
   }

   const int writeFlags = FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_WRITE;
   int writeHandle = FileOpen(SCORE_LOG_VERIFY_SCORES_JSON, writeFlags);
   if(writeHandle == INVALID_HANDLE)
      writeHandle = FileOpen(SCORE_LOG_VERIFY_SCORES_JSON, writeFlags | FILE_COMMON);
   if(writeHandle == INVALID_HANDLE)
   {
      FileClose(readHandle);
      Print("Score verify: cannot create ", SCORE_LOG_VERIFY_SCORES_JSON);
      return;
   }

   FileWriteString(writeHandle, "[\n");

   int index = 0;
   bool wroteAny = false;
   while(!FileIsEnding(readHandle))
   {
      const string line = FileReadString(readHandle);
      if(StringFind(line, "\"symbol\"") < 0)
         continue;

      const string symbol = ScoreLogParseJsonStringField(line, "symbol");
      const string barText = ScoreLogParseJsonStringField(line, "bar");
      const bool bull = ScoreLogParseJsonBoolField(line, "bull");
      const int biasW1 = ScoreLogParseJsonBiasField(line, "W1");
      const int biasD1 = ScoreLogParseJsonBiasField(line, "D1");
      const int biasH4 = ScoreLogParseJsonBiasField(line, "H4");
      const int biasM15 = ScoreLogParseJsonBiasField(line, "M15");

      ENUM_SMC_ZONE_TYPE zoneTypes[];
      ScoreLogParseZoneTypesFromLine(line, zoneTypes);

      const double score = CalculateReplayTradeScore(bull, zoneTypes, biasW1, biasD1, biasH4, biasM15);
      const string entryJson = StringFormat(
         "  {\"index\":%d,\"symbol\":\"%s\",\"bull\":%s,\"bar\":\"%s\",\"score\":%.6f}",
         index,
         symbol,
         bull ? "true" : "false",
         barText,
         score);

      if(wroteAny)
         FileWriteString(writeHandle, ",\n");
      FileWriteString(writeHandle, entryJson);
      wroteAny = true;
      index++;
   }

   FileWriteString(writeHandle, "\n]\n");
   FileClose(writeHandle);
   FileClose(readHandle);

   PrintFormat("Score verify: wrote %d replay scores to %s", index, SCORE_LOG_VERIFY_SCORES_JSON);
}

//+------------------------------------------------------------------+
double ScoreLogPercentileFromSorted(const double &sorted[], const double percentile)
{
   const int count = ArraySize(sorted);
   if(count <= 0)
      return 0.0;
   if(count == 1)
      return sorted[0];

   const double rank = (count - 1) * (percentile / 100.0);
   const int low = (int)MathFloor(rank);
   const int high = (int)MathCeil(rank);
   if(low == high)
      return sorted[low];

   const double weight = rank - (double)low;
   return sorted[low] * (1.0 - weight) + sorted[high] * weight;
}

//+------------------------------------------------------------------+
bool ScoreLogApplyThresholdPercentiles(const double &positiveScores[])
{
   double sorted[];
   ArrayResize(sorted, ArraySize(positiveScores));
   ArrayCopy(sorted, positiveScores);
   ArraySort(sorted);

   g_scoreThreshP0   = ScoreLogPercentileFromSorted(sorted, 0.0);
   g_scoreThreshP10  = ScoreLogPercentileFromSorted(sorted, 10.0);
   g_scoreThreshP20  = ScoreLogPercentileFromSorted(sorted, 20.0);
   g_scoreThreshP30  = ScoreLogPercentileFromSorted(sorted, 30.0);
   g_scoreThreshP80  = ScoreLogPercentileFromSorted(sorted, 80.0);
   g_scoreThreshP90  = ScoreLogPercentileFromSorted(sorted, 90.0);
   g_scoreThreshP100 = ScoreLogPercentileFromSorted(sorted, 100.0);
   return (g_scoreThreshP80 > 0.0 || g_scoreThreshP100 > 0.0);
}

//+------------------------------------------------------------------+
bool InitScoreThresholdsFromSetupZoneJson()
{
   const int fileHandle = ScoreLogOpenSetupJsonForRead();
   if(fileHandle == INVALID_HANDLE)
   {
      Print("Score thresholds: ", SCORE_LOG_SETUP_ZONES_JSON,
            " not found in MQL5/Files or Common/Files.");
      return false;
   }

   const uint startedMs = GetTickCount();

   // Mirror optimize_score_adaptive.cpp: score every setup, keep the pool of
   // strictly-positive scores, then derive P0..P100 via linear interpolation.
   double positiveScores[];
   ArrayResize(positiveScores, 0, 8192); // reserve capacity to avoid O(n^2) reallocation
   int positiveCount = 0;
   int totalSetups = 0;

   while(!FileIsEnding(fileHandle))
   {
      const string line = FileReadString(fileHandle);
      if(StringFind(line, "\"symbol\"") < 0)
         continue;

      totalSetups++;

      const bool bull = ScoreLogParseJsonBoolField(line, "bull");
      const int biasW1 = ScoreLogParseJsonBiasField(line, "W1");
      const int biasD1 = ScoreLogParseJsonBiasField(line, "D1");
      const int biasH4 = ScoreLogParseJsonBiasField(line, "H4");
      const int biasM15 = ScoreLogParseJsonBiasField(line, "M15");

      ENUM_SMC_ZONE_TYPE zoneTypes[];
      ScoreLogParseZoneTypesFromLine(line, zoneTypes);

      const double score = CalculateReplayTradeScore(bull, zoneTypes, biasW1, biasD1, biasH4, biasM15);
      if(score <= 0.0)
         continue;

      if(positiveCount >= ArraySize(positiveScores))
         ArrayResize(positiveScores, ArraySize(positiveScores) + 8192, 8192);
      positiveScores[positiveCount++] = score;
   }
   FileClose(fileHandle);

   if(positiveCount <= 0)
   {
      Print("Score thresholds: no positive replay scores in ", SCORE_LOG_SETUP_ZONES_JSON,
            " (", totalSetups, " setups parsed).");
      return false;
   }

   ArrayResize(positiveScores, positiveCount);
   g_scoreThresholdsLoaded = ScoreLogApplyThresholdPercentiles(positiveScores);
   if(g_scoreThresholdsLoaded)
   {
      // Same fields/format as optimize_score_adaptive.exe for direct comparison.
      PrintFormat("Score thresholds: Setups=%d PositiveScores=%d TheoreticalMax=%.0f (in %u ms)",
                  totalSetups, positiveCount, GetMaxPossibleScore(),
                  (uint)(GetTickCount() - startedMs));
      PrintFormat("Score thresholds: P0=%.2f P10=%.2f P20=%.2f P30=%.2f P80=%.2f P90=%.2f P100=%.2f",
                  g_scoreThreshP0, g_scoreThreshP10, g_scoreThreshP20, g_scoreThreshP30,
                  g_scoreThreshP80, g_scoreThreshP90, g_scoreThreshP100);
   }
   return g_scoreThresholdsLoaded;
}

//+------------------------------------------------------------------+
void ScoreLogPrintActiveThresholds()
{
   PrintFormat("Score thresholds: gate %s=%.2f (score >) | risk denom %s=%.2f",
               EnumToString(InputMinScorePercentile), GetMinScoreThreshold(),
               EnumToString(InputScoreDenominatorPercentile), GetRiskNormalizationScore());
}

//+------------------------------------------------------------------+
bool InitScoreThresholds()
{
   if(InputScoreLogWriteCsv)
      return false;

   ScoreLogClearThresholdGlobals();

   // Primary (tester-safe): compute P0..P100 in-process directly from
   // setup_zone_types.json using the current weight inputs. No external .exe
   // (ShellExecute is unreliable inside Strategy Tester agents) and no CSV/xlsx
   // row-matching, so every optimization pass gets its own correct percentiles.
   if(InitScoreThresholdsFromSetupZoneJson())
   {
      g_scoreThresholdsLoaded = true;
      ScoreLogPrintActiveThresholds();
      return true;
   }

   Print("Score thresholds: in-process compute from ", SCORE_LOG_SETUP_ZONES_JSON, " failed.");
   return false;
}

//+------------------------------------------------------------------+
double GetMinScoreThreshold()
{
   if(InputScoreLogWriteCsv)
      return 0.0;
   if(!g_scoreThresholdsLoaded)
      return 0.0;

   switch((int)InputMinScorePercentile)
   {
      case SCORE_PERCENTILE_MIN_P0:  return g_scoreThreshP0;
      case SCORE_PERCENTILE_MIN_P10: return g_scoreThreshP10;
      case SCORE_PERCENTILE_MIN_P20: return g_scoreThreshP20;
      case SCORE_PERCENTILE_MIN_P30: return g_scoreThreshP30;
   }
   return g_scoreThreshP30;
}

//+------------------------------------------------------------------+
bool ScoreLogThresholdsReady()
{
   if(InputScoreLogWriteCsv)
      return true;
   return g_scoreThresholdsLoaded;
}

//+------------------------------------------------------------------+
double GetRiskNormalizationScore()
{
   if(InputScoreLogWriteCsv)
      return GetMaxPossibleScore();
   if(!g_scoreThresholdsLoaded)
      return GetMaxPossibleScore();

   switch((int)InputScoreDenominatorPercentile)
   {
      case SCORE_PERCENTILE_DENOM_P80:  return g_scoreThreshP80;
      case SCORE_PERCENTILE_DENOM_P90:  return g_scoreThreshP90;
      case SCORE_PERCENTILE_DENOM_P100: return g_scoreThreshP100;
   }
   return g_scoreThreshP80;
}
