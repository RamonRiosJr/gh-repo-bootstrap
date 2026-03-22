@echo off
color 0B
echo.
echo =========================================================
echo       _                 _    ___  ___   ____                 
echo      / \  _   _ _ __ __^| ^|  / _ \/ __^| ^|  _ \  ___   ___ ___ 
echo     / _ \^| ^| ^| ^| '__/ _` ^| ^| ^| ^| \__ \ ^| ^| ^| ^|/ _ \ / __/ __^|
echo    / ___ \ ^|_^| ^| ^| ^| (_^| ^| ^| ^|_^| ^|___/ ^| ^|_^| ^| (_) ^| (__\__ \
echo   /_/   \_\__,_^|_^|  \__,_^|  \___/^|___/ ^|____/ \___/ \___^|___/
echo =========================================================
echo                AURA hOS DOCS PORTAL
echo =========================================================
echo.
echo Starting development server on port 7100...
cd ..\..

:: Install dependencies if node_modules doesn't exist
if not exist "node_modules\" (
    echo Installing dependencies...
    call npm install
)

npm run dev -- --port 7100
