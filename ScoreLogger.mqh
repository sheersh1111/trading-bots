//+------------------------------------------------------------------+
//| ScoreLogger.mqh - permutation summary CSV read/write             |
//| Write mode: track running max ScoreP100 (int); flush on deinit   |
//| Read mode:  load ScoreP100 from CSV for tester risk sizing         |
//+------------------------------------------------------------------+

#define SCORE_LOG_SUMMARY_CSV    "optimization_permutation_summary.csv"
#define SCORE_LOG_COMBINED_CSV   "optimization_permutation_summary_combined.csv"

double g_riskScoreP100      = 0.0;
int    g_scoreLogP100       = 0;
bool   g_scoreLogWriteMode  = false;

int    g_scoreLogHdrWeeklyFvg  = 0;
int    g_scoreLogHdrDailyFvg   = 0;
int    g_scoreLogHdrH4Fvg      = 0;
int    g_scoreLogHdrM15Fvg     = 0;
int    g_scoreLogHdrW1HighLow  = 0;
int    g_scoreLogHdrD1HighLow  = 0;
int    g_scoreLogHdrH4HighLow  = 0;
int    g_scoreLogHdrM15HighLow = 0;
double g_scoreLogHdrMinScore   = 0.0;
int    g_scoreLogHdrW1Bos      = 0;
int    g_scoreLogHdrD1Bos      = 0;
int    g_scoreLogHdrH4Bos      = 0;
int    g_scoreLogHdrM15Bos     = 0;

struct ScoreLogSummaryRow
{
   int    weeklyFvg;
   int    dailyFvg;
   int    h4Fvg;
   int    m15Fvg;
   int    w1HighLow;
   int    d1HighLow;
   int    h4HighLow;
   int    m15HighLow;
   double minScore;
   int    w1Bos;
   int    d1Bos;
   int    h4Bos;
   int    m15Bos;
   int    topScoreCount;
   double scoreP100;
   double scoreP90;
};

//+------------------------------------------------------------------+
void ScoreLogResetBuffer()
{
   g_scoreLogP100 = 0;
}

//+------------------------------------------------------------------+
void ScoreLogWriteSummaryHeader(const int fileHandle)
{
   FileWrite(fileHandle,
             "WeeklyFVG",
             "DailyFVG",
             "H4FVG",
             "M15FVG",
             "W1_HighLowZones",
             "D1_HighLowZones",
             "H4_HighLowZones",
             "M15_HighLowZones",
             "MinScore",
             "W1_BOS",
             "D1_BOS",
             "H4_BOS",
             "M15_BOS",
             "PositiveScoreCount",
             "ScoreP100",
             "ScoreP90");
}

//+------------------------------------------------------------------+
void ScoreLogWriteSummaryRow(const int fileHandle, const ScoreLogSummaryRow &row)
{
   FileWrite(fileHandle,
             IntegerToString(row.weeklyFvg),
             IntegerToString(row.dailyFvg),
             IntegerToString(row.h4Fvg),
             IntegerToString(row.m15Fvg),
             IntegerToString(row.w1HighLow),
             IntegerToString(row.d1HighLow),
             IntegerToString(row.h4HighLow),
             IntegerToString(row.m15HighLow),
             DoubleToString(row.minScore, 2),
             IntegerToString(row.w1Bos),
             IntegerToString(row.d1Bos),
             IntegerToString(row.h4Bos),
             IntegerToString(row.m15Bos),
             IntegerToString(row.topScoreCount),
             IntegerToString((int)MathRound(row.scoreP100)),
             IntegerToString((int)MathRound(row.scoreP90)));
}

//+------------------------------------------------------------------+
void ScoreLogBuildCurrentSummaryRow(ScoreLogSummaryRow &row, const int scoreP100)
{
   row.weeklyFvg     = g_scoreLogHdrWeeklyFvg;
   row.dailyFvg      = g_scoreLogHdrDailyFvg;
   row.h4Fvg         = g_scoreLogHdrH4Fvg;
   row.m15Fvg        = g_scoreLogHdrM15Fvg;
   row.w1HighLow     = g_scoreLogHdrW1HighLow;
   row.d1HighLow     = g_scoreLogHdrD1HighLow;
   row.h4HighLow     = g_scoreLogHdrH4HighLow;
   row.m15HighLow    = g_scoreLogHdrM15HighLow;
   row.minScore      = g_scoreLogHdrMinScore;
   row.w1Bos         = g_scoreLogHdrW1Bos;
   row.d1Bos         = g_scoreLogHdrD1Bos;
   row.h4Bos         = g_scoreLogHdrH4Bos;
   row.m15Bos        = g_scoreLogHdrM15Bos;
   row.topScoreCount = 0;
   row.scoreP100     = (double)scoreP100;
   row.scoreP90      = 0.0;
}

