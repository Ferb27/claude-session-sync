@echo off
chcp 65001 >nul
title Undo Claude sessions sync
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-claude-sessions.ps1" -Undo
echo.
pause
