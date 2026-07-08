//+------------------------------------------------------------------+
//| ScoreLogger.mqh - setup_zone_types.json write + manual thresholds |
//| v2.9: write mode also emits setup_zone_types.bin (weight-slot mask); read mode loads bin + computes only the 2 active percentiles |
//| v2.8: deinit verify dump gated by InputVerifyPermutationScores (read-mode) |
//| v2.7: log Setups/PositiveScores/TheoreticalMax + P0..P100 (matches optimize_score_adaptive.exe for verification) |
//| v2.6: merge ScoreLogApplyThresholdPercentileValues into ScoreLogApplyThresholdPercentiles |
//| v2.5: drop ScoreAdaptiveXlsx.mqh — thresholds computed in-process only |
//| v2.4: OnInit computes P0..P100 in-process from setup_zone_types.json (tester-safe, no .exe/xlsx) |
//| v2.3: OnInit runs optimizer script + loads percentile thresholds from xlsx |
//| v2.2: read-mode deinit replay → setup_zone_scores.json verification |
//+------------------------------------------------------------------+

#define SCORE_LOG_SETUP_ZONES_JSON  "setup_zone_types.json"
#define SCORE_LOG_SETUP_ZONES_BIN   "setup_zone_types.bin"
#define SCORE_LOG_VERIFY_SCORES_JSON "setup_zone_scores.json"

// Binary replay file: header {magic,version,count} + packed POD records.
// MQL5-only (the C++ verifier reads JSON); no cross-language byte layout needed.
#define SCORE_BIN_MAGIC    0x5A4C4231  // 'ZLB1'
#define SCORE_BIN_VERSION  1

// Weight-slot mask + bias record. No strings → fast bulk FileReadArray/FileWriteArray.
struct ScoreBinSetupRecord
{
   uchar zoneMask;   // bits 0..7 = weight slots (GetZoneWeightSlotIndex)
   uchar bull;       // 0/1
   char  biasW1;     // -1/0/1
   char  biasD1;
   char  biasH4;
   char  biasM15;
};

// Read mode stores only the two percentiles the inputs actually select.
double g_scoreActiveMinThreshold = 0.0;  // value at InputMinScorePercentile (P0/P10/P20/P30)
double g_scoreActiveDenomScore   = 0.0;  // value at InputScoreDenominatorPercentile (P80/P90/P100)
bool   g_scoreThresholdsLoaded   = false;

