@echo off
setlocal
call "%~dp0cli.bat" install %*
set "EXIT_CODE=%ERRORLEVEL%"
if "%~1"=="" pause
exit /b %EXIT_CODE%
