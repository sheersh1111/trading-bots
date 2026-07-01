//+------------------------------------------------------------------+
//| ScoreLogger.mqh - Optimization setup score CSV logger            |
//+------------------------------------------------------------------+

// Flat lookup row: Timestamp, Score, Context, then all CalculateTotalTradeScore weights.
// FILE_SHARE_WRITE + seek-to-end append (MQL5 has no FILE_APPEND flag).
void LogAllSetupScores(const double score,
                       const string context,
                       const int weightWeeklyFvg,
                       const int weightDailyFvg,
                       const int weightH4Fvg,
                       const int weightM15Fvg,
                       const int weightBreaker,
                       const int weightProtected,
                       const int weightSwingResistance,
                       const int weightSwingSupport,
                       const double clusterMultiplier,
                       const double minScore,
                       const int weightW1Bos,
                       const int weightD1Bos,
                       const int weightH4Bos,
                       const int weightM15Bos)
{
   const string fileName = "OptimizationData.csv";
   const int openFlags = FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_WRITE;

   int fileHandle = FileOpen(fileName, openFlags, ',');
   if(fileHandle == INVALID_HANDLE)
      fileHandle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_SHARE_WRITE, ',');
   if(fileHandle == INVALID_HANDLE)
      return;

   const bool writeHeader = (FileSize(fileHandle) == 0);
   if(!writeHeader)
      FileSeek(fileHandle, 0, SEEK_END);

   if(writeHeader)
   {
      FileWrite(fileHandle,
                "Timestamp",
                "Score",
                "Context",
                "WeeklyFVG",
                "DailyFVG",
                "H4FVG",
                "M15FVG",
                "Breaker",
                "Protected",
                "SwingResistance",
                "SwingSupport",
                "ClusterMultiplier",
                "MinScore",
                "W1_BOS",
                "D1_BOS",
                "H4_BOS",
                "M15_BOS");
   }

   FileWrite(fileHandle,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             DoubleToString(score, 2),
             context,
             weightWeeklyFvg,
             weightDailyFvg,
             weightH4Fvg,
             weightM15Fvg,
             weightBreaker,
             weightProtected,
             weightSwingResistance,
             weightSwingSupport,
             DoubleToString(clusterMultiplier, 2),
             DoubleToString(minScore, 2),
             weightW1Bos,
             weightD1Bos,
             weightH4Bos,
             weightM15Bos);
   FileClose(fileHandle);
}
