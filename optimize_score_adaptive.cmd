@echo off
setlocal
cd /d "%~dp0"

if not exist optimize_score_adaptive.exe (
  call "%~dp0optimize_score_adaptive_build.cmd"
  if errorlevel 1 exit /b 1
)

optimize_score_adaptive.exe %*
