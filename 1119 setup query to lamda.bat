@echo off
setlocal

:: Auto-elevate to Admin — but only if not already elevated
fltmc >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    goto :EOF
)

:: If we reach here, we are running as Admin
echo [INFO] Running with Administrator privileges.
echo.

:: =============== CONFIG ===============
set "CF_API_TOKEN=zFMo2f2MJ5bz9j3hc_cGNHjGyMLYBRS306JXIb4y"
set "LOCAL_SERVICE=http://127.0.0.1:8080"
set "ACCOUNT_ID=6d54e9aa12b7627c5fb230ae1cb8e377"
set "ROOT_DOMAIN=nguyentranviethung.org"
set "ENCRYPTION_PASSWORD=test"  ← 🔑 CHANGE THIS TO A STRONG PASSWORD
:: ======================================

echo [1/6] Installing Sunshine...
if not exist "%USERPROFILE%\Downloads\Sunshine-Windows-AMD64-installer.exe" (
    curl -L "https://github.com/LizardByte/Sunshine/releases/latest/download/Sunshine-Windows-AMD64-installer.exe" -o "%USERPROFILE%\Downloads\Sunshine-Windows-AMD64-installer.exe"
)
"%USERPROFILE%\Downloads\Sunshine-Windows-AMD64-installer.exe" /S
timeout /t 5 /nobreak >nul

:: Set Sunshine credentials (run once)
"C:\Program Files\Sunshine\sunshine.exe" --creds bluefml1 letmeinpls
taskkill /f /im sunshine.exe >nul 2>&1
timeout /t 2 /nobreak >nul
start "" "C:\Program Files\Sunshine\sunshine.exe"

echo [2/6] Setting up Moonlight Web...

set "MOONLIGHT_ZIP=%USERPROFILE%\Downloads\moonlight-web-x86_64-pc-windows-gnu.zip"
set "MOONLIGHT_DIR=%USERPROFILE%\Downloads\moonlight-web"

:: 1. Download ZIP if missing
if not exist "%MOONLIGHT_ZIP%" (
    echo [*] Downloading Moonlight Web ZIP...
    curl -L "https://github.com/MrCreativ3001/moonlight-web-stream/releases/download/v1.6/moonlight-web-x86_64-pc-windows-gnu.zip" -o "%MOONLIGHT_ZIP%" || (
        echo ERROR: Failed to download ZIP.
        pause
        exit /b 1
    )
)

:: 2. Extract only if web-server.exe is missing
if not exist "%MOONLIGHT_DIR%\web-server.exe" (
    echo [*] Extracting Moonlight Web...
    
    :: Create folder
    mkdir "%MOONLIGHT_DIR%" || (
        echo ERROR: Failed to create directory.
        pause
        exit /b 1
    )
    :: Use PowerShell's Expand-Archive (works on all modern Windows)
    powershell -NoLogo -Command "Expand-Archive -Path '%MOONLIGHT_ZIP%' -DestinationPath '%MOONLIGHT_DIR%' -Force" || (
        echo ERROR: Failed to extract ZIP. Is the file valid?
        pause
        exit /b 1
    )
)

:: 3. Create config folder
if not exist "%MOONLIGHT_DIR%\server" mkdir "%MOONLIGHT_DIR%\server"

:: 4. Download config
curl -L "https://raw.githubusercontent.com/bluefml1/bongsenvang-assets/main/config.json" -o "%MOONLIGHT_DIR%\server\config.json" >nul 2>&1

:: 5. Start server — ONLY if exe exists
if exist "%MOONLIGHT_DIR%\web-server.exe" (
    echo [*] Starting Moonlight Web server...
    powershell -Command "Start-Process -FilePath '%MOONLIGHT_DIR%\web-server.exe' -WorkingDirectory '%MOONLIGHT_DIR%' -WindowStyle Hidden"

) else (
    echo ERROR: web-server.exe not found! Extraction failed.
    dir "%MOONLIGHT_DIR%"
    pause
    exit /b 1
)

