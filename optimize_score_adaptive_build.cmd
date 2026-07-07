@echo off
setlocal
cd /d "%~dp0"

if not exist json.hpp (
  echo Fetching nlohmann/json single header...
  powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp' -OutFile 'json.hpp'"
  if errorlevel 1 (
    echo Failed to download json.hpp
    exit /b 1
  )
)

echo Compiling optimize_score_adaptive.cpp ...
g++ -std=c++17 -O3 -o optimize_score_adaptive.exe optimize_score_adaptive.cpp
if errorlevel 1 exit /b 1
echo Built optimize_score_adaptive.exe
