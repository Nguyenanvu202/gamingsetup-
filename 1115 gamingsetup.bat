@echo off
setlocal enabledelayedexpansion

:: Auto-elevate to Admin
fltmc >nul 2>&1 || (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: =============== CONFIG ===============
set "CF_API_TOKEN=zFMo2f2MJ5bz9j3hc_cGNHjGyMLYBRS306JXIb4y"
set "DOMAIN=nguyentranviethung.org"
set "LOCAL_SERVICE=http://127.0.0.1:8080"
set "TUNNEL_NAME=nguyentranviethung"
set "ACCOUNT_ID=6d54e9aa12b7627c5fb230ae1cb8e377"
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

:: 1. Download ZIP if missing
if not exist "%USERPROFILE%\Downloads\moonlight-web-x86_64-pc-windows-gnu.zip" (
    curl -L "https://github.com/MrCreativ3001/moonlight-web-stream/releases/download/v1.6/moonlight-web-x86_64-pc-windows-gnu.zip" -o "%USERPROFILE%\Downloads\moonlight-web-x86_64-pc-windows-gnu.zip"
)

:: 2. Create the 'moonlight-web' folder FIRST
set "MOONLIGHT_DIR=%USERPROFILE%\Downloads\moonlight-web"
if not exist "%MOONLIGHT_DIR%" (
    mkdir "%MOONLIGHT_DIR%"
    :: 3. Extract INTO the folder (not into Downloads root)
    tar -xf "%USERPROFILE%\Downloads\moonlight-web-x86_64-pc-windows-gnu.zip" -C "%MOONLIGHT_DIR%"
)

:: 4. Create server config folder
if not exist "%MOONLIGHT_DIR%\server\" (
    mkdir "%MOONLIGHT_DIR%\server"
)

:: 5. Download config
curl -L "https://raw.githubusercontent.com/bluefml1/bongsenvang-assets/main/config.json" -o "%MOONLIGHT_DIR%\server\config.json"
timeout /t 3 >nul
:: 6. Start server

:: Create and run a hidden VBS launcher
powershell -WindowStyle Hidden -Command "Start-Process -FilePath '%USERPROFILE%\Downloads\moonlight-web\web-server.exe' -WorkingDirectory '%USERPROFILE%\Downloads\moonlight-web' -WindowStyle Hidden"


:: 7. Wait for server to initialize (critical!)
timeout /t 3 /nobreak >nul

echo [3/6] Downloading cloudflared...
if not exist "%USERPROFILE%\Downloads\cloudflared.exe" (
    curl -L "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -o "%USERPROFILE%\Downloads\cloudflared.exe"
)

echo [4/6] Verifying Cloudflare token...

curl -H "Authorization: Bearer %CF_API_TOKEN%" ^
     "https://api.cloudflare.com/client/v4/accounts/%ACCOUNT_ID%/tokens/verify"


echo [5/6] Creating Cloudflare Tunnel...

:: Get tunnel ID and (non-existent) token from API response
:: Create Cloudflare Tunnel
curl --request POST "https://api.cloudflare.com/client/v4/accounts/%ACCOUNT_ID%/tunnels" ^
     -H "Authorization: Bearer %CF_API_TOKEN%" ^
     -H "Content-Type: application/json" ^
     --data "{ \"name\": \"%TUNNEL_NAME%\", \"config_src\": \"cloudflare\" }" ^
     -o "%TEMP%\tunnel_response.json"

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


:: Get Zone ID

for /f "delims=" %%i in ('curl -s -H "Authorization: Bearer %CF_API_TOKEN%" ^
 "https://api.cloudflare.com/client/v4/zones?name=%DOMAIN%" ^| ^
 powershell -Command "($input | ConvertFrom-Json).result[0].id"') do (
    set "ZONE_ID=%%i"
)

:: Create DNS record
curl -X POST "https://api.cloudflare.com/client/v4/zones/%ZONE_ID%/dns_records" ^
    -H "Authorization: Bearer %CF_API_TOKEN%" ^
    -H "Content-Type: application/json" ^
    --data "{\"type\":\"CNAME\",\"name\":\"%DOMAIN%\",\"content\":\"%TUNNEL_ID%.cfargotunnel.com\",\"proxied\":true}"

echo [6/6] Installing cloudflared as Windows service...
setx CLOUDFLARE_TUNNEL_TOKEN "%CF_API_TOKEN%" /M >nul
"%USERPROFILE%\Downloads\cloudflared.exe" service install "%TUNNEL_TOKEN%"

echo.
echo Setup complete! Visit https://%DOMAIN%
pause