echo [3/6] Downloading cloudflared...
if not exist "%USERPROFILE%\Downloads\cloudflared.exe" (
    curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -o "%USERPROFILE%\Downloads\cloudflared.exe"
)

echo [4/6] Verifying Cloudflare token...

curl -H "Authorization: Bearer %CF_API_TOKEN%" ^
     "https://api.cloudflare.com/client/v4/accounts/%ACCOUNT_ID%/tokens/verify"

echo [5/6] Creating Cloudflare Tunnel...
for /f "delims=" %%i in ('curl -s -H "Authorization: Bearer %CF_API_TOKEN%" ^
 "https://api.cloudflare.com/client/v4/zones?name=%ROOT_DOMAIN%" ^| ^
 powershell -Command "($input | ConvertFrom-Json).result[0].id"') do (
    set "ZONE_ID=%%i"
)

echo [1/7] Detecting Public and Private IPs...
:: === GET PUBLIC IP (with fallback and error handling) ===
set "PUBLIC_IP="
for /f "delims=" %%i in ('powershell -Command "try { (irm -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 5).Trim() } catch { 'Failed' }"') do set "PUBLIC_IP=%%i"

if "!PUBLIC_IP!"=="" set "PUBLIC_IP=Failed"
if "!PUBLIC_IP!"=="Failed" (
    echo ERROR: Could not fetch public IP.
    set "PUBLIC_IP=127.0.0.1"
) else (
    echo Public IP: !PUBLIC_IP!
)

:: Get Private IP - 100% reliable (uses ipconfig as fallback)
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "192.168.1."') do (
    for /f "tokens=* delims= " %%b in ("%%a") do (
        set "PRIVATE_IP=%%b"
        goto :private_ip_found
    )
)
:private_ip_found
if not defined PRIVATE_IP set "PRIVATE_IP=127.0.0.1"
echo Private IP: %PRIVATE_IP%

echo [2/7] Generating encrypted DNS ID from both IPs...
:: Combine IPs and generate short encrypted ID (ALL IN ONE LINE)
for /f "delims=" %%h in ('powershell -NoLogo -Command "$ips='%PUBLIC_IP%,%PRIVATE_IP%';$pwd='%ENCRYPTION_PASSWORD%';$salt=[byte[]]@(0..15);$derive=New-Object Security.Cryptography.Rfc2898DeriveBytes($pwd,$salt,10000,[Security.Cryptography.HashAlgorithmName]::SHA256);$key=$derive.GetBytes(32);$iv=$derive.GetBytes(16);$aes=[Security.Cryptography.Aes]::Create();$aes.Key=$key;$aes.IV=$iv;$enc=$aes.CreateEncryptor().TransformFinalBlock([Text.Encoding]::UTF8.GetBytes($ips),0,$ips.Length);$hash=(New-Object Security.Cryptography.SHA256Managed).ComputeHash($enc);$alpha='abcdefghijklmnopqrstuvwxyz0123456789';$id='';for($i=0;$i-lt8;$i++){$id+=$alpha[[int]$hash[$i]%%$alpha.Length]};$id.ToUpper()"') do set "DNS_ID=%%h"

set "DOMAIN=%DNS_ID%.%ROOT_DOMAIN%"
set "TUNNEL_NAME=%DNS_ID%-tunnel"
echo Encrypted DNS ID: %DNS_ID%
echo Full Domain: %DOMAIN%

:: Get tunnel ID and (non-existent) token from API response

:: Create Cloudflare Tunnel
curl --request POST "https://api.cloudflare.com/client/v4/accounts/%ACCOUNT_ID%/cfd_tunnel" ^
     -H "Authorization: Bearer %CF_API_TOKEN%" ^
     -H "Content-Type: application/json" ^
     --data "{ \"name\": \"%TUNNEL_NAME%\", \"config_src\": \"cloudflare\" }" ^
     -o "%TEMP%\tunnel_response.json"

