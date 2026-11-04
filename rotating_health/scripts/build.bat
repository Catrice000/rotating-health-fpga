@echo off
cd /d "%~dp0.."
call "D:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -source scripts\build.tcl -log build\vivado.log -journal build\vivado.jou
if errorlevel 1 pause
