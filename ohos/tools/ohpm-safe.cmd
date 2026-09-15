@echo off
rem Invoke ohpm's Node entry directly.  The DevEco ohpm.bat wrapper recursively
rem re-enters cmd.exe when Hvigor is started through hvigorw.js on Windows.
"%MGREAD_OHPM_NODE%" "%MGREAD_OHPM_CLI%" %*
exit /b %ERRORLEVEL%
