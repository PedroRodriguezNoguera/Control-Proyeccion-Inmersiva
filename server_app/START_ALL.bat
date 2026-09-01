@echo off
setlocal EnableExtensions
title SISTEMA MPV MULTIPANTALLA
cls

echo =====================================
echo     INICIANDO SISTEMA COMPLETO
echo =====================================

:: Espera a que el sistema termine de cargar drivers de pantalla/red
:: tras el arranque, para evitar fallos al detectar monitores o red.
echo Esperando 15s a que el sistema termine de arrancar...
timeout /t 15 /nobreak >nul

cd /d %~dp0

:: ─── COMPILACION ─────────────────────────────────────────────────────────────
echo.
echo [0/3] Compilando servidor Java...

if not exist bin mkdir bin

javac -cp "src\main\lib\*" -d bin src\main\java\uk\co\caprica\Main.java 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: La compilacion ha fallado. Revisa los errores anteriores.
    pause
    exit /b 1
)
echo Compilacion OK.

:: ─── DETECCION DE PANTALLAS ───────────────────────────────────────────────────
set "PANTALLAS=1"
set "ABRIR_MPV2=0"

for /f "tokens=1,2" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; $c=[System.Windows.Forms.Screen]::AllScreens.Count; if ($c -ge 2) { Write-Output ($c.ToString() + ' 1') } else { Write-Output ($c.ToString() + ' 0') }" 2^>nul') do (
    set "PANTALLAS=%%A"
    set "ABRIR_MPV2=%%B"
)

echo.
echo Pantallas detectadas: %PANTALLAS%

:: ─── MPV PANTALLA 1 ───────────────────────────────────────────────────────────
echo.
echo [1/3] Iniciando MPV Pantalla 1...

start "" "C:\mpv\mpv.exe" ^
--no-config ^
--screen=0 ^
--fs ^
--loop-file=inf ^
--keep-open=yes ^
--image-display-duration=inf ^
--no-terminal ^
--vo=gpu ^
--gpu-api=d3d11 ^
--panscan=1.0 ^
--input-ipc-server=\\.\pipe\mpv_pro1 ^
"C:\mpv\video.mp4"

timeout /t 2 >nul

:: ─── MPV PANTALLA 2 (solo si hay 2+ pantallas) ────────────────────────────────
if "%ABRIR_MPV2%"=="1" (
    echo [2/3] Iniciando MPV Pantalla 2...

    start "" "C:\mpv\mpv.exe" ^
    --no-config ^
    --screen=1 ^
    --fs ^
    --loop-file=inf ^
    --keep-open=yes ^
    --image-display-duration=inf ^
    --no-terminal ^
    --vo=gpu ^
    --gpu-api=d3d11 ^
    --panscan=1.0 ^
    --input-ipc-server=\\.\pipe\mpv_pro2 ^
    "C:\mpv\video.mp4"

    timeout /t 2 >nul
) else (
    echo [2/3] Solo hay una pantalla, no se inicia MPV Pantalla 2.
)

:: ─── SERVIDOR JAVA ────────────────────────────────────────────────────────────
echo.
echo [3/3] Iniciando servidor Java...

java -cp "bin;src\main\lib\*" uk.co.caprica.Main

echo.
echo El servidor Java se ha cerrado.
pause
