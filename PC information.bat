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
for /F "tokens=* skip=1" %%n in ('WMIC path Win32_VideoController get Name ^| findstr "."') do set GPU_NAME=%%n

:: Fallback if chipset is empty
if "%CHIPSET_MFG%%CHIPSET_MODEL%"=="" (
    set "CHIPSET_MFG=Unknown"
    set "CHIPSET_MODEL=Unknown"
)

:: Output
echo ========================================
echo System Information
echo ========================================
echo Operating System: %OS_NAME% (%OS_VERSION%)
echo Processor:        %CPU%
echo RAM:              %TotalPhysicalMemory% GB
echo GPU NAME:          %GPU_NAME%
echo ========================================
echo.
echo IPs detected successfully.
echo Press any key to continue...
pause >nul