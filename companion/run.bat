@echo off
rem Lance le compagnon de Forever Music Player.
rem Au premier lancement, installe ce dont il a besoin dans le dossier .venv.
setlocal
cd /d "%~dp0"

set "PY=py -3"
where py >nul 2>nul
if errorlevel 1 (
    set "PY=python"
    where python >nul 2>nul
    if errorlevel 1 (
        echo Python est introuvable. Installe Python 3.11 ou plus recent depuis
        echo https://www.python.org/downloads/ en cochant "Add python.exe to PATH",
        echo puis relance ce fichier.
        pause
        exit /b 1
    )
)

if not exist ".venv\Scripts\python.exe" (
    echo Premiere installation, un instant...
    %PY% -m venv .venv
    if errorlevel 1 goto failed
    ".venv\Scripts\python.exe" -m pip install --upgrade pip
    ".venv\Scripts\python.exe" -m pip install -r requirements.txt
    if errorlevel 1 goto failed
)

".venv\Scripts\python.exe" -m fmp_companion %*
if errorlevel 1 pause
exit /b 0

:failed
echo L'installation a echoue. Verifie ta connexion Internet puis relance ce fichier.
if exist .venv rmdir /s /q .venv
pause
exit /b 1
