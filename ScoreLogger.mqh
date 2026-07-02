//+------------------------------------------------------------------+
//| ScoreLogger.mqh - Optimization permutation summary CSV logger    |
//| In-memory top-K buffer per pass; upsert one shared CSV on deinit |
//+------------------------------------------------------------------+

#define SCORE_LOG_SUMMARY_CSV "optimization_permutation_summary.csv"

double g_allScores[];
int    g_scoreLogTopCapacity = 0;
int    g_scoreLogCount       = 0;
bool   g_scoreLogEnabled     = false;

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
void ResetScoreLogBuffer(const int topCapacity)
{
   g_scoreLogTopCapacity = MathMax(0, topCapacity);
   g_scoreLogCount       = 0;
   ArrayResize(g_allScores, 0);
}

//+------------------------------------------------------------------+
int ScoreLogFindMinScoreIndex()
{
   if(g_scoreLogCount <= 0)
      return -1;

   int minIdx = 0;
   for(int i = 1; i < g_scoreLogCount; i++)
   {
      if(g_allScores[i] < g_allScores[minIdx])
         minIdx = i;
   }
   return minIdx;
}

//+------------------------------------------------------------------+
void ScoreLogSortBufferDescending()
{
   for(int i = 0; i < g_scoreLogCount - 1; i++)
   {
      for(int j = i + 1; j < g_scoreLogCount; j++)
      {
         if(g_allScores[j] <= g_allScores[i])
            continue;

         const double swapScore = g_allScores[i];
         g_allScores[i] = g_allScores[j];
         g_allScores[j] = swapScore;
      }
   }
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
             "TopScoreCount",
             "ScoreP100",
             "ScoreP90");
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
             DoubleToString(row.scoreP100, 2),
             DoubleToString(row.scoreP90, 2));
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
void ScoreLogBuildCurrentSummaryRow(ScoreLogSummaryRow &row,
                                     const double scoreP100,
                                     const double scoreP90)
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
   row.topScoreCount = g_scoreLogCount;
   row.scoreP100     = scoreP100;
   row.scoreP90      = scoreP90;
}

//+------------------------------------------------------------------+
int ScoreLogLoadSummaryRows(ScoreLogSummaryRow &rows[])
{
   ArrayResize(rows, 0);
   if(!FileIsExist(SCORE_LOG_SUMMARY_CSV))
      return 0;

   const int readFlags = FILE_READ | FILE_CSV | FILE_SHARE_READ;
   int fileHandle = FileOpen(SCORE_LOG_SUMMARY_CSV, readFlags, ',');
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
// Store permutation weights + reset in-memory top-K buffer (no disk I/O).
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
                                 const int topScoreCapacity)
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

   ResetScoreLogBuffer(topScoreCapacity);
   g_scoreLogEnabled = (topScoreCapacity > 0);
}

//+------------------------------------------------------------------+
// Keep top-K positive scores in RAM; discard scores <= 0 and below current minimum.
void LogAllSetupScores(const double score)
{
   if(!g_scoreLogEnabled)
      return;
   if(score <= 0.0)
      return;

   if(g_scoreLogCount < g_scoreLogTopCapacity)
   {
      const int idx = g_scoreLogCount;
      ArrayResize(g_allScores, idx + 1);
      g_allScores[idx] = score;
      g_scoreLogCount++;
      return;
   }

   const int minIdx = ScoreLogFindMinScoreIndex();
   if(minIdx < 0 || score <= g_allScores[minIdx])
      return;

   g_allScores[minIdx] = score;
}

//+------------------------------------------------------------------+
// Upsert one summary row for this permutation into the shared CSV.
void FlushScoreLogToFile()
{
   if(!g_scoreLogEnabled || g_scoreLogCount <= 0)
      return;

   ScoreLogSortBufferDescending();

   const double scoreP100 = g_allScores[0];
   double scoreP90        = scoreP100;
   if(g_scoreLogCount >= 2)
      scoreP90 = g_allScores[g_scoreLogCount - 2];

   ScoreLogSummaryRow currentRow;
   ScoreLogBuildCurrentSummaryRow(currentRow, scoreP100, scoreP90);

   ScoreLogSummaryRow rows[];
   const int rowCount = ScoreLogLoadSummaryRows(rows);

   int matchIndex = -1;
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
