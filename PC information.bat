@echo off
setlocal enabledelayedexpansion

:: Auto-elevate to Admin
fltmc >nul 2>&1 || (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)


:: Get Operating System
for /f "tokens=2* delims= " %%a in ('wmic os get caption /value 2^>nul ^| findstr "="') do set "OS_NAME=%%b"
for /f "tokens=2* delims= " %%a in ('wmic os get version /value 2^>nul ^| findstr "="') do set "OS_VERSION=%%b"

:: Get Processor
for /f "tokens=2* delims= " %%a in ('wmic cpu get name /value 2^>nul ^| findstr "="') do set "CPU=%%b"

:: === GET RAM ===
for /f "tokens=2 delims==" %%a in ('wmic computersystem get TotalPhysicalMemory /value') do (
   for /f "delims=" %%b in ("%%a") do (
     Set "RAM_GB=%%b"
   )
)


Set /a TotalPhysicalMemory = %RAM_GB:~0,-3%/1024/1024


:: === GET GPU (NVIDIA/AMD) - CORRECTED ===
set "GPU_NAME="

:: Get NVIDIA GPU first
for /f "tokens=*" %%i in ('wmic path Win32_VideoController get Name ^| findstr /I "NVIDIA"') do (
    set "GPU_NAME=%%i"
)

:: If NVIDIA not found, try AMD / Radeon
if not defined GPU_NAME (
    for /f "tokens=*" %%i in ('wmic path Win32_VideoController get Name ^| findstr /I "AMD Radeon"') do (
        set "GPU_NAME=%%i"
    )
)

:: If still nothing, take first available GPU
if not defined GPU_NAME (
    for /f "skip=1 tokens=*" %%i in ('wmic path Win32_VideoController get Name ^| findstr "."') do (
        if not defined GPU_NAME set "GPU_NAME=%%i"
    )
)

:: Get current timestamp
:: Use WMIC to retrieve date and time
FOR /F "skip=1 tokens=1-6" %%G IN ('WMIC Path Win32_LocalTime Get Day^,Hour^,Minute^,Month^,Second^,Year /Format:table') DO (
   IF "%%~L"=="" goto s_done
      Set _yyyy=%%L
      Set _mm=00%%J
      Set _dd=00%%G
      Set _hour=00%%H
      SET _minute=00%%I
)
:s_done

:: Pad digits with leading zeros
      Set _mm=%_mm:~-2%
      Set _dd=%_dd:~-2%
      Set _hour=%_hour:~-2%
      Set _minute=%_minute:~-2%

:: Display the date/time in ISO 8601 format:
Set LAST_CHECKIN=%_yyyy%-%_mm%-%_dd% %_hour%:%_minute%
Echo %_isodate%
:: Output
echo ========================================
echo System Information
echo ========================================
echo Operating System: %OS_NAME% (%OS_VERSION%)
echo Processor:        %CPU%
echo RAM:              %TotalPhysicalMemory% GB
echo GPU NAME:          %GPU_NAME%
echo Last Check-in: %LAST_CHECKIN%
echo ========================================
echo.
echo IPs detected successfully.
echo Press any key to continue...
pause >nul
