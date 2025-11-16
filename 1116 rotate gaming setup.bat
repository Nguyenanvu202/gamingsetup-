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
:: Use PowerShell to call Cloudflare API and extract total_count
for /f "delims=" %%C in ('curl -s -H "Authorization: Bearer %CF_API_TOKEN%" ^
 "https://api.cloudflare.com/client/v4/zones/%ZONE_ID%/dns_records" ^| ^
 powershell -Command "($input | ConvertFrom-Json).result_info.total_count"') do (
    set "TOTAL_COUNT=%%C"
)

echo Total DNS records: %TOTAL_COUNT%

set /a NEXT_NUM=%TOTAL_COUNT% + 200
set "DOMAIN=App%NEXT_NUM%.nguyentranviethung.org"
set "TUNNEL_NAME=%NEXT_NUM%-nguyentranviethung"
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

:: === KEEP WINDOW OPEN FOR DEBUGGING ===
echo.
echo [DEBUG] Script completed. Review output above.
echo Press any key to close this window...
pause >nul