@echo off
cd /d "%~dp0"
"D:\python3.11.9\python.exe" host\app.py --demo
if errorlevel 1 pause