//+------------------------------------------------------------------+
bool ScoreLogReadSummaryRow(const int fileHandle, ScoreLogSummaryRow &row)
{
   if(FileIsEnding(fileHandle))
      return false;

   row.weeklyFvg     = (int)StringToInteger(FileReadString(fileHandle));
   row.dailyFvg      = (int)StringToInteger(FileReadString(fileHandle));
   row.h4Fvg         = (int)StringToInteger(FileReadString(fileHandle));
   row.m15Fvg        = (int)StringToInteger(FileReadString(fileHandle));
   row.w1HighLow     = (int)StringToInteger(FileReadString(fileHandle));
   row.d1HighLow     = (int)StringToInteger(FileReadString(fileHandle));
   row.h4HighLow     = (int)StringToInteger(FileReadString(fileHandle));
   row.m15HighLow    = (int)StringToInteger(FileReadString(fileHandle));
   row.minScore      = StringToDouble(FileReadString(fileHandle));
   row.w1Bos         = (int)StringToInteger(FileReadString(fileHandle));
   row.d1Bos         = (int)StringToInteger(FileReadString(fileHandle));
   row.h4Bos         = (int)StringToInteger(FileReadString(fileHandle));
   row.m15Bos        = (int)StringToInteger(FileReadString(fileHandle));
   row.topScoreCount = (int)StringToInteger(FileReadString(fileHandle));
   row.scoreP100     = StringToDouble(FileReadString(fileHandle));
   row.scoreP90      = StringToDouble(FileReadString(fileHandle));
   return true;
}

//+------------------------------------------------------------------+
bool ScoreLogRowMatchesCurrentPermutation(const ScoreLogSummaryRow &row)
{
   if(row.weeklyFvg != g_scoreLogHdrWeeklyFvg)
      return false;
   if(row.dailyFvg != g_scoreLogHdrDailyFvg)
      return false;
   if(row.h4Fvg != g_scoreLogHdrH4Fvg)
      return false;
   if(row.m15Fvg != g_scoreLogHdrM15Fvg)
      return false;
   if(row.w1HighLow != g_scoreLogHdrW1HighLow)
      return false;
   if(row.d1HighLow != g_scoreLogHdrD1HighLow)
      return false;
   if(row.h4HighLow != g_scoreLogHdrH4HighLow)
      return false;
   if(row.m15HighLow != g_scoreLogHdrM15HighLow)
      return false;
   if(MathAbs(row.minScore - g_scoreLogHdrMinScore) > 0.001)
      return false;
   if(row.w1Bos != g_scoreLogHdrW1Bos)
      return false;
   if(row.d1Bos != g_scoreLogHdrD1Bos)
      return false;
   if(row.h4Bos != g_scoreLogHdrH4Bos)
      return false;
   if(row.m15Bos != g_scoreLogHdrM15Bos)
      return false;
   return true;
}

//+------------------------------------------------------------------+
int ScoreLogLoadSummaryRowsFromFile(const string csvFileName, ScoreLogSummaryRow &rows[])
{
   ArrayResize(rows, 0);
   if(csvFileName == "" || !FileIsExist(csvFileName))
      return 0;

   const int readFlags = FILE_READ | FILE_CSV | FILE_SHARE_READ;
   int fileHandle = FileOpen(csvFileName, readFlags, ',');
   if(fileHandle == INVALID_HANDLE)
      return 0;

   if(!FileIsEnding(fileHandle))
   {
      for(int col = 0; col < 16; col++)
      {
         if(FileIsEnding(fileHandle))
            break;
         FileReadString(fileHandle);
      }
   }

   while(!FileIsEnding(fileHandle))
   {
      ScoreLogSummaryRow row;
      if(!ScoreLogReadSummaryRow(fileHandle, row))
         break;

      const int idx = ArraySize(rows);
      ArrayResize(rows, idx + 1);
      rows[idx] = row;
   }

   FileClose(fileHandle);
   return ArraySize(rows);
}

