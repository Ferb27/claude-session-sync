@echo off
chcp 65001 >nul
title Sync Claude sessions
echo Re-attaching your old Claude Code sessions to the account you are logged in with...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-claude-sessions.ps1" -OneClick
echo.
pause
