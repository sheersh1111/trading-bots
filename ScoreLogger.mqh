//+------------------------------------------------------------------+
//| ScoreLogger.mqh - Optimization permutation summary CSV logger    |
//| In-memory top-K buffer per pass; one shared CSV on deinit        |
//+------------------------------------------------------------------+

#define SCORE_LOG_SUMMARY_CSV "OptimizationData\\permutation_scores.csv"

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
bool ScoreLogSummaryFileNeedsHeader()
{
   if(!FileIsExist(SCORE_LOG_SUMMARY_CSV))
      return true;

   int fileHandle = FileOpen(SCORE_LOG_SUMMARY_CSV, FILE_READ | FILE_CSV | FILE_SHARE_READ, ',');
   if(fileHandle == INVALID_HANDLE)
      return true;

   const bool needsHeader = (FileSize(fileHandle) <= 0);
   FileClose(fileHandle);
   return needsHeader;
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

   if(g_scoreLogEnabled)
      FolderCreate("OptimizationData", FILE_SHARE_WRITE);
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
// Append one summary row for this permutation to the shared CSV.
void FlushScoreLogToFile()
{
   if(!g_scoreLogEnabled || g_scoreLogCount <= 0)
      return;

   ScoreLogSortBufferDescending();

   const double scoreP100 = g_allScores[0];
   double scoreP90        = scoreP100;
   if(g_scoreLogCount >= 2)
      scoreP90 = g_allScores[g_scoreLogCount - 2];

   const int openFlags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_WRITE;
   int fileHandle = FileOpen(SCORE_LOG_SUMMARY_CSV, openFlags, ',');
   if(fileHandle == INVALID_HANDLE)
      return;

   if(ScoreLogSummaryFileNeedsHeader())
      ScoreLogWriteSummaryHeader(fileHandle);
   else if(FileSize(fileHandle) > 0)
      FileSeek(fileHandle, 0, SEEK_END);

   FileWrite(fileHandle,
             IntegerToString(g_scoreLogHdrWeeklyFvg),
             IntegerToString(g_scoreLogHdrDailyFvg),
             IntegerToString(g_scoreLogHdrH4Fvg),
             IntegerToString(g_scoreLogHdrM15Fvg),
             IntegerToString(g_scoreLogHdrW1HighLow),
             IntegerToString(g_scoreLogHdrD1HighLow),
             IntegerToString(g_scoreLogHdrH4HighLow),
             IntegerToString(g_scoreLogHdrM15HighLow),
             DoubleToString(g_scoreLogHdrMinScore, 2),
             IntegerToString(g_scoreLogHdrW1Bos),
             IntegerToString(g_scoreLogHdrD1Bos),
             IntegerToString(g_scoreLogHdrH4Bos),
             IntegerToString(g_scoreLogHdrM15Bos),
             IntegerToString(g_scoreLogCount),
             DoubleToString(scoreP100, 2),
             DoubleToString(scoreP90, 2));

   FileClose(fileHandle);
}