type "%TEMP%\tunnel_response.json"
:: Extract tunnel_id and tunnel_token using PowerShell JSON parser
for /f "delims=" %%A in ('powershell -NoLogo -Command ^
    "(Get-Content -Raw '%TEMP%\tunnel_response.json' | ConvertFrom-Json).result.id"') do (
    set "TUNNEL_ID=%%A"
)


for /f "delims=" %%A in ('powershell -NoLogo -Command ^
    "(Get-Content -Raw '%TEMP%\tunnel_response.json' | ConvertFrom-Json).result.token"') do (
    set "TUNNEL_TOKEN=%%A"
)

echo Tunnel ID: %TUNNEL_ID%
echo Tunnel Token: %TUNNEL_TOKEN%

:: Configure ingress
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/%ACCOUNT_ID%/cfd_tunnel/%TUNNEL_ID%/configurations" ^
    -H "Authorization: Bearer %CF_API_TOKEN%" ^
    -H "Content-Type: application/json" ^
    --data "{\"config\":{\"ingress\":[{\"hostname\":\"%DOMAIN%\",\"service\":\"%LOCAL_SERVICE%\",\"originRequest\":{}},{\"service\":\"http_status:404\"}]}}"


:: Create DNS record
curl -X POST "https://api.cloudflare.com/client/v4/zones/%ZONE_ID%/dns_records" ^
    -H "Authorization: Bearer %CF_API_TOKEN%" ^
    -H "Content-Type: application/json" ^
    --data "{\"type\":\"CNAME\",\"name\":\"%DOMAIN%\",\"content\":\"%TUNNEL_ID%.cfargotunnel.com\",\"proxied\":true}"

echo [6/6] Installing cloudflared as Windows service...
setx CLOUDFLARE_TUNNEL_TOKEN "%CF_API_TOKEN%" /M >nul
"%USERPROFILE%\Downloads\cloudflared.exe" service install "%TUNNEL_TOKEN%"
echo %TUNNEL_NAME%
echo Setup complete! Visit https://%DOMAIN%


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
:: Set Status
set "STATUS=online"
::Get Computer name
for /f "skip=1 delims=" %%A in (
  'wmic computersystem get name'
) do for /f "delims=" %%B in ("%%A") do set "NAME=%%A"
::Set Notes
set "NOTES=ready to use"
:: Output
echo ========================================
echo System Information
echo ========================================
echo Name:		%NAME%
echo Private IP:       	%PRIVATE_IP%
echo Public IP:		%PUBLIC_IP%
echo Domain:		%DOMAIN%
echo Status:	       	%STATUS% 
echo Operating System: 	%OS_NAME% (%OS_VERSION%)
echo Processor:        	%CPU%
echo RAM:              	%TotalPhysicalMemory% GB
echo GPU NAME:         	%GPU_NAME%
echo Last_checkin:	%LAST_CHECKIN%	
echo Notes:		%NOTES%		
echo ========================================


:: Generate JSON payload with EXACT required field names
set "PAYLOAD={\"computer_name\":\"%NAME%\",\"publicIP\":\"%PUBLIC_IP%\",\"privateIP\":\"%PRIVATE_IP%\",\"status\":\"%STATUS%\",\"domain\":\"%DOMAIN%\",\"Operation_system\":\"%OS_NAME%\",\"Processor\":\"%CPU%\",\"RAM\":\"%TotalPhysicalMemory% GB\",\"GPU_name\":\"%GPU_NAME%\",\"last_checkin\":\"%LAST_CHECKIN%\",\"notes\":\"%NOTES%\"}"


curl -X POST https://wxclsqc9p6.execute-api.ap-southeast-1.amazonaws.com/registeringGPUMachine -H "Content-Type: application/json" -d "%PAYLOAD%"


:: === KEEP WINDOW OPEN FOR DEBUGGING ===
echo.
echo [DEBUG] Script completed. Review output above.
echo Press any key to close this window...
pause >nul