//+------------------------------------------------------------------+
bool ScoreLogWriteAllSummaryRows(const ScoreLogSummaryRow &rows[])
{
   const int writeFlags = FILE_WRITE | FILE_CSV | FILE_SHARE_WRITE;
   int fileHandle = FileOpen(SCORE_LOG_SUMMARY_CSV, writeFlags, ',');
   if(fileHandle == INVALID_HANDLE)
      return false;

   ScoreLogWriteSummaryHeader(fileHandle);
   const int rowCount = ArraySize(rows);
   for(int i = 0; i < rowCount; i++)
      ScoreLogWriteSummaryRow(fileHandle, rows[i]);

   FileClose(fileHandle);
   return true;
}

//+------------------------------------------------------------------+
bool ScoreLogTryApplyRiskScoreP100FromRows(const ScoreLogSummaryRow &rows[])
{
   const int rowCount = ArraySize(rows);
   for(int i = 0; i < rowCount; i++)
   {
      if(!ScoreLogRowMatchesCurrentPermutation(rows[i]))
         continue;

      if(rows[i].scoreP100 > 0.0)
      {
         g_riskScoreP100 = rows[i].scoreP100;
         return true;
      }
      return false;
   }
   return false;
}

//+------------------------------------------------------------------+
bool InitRiskScoreP100FromPermutationSummary()
{
   g_riskScoreP100 = 0.0;

   ScoreLogSummaryRow rows[];
   if(FileIsExist(SCORE_LOG_COMBINED_CSV))
   {
      if(ScoreLogLoadSummaryRowsFromFile(SCORE_LOG_COMBINED_CSV, rows) > 0
         && ScoreLogTryApplyRiskScoreP100FromRows(rows))
         return true;
   }
   if(FileIsExist(SCORE_LOG_SUMMARY_CSV))
   {
      if(ScoreLogLoadSummaryRowsFromFile(SCORE_LOG_SUMMARY_CSV, rows) > 0
         && ScoreLogTryApplyRiskScoreP100FromRows(rows))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double GetRiskNormalizationScore()
{
   if(!InputScoreLogWriteCsv && MQLInfoInteger(MQL_TESTER) && g_riskScoreP100 > 0.0)
      return g_riskScoreP100;
   return GetMaxPossibleScore();
}

//+------------------------------------------------------------------+
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
                                 const int weightM15Bos,
                                 const bool writeMode)
{
   g_scoreLogHdrWeeklyFvg  = weightWeeklyFvg;
   g_scoreLogHdrDailyFvg   = weightDailyFvg;
   g_scoreLogHdrH4Fvg      = weightH4Fvg;
   g_scoreLogHdrM15Fvg     = weightM15Fvg;
   g_scoreLogHdrW1HighLow  = weightW1HighLow;
   g_scoreLogHdrD1HighLow  = weightD1HighLow;
   g_scoreLogHdrH4HighLow  = weightH4HighLow;
   g_scoreLogHdrM15HighLow = weightM15HighLow;
   g_scoreLogHdrMinScore   = minScore;
   g_scoreLogHdrW1Bos      = weightW1Bos;
   g_scoreLogHdrD1Bos      = weightD1Bos;
   g_scoreLogHdrH4Bos      = weightH4Bos;
   g_scoreLogHdrM15Bos     = weightM15Bos;

   g_scoreLogWriteMode = writeMode;
   if(g_scoreLogWriteMode)
      ScoreLogResetBuffer();
}

//+------------------------------------------------------------------+
void LogAllSetupScores(const double score)
{
   if(!g_scoreLogWriteMode)
      return;
   if(score <= 0.0)
      return;

   const int scoreInt = (int)MathRound(score);
   if(scoreInt > g_scoreLogP100)
      g_scoreLogP100 = scoreInt;
}

//+------------------------------------------------------------------+
void FlushScoreLogToFile()
{
   if(!g_scoreLogWriteMode || g_scoreLogP100 <= 0)
      return;

   ScoreLogSummaryRow currentRow;
   ScoreLogBuildCurrentSummaryRow(currentRow, g_scoreLogP100);

   ScoreLogSummaryRow rows[];
   ScoreLogLoadSummaryRowsFromFile(SCORE_LOG_SUMMARY_CSV, rows);

   int matchIndex = -1;
   const int rowCount = ArraySize(rows);
   for(int i = 0; i < rowCount; i++)
   {
      if(ScoreLogRowMatchesCurrentPermutation(rows[i]))
      {
         matchIndex = i;
         break;
      }
   }

   if(matchIndex >= 0)
      rows[matchIndex] = currentRow;
   else
   {
      const int idx = ArraySize(rows);
      ArrayResize(rows, idx + 1);
      rows[idx] = currentRow;
   }

   ScoreLogWriteAllSummaryRows(rows);
}