//+------------------------------------------------------------------+
void ScoreLogClearThresholdGlobals()
{
   g_scoreThresholdsLoaded  = false;
   g_scoreActiveMinThreshold = 0.0;
   g_scoreActiveDenomScore   = 0.0;
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
//| Collapse zone types → weight-slot bitmask (each slot counts once). |
//+------------------------------------------------------------------+
uchar ScoreLogBuildZoneMaskFromTypes(const ENUM_SMC_ZONE_TYPE &zoneTypes[])
{
   uchar mask = 0;
   bool used[SMC_ZONE_WEIGHT_SLOT_COUNT];
   ArrayInitialize(used, false);

   const int typeCount = ArraySize(zoneTypes);
   for(int i = 0; i < typeCount; i++)
   {
      const int slot = GetZoneWeightSlotIndex(zoneTypes[i]);
      if(slot < 0 || slot >= SMC_ZONE_WEIGHT_SLOT_COUNT || used[slot])
         continue;
      used[slot] = true;
      mask |= (uchar)(1 << slot);
   }
   return mask;
}

//+------------------------------------------------------------------+
//| Write setup_zone_types.bin from the accumulated write-mode buffer. |
//+------------------------------------------------------------------+
void ScoreLogFlushSetupBinToFile()
{
   if(!InputScoreLogWriteCsv)
      return;

   const int entryCount = ArraySize(g_scoreLogSetupRecords);
   if(entryCount <= 0)
      return;

   ScoreBinSetupRecord recs[];
   ArrayResize(recs, entryCount);
   for(int i = 0; i < entryCount; i++)
   {
      recs[i].zoneMask = ScoreLogBuildZoneMaskFromTypes(g_scoreLogSetupRecords[i].zoneTypes);
      recs[i].bull     = (uchar)(g_scoreLogSetupRecords[i].bull ? 1 : 0);
      recs[i].biasW1   = (char)g_scoreLogSetupRecords[i].biasW1;
      recs[i].biasD1   = (char)g_scoreLogSetupRecords[i].biasD1;
      recs[i].biasH4   = (char)g_scoreLogSetupRecords[i].biasH4;
      recs[i].biasM15  = (char)g_scoreLogSetupRecords[i].biasM15;
   }

   const int writeFlags = FILE_WRITE | FILE_BIN | FILE_SHARE_WRITE;
   int fileHandle = FileOpen(SCORE_LOG_SETUP_ZONES_BIN, writeFlags);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("Score bin: cannot create ", SCORE_LOG_SETUP_ZONES_BIN);
      return;
   }

   FileWriteInteger(fileHandle, SCORE_BIN_MAGIC,   INT_VALUE);
   FileWriteInteger(fileHandle, SCORE_BIN_VERSION, INT_VALUE);
   FileWriteInteger(fileHandle, entryCount,        INT_VALUE);
   FileWriteArray(fileHandle, recs, 0, entryCount);
   FileClose(fileHandle);
   PrintFormat("Score bin: wrote %d setups to %s", entryCount, SCORE_LOG_SETUP_ZONES_BIN);
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
   ScoreLogFlushSetupJsonToFile();  // JSON: consumed by optimize_score_adaptive verifier
   ScoreLogFlushSetupBinToFile();   // BIN: consumed by read-mode InitScoreThresholds
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
//| Sort positives and keep only the two percentiles the inputs use.  |
//+------------------------------------------------------------------+
bool ScoreLogApplyActiveThresholds(double &positiveScores[], const int positiveCount,
                                    const int totalSetups, const uint startedMs,
                                    const string sourceLabel)
{
   if(positiveCount <= 0)
   {
      Print("Score thresholds [", sourceLabel, "]: no positive scores (",
            totalSetups, " setups parsed).");
      return false;
   }

   ArrayResize(positiveScores, positiveCount);
   ArraySort(positiveScores);

   // Enum underlying values ARE the percentiles: P0/P10/P20/P30 and P80/P90/P100.
   const double minPct   = (double)((int)InputMinScorePercentile);
   const double denomPct = (double)((int)InputScoreDenominatorPercentile);
   g_scoreActiveMinThreshold = ScoreLogPercentileFromSorted(positiveScores, minPct);
   g_scoreActiveDenomScore   = ScoreLogPercentileFromSorted(positiveScores, denomPct);

   const bool ok = (g_scoreActiveDenomScore > 0.0);
   if(ok)
   {
      PrintFormat("Score thresholds [%s]: Setups=%d PositiveScores=%d TheoreticalMax=%.0f (in %u ms)",
                  sourceLabel, totalSetups, positiveCount, GetMaxPossibleScore(),
                  (uint)(GetTickCount() - startedMs));
      PrintFormat("Score thresholds [%s]: gate P%d=%.2f (score >) | risk denom P%d=%.2f",
                  sourceLabel, (int)InputMinScorePercentile, g_scoreActiveMinThreshold,
                  (int)InputScoreDenominatorPercentile, g_scoreActiveDenomScore);
   }
   return ok;
}

//+------------------------------------------------------------------+
//| Read setup_zone_types.bin (header-validated) into a record array. |
//+------------------------------------------------------------------+
bool ScoreLogLoadSetupBin(ScoreBinSetupRecord &recs[], int &outCount)
{
   outCount = 0;

   const int readFlags = FILE_READ | FILE_BIN | FILE_SHARE_READ;
   int fileHandle = FileOpen(SCORE_LOG_SETUP_ZONES_BIN, readFlags);
   if(fileHandle == INVALID_HANDLE)
      fileHandle = FileOpen(SCORE_LOG_SETUP_ZONES_BIN, readFlags | FILE_COMMON);
   if(fileHandle == INVALID_HANDLE)
      return false;

   const int magic = FileReadInteger(fileHandle, INT_VALUE);
   const int ver   = FileReadInteger(fileHandle, INT_VALUE);
   const int count = FileReadInteger(fileHandle, INT_VALUE);
   if(magic != SCORE_BIN_MAGIC || ver != SCORE_BIN_VERSION || count <= 0)
   {
      FileClose(fileHandle);
      Print("Score bin: header invalid/empty in ", SCORE_LOG_SETUP_ZONES_BIN);
      return false;
   }

   ArrayResize(recs, count);
   const int readCount = (int)FileReadArray(fileHandle, recs, 0, count);
   FileClose(fileHandle);
   if(readCount != count)
   {
      Print("Score bin: expected ", count, " records, read ", readCount);
      return false;
   }
   outCount = count;
   return true;
}

//+------------------------------------------------------------------+
//| Map a weight slot index → its current input weight.               |
//+------------------------------------------------------------------+
int ScoreLogZoneWeightBySlot(const int slot)
{
   switch(slot)
   {
      case 0: return InputWeight_WeeklyFVG;
      case 1: return InputWeight_DailyFVG;
      case 2: return InputWeight_H4FVG;
      case 3: return InputWeight_M15FVG;
      case 4: return InputWeight_W1_HighLowZones;
      case 5: return InputWeight_D1_HighLowZones;
      case 6: return InputWeight_H4_HighLowZones;
      case 7: return InputWeight_M15_HighLowZones;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Score a bin record with the current weight inputs (no strings).   |
//+------------------------------------------------------------------+
double ScoreLogScoreBinRecord(const ScoreBinSetupRecord &r)
{
   double score = 0.0;
   for(int slot = 0; slot < SMC_ZONE_WEIGHT_SLOT_COUNT; slot++)
   {
      if((r.zoneMask & (1 << slot)) != 0)
         score += (double)ScoreLogZoneWeightBySlot(slot);
   }

   const int tradeDir = (r.bull != 0 ? 1 : -1);
   score += SMCAlignmentContribution((int)r.biasW1,  InputWeight_W1_BOS,  tradeDir);
   score += SMCAlignmentContribution((int)r.biasD1,  InputWeight_D1_BOS,  tradeDir);
   score += SMCAlignmentContribution((int)r.biasH4,  InputWeight_H4_BOS,  tradeDir);
   score += SMCAlignmentContribution((int)r.biasM15, InputWeight_M15_BOS, tradeDir);
   return score;
}

//+------------------------------------------------------------------+
//| Primary read path: load bin, score every record, keep 2 pctiles. |
//+------------------------------------------------------------------+
bool InitScoreThresholdsFromSetupBin()
{
   ScoreBinSetupRecord recs[];
   int count = 0;
   if(!ScoreLogLoadSetupBin(recs, count))
      return false;

   const uint startedMs = GetTickCount();

   double positiveScores[];
   ArrayResize(positiveScores, count);
   int positiveCount = 0;
   for(int i = 0; i < count; i++)
   {
      const double score = ScoreLogScoreBinRecord(recs[i]);
      if(score > 0.0)
         positiveScores[positiveCount++] = score;
   }

   return ScoreLogApplyActiveThresholds(positiveScores, positiveCount, count, startedMs, "bin");
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

   return ScoreLogApplyActiveThresholds(positiveScores, positiveCount, totalSetups, startedMs, "json");
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

   // Primary (fast): load setup_zone_types.bin — weight-slot bitmask, no string
   // parsing — score each record with the current weight inputs, keep only the
   // two percentiles the inputs select. Best path for genetic optimization.
   if(InitScoreThresholdsFromSetupBin())
   {
      g_scoreThresholdsLoaded = true;
      ScoreLogPrintActiveThresholds();
      return true;
   }

   // Fallback: parse setup_zone_types.json directly (e.g. bin not yet generated).
   if(InitScoreThresholdsFromSetupZoneJson())
   {
      g_scoreThresholdsLoaded = true;
      ScoreLogPrintActiveThresholds();
      return true;
   }

   Print("Score thresholds: bin + JSON load both failed.");
   return false;
}

//+------------------------------------------------------------------+
double GetMinScoreThreshold()
{
   if(InputScoreLogWriteCsv)
      return 0.0;
   if(!g_scoreThresholdsLoaded)
      return 0.0;
   return g_scoreActiveMinThreshold;
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
   return g_scoreActiveDenomScore;
}
