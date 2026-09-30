@echo off
rem Builds and runs the hxunity-yaml test suite as a native binary.
rem
rem Compiling to Neko and booting to a .exe once is far faster than re-running
rem `haxe --run`, which recompiles through the Haxe compile server on every
rem invocation. Pass --rebuild to force a recompile.
rem
rem Usage:
rem   build\test.cmd                              (run the suite, no corpus)
rem   build\test.cmd D:\Project\Game\Assets       (also check real Unity files)
rem   build\test.cmd D:\Project\Game\Assets --rebuild

setlocal
set ROOT=%~dp0..
set OUT=%ROOT%\build
set HAXE=C:\HaxeToolkit\haxe\haxe.exe

if not exist "%OUT%" mkdir "%OUT%"

set REBUILD=0
for %%A in (%*) do if "%%A"=="--rebuild" set REBUILD=1

if "%REBUILD%"=="1" goto compile
if not exist "%OUT%\test.exe" goto compile
if not exist "%OUT%\validate.exe" goto compile
goto run

:compile
echo building tests...
"%HAXE%" -cp "%ROOT%\src" -cp "%ROOT%\tests" -main TestMain -neko "%OUT%\test.n" || exit /b 1
nekotools boot "%OUT%\test.n" || exit /b 1
echo building validator...
"%HAXE%" -cp "%ROOT%\src" -cp "%ROOT%\tools" -main Validate -neko "%OUT%\validate.n" || exit /b 1
nekotools boot "%OUT%\validate.n" || exit /b 1
echo built.

:run
"%OUT%\test.exe" %*
exit /b %ERRORLEVEL%
