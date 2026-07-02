//+------------------------------------------------------------------+
//| ScoreLogger.mqh - Per-permutation optimization score CSV logger  |
//+------------------------------------------------------------------+

string g_scoreLogCsvFileName = "";

//+------------------------------------------------------------------+
string ScoreLogFormatPermDouble(const double value)
{
   string s = DoubleToString(value, 2);
   StringReplace(s, ".", "p");
   StringReplace(s, "-", "m");
   return s;
}

//+------------------------------------------------------------------+
string ScoreLogBuildPermutationKey(const int weightWeeklyFvg,
                                   const int weightDailyFvg,
                                   const int weightH4Fvg,
                                   const int weightM15Fvg,
                                   const int weightW1HighLow,
                                   const int weightD1HighLow,
                                   const int weightH4HighLow,
                                   const int weightM15HighLow,
                                   const double minScore,
                                   const int weightW1Bos,
                                   const int weightD1Bos,
                                   const int weightH4Bos,
                                   const int weightM15Bos)
{
   return StringFormat("W%d_D%d_H%d_M%d_HL%d_%d_%d_%d_MS%s_BOS%d_%d_%d_%d",
                       weightWeeklyFvg,
                       weightDailyFvg,
                       weightH4Fvg,
                       weightM15Fvg,
                       weightW1HighLow,
                       weightD1HighLow,
                       weightH4HighLow,
                       weightM15HighLow,
                       ScoreLogFormatPermDouble(minScore),
                       weightW1Bos,
                       weightD1Bos,
                       weightH4Bos,
                       weightM15Bos);
}

//+------------------------------------------------------------------+
// One CSV per input permutation (overwritten each optimization pass).
// Top section: WeightName,WeightValue — then Timestamp,Score,Context rows.
void InitScoreLogPermutationFile(const int weightWeeklyFvg,
                                 const int weightDailyFvg,
                                 const int weightH4Fvg,
                                 const int weightM15Fvg,
                                 const int weightW1HighLow,
                                 const int weightD1HighLow,
                                 const int weightH4HighLow,
                                 const int weightM15HighLow,
                                 const double minScore,
                                 const int weightW1Bos,
                                 const int weightD1Bos,
                                 const int weightH4Bos,
                                 const int weightM15Bos)
{
   FolderCreate("OptimizationData", FILE_SHARE_WRITE);

   const string permKey = ScoreLogBuildPermutationKey(weightWeeklyFvg, weightDailyFvg,
                                                      weightH4Fvg, weightM15Fvg,
                                                      weightW1HighLow, weightD1HighLow,
                                                      weightH4HighLow, weightM15HighLow,
                                                      minScore,
                                                      weightW1Bos, weightD1Bos,
                                                      weightH4Bos, weightM15Bos);
   g_scoreLogCsvFileName = "OptimizationData\\perm_" + permKey + ".csv";

   int fileHandle = FileOpen(g_scoreLogCsvFileName,
                             FILE_WRITE | FILE_CSV | FILE_SHARE_WRITE, ',');
   if(fileHandle == INVALID_HANDLE)
   {
      g_scoreLogCsvFileName = "";
      return;
   }

   FileWrite(fileHandle, "WeightName", "WeightValue");
   FileWrite(fileHandle, "WeeklyFVG", IntegerToString(weightWeeklyFvg));
   FileWrite(fileHandle, "DailyFVG", IntegerToString(weightDailyFvg));
   FileWrite(fileHandle, "H4FVG", IntegerToString(weightH4Fvg));
   FileWrite(fileHandle, "M15FVG", IntegerToString(weightM15Fvg));
   FileWrite(fileHandle, "W1_HighLowZones", IntegerToString(weightW1HighLow));
   FileWrite(fileHandle, "D1_HighLowZones", IntegerToString(weightD1HighLow));
   FileWrite(fileHandle, "H4_HighLowZones", IntegerToString(weightH4HighLow));
   FileWrite(fileHandle, "M15_HighLowZones", IntegerToString(weightM15HighLow));
   FileWrite(fileHandle, "MinScore", DoubleToString(minScore, 2));
   FileWrite(fileHandle, "W1_BOS", IntegerToString(weightW1Bos));
   FileWrite(fileHandle, "D1_BOS", IntegerToString(weightD1Bos));
   FileWrite(fileHandle, "H4_BOS", IntegerToString(weightH4Bos));
   FileWrite(fileHandle, "M15_BOS", IntegerToString(weightM15Bos));
   FileWrite(fileHandle, "", "");
   FileWrite(fileHandle, "Timestamp", "Score", "Context");
   FileClose(fileHandle);
}

//+------------------------------------------------------------------+
void LogAllSetupScores(const double score, const string context)
{
   if(g_scoreLogCsvFileName == "")
      return;

   const int openFlags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_WRITE;
   int fileHandle = FileOpen(g_scoreLogCsvFileName, openFlags, ',');
   if(fileHandle == INVALID_HANDLE)
      return;

   if(FileSize(fileHandle) > 0)
      FileSeek(fileHandle, 0, SEEK_END);

   FileWrite(fileHandle,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             DoubleToString(score, 2),
             context);
   FileClose(fileHandle);
}
