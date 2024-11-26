@echo off
set script=main
set binName=NESCompress.exe

if exist "%script%.exe" del /q "%script%.exe"
if exist "%binName%" del /q "%binName%"

rem We Don't use -r here because it stops the
rem batch execution, even if we use "start"
nim c --app:console --threads:on --opt:size "%script%.nim"

if not exist "%script%.exe" goto error
ren "%script%.exe" "%binName%"

echo Executing app...
echo.
call %binName%
goto theend

:error
echo error!

pause

:theend
