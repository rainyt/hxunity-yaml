@echo off
rem Builds and runs the hxunity-yaml test suite as a native binary.
rem
rem Compiling to Neko and booting to a .exe once is far faster than re-running
rem `haxe --run`, which recompiles through the Haxe compile server on every
rem invocation. Pass --rebuild to force a recompile.
rem
rem Usage (the script sits in tools\build, so the paths below are relative to it):
rem   tools\build\test.cmd                            (run the suite, no corpus)
rem   tools\build\test.cmd D:\Project\Game\Assets     (also check real Unity files)
rem   tools\build\test.cmd D:\Project\Game\Assets --rebuild

setlocal
rem Two levels up from tools\build is the repository root.
set ROOT=%~dp0..\..
set OUT=%ROOT%\build
set HAXE=C:\HaxeToolkit\haxe\haxe.exe
rem nekotools lives in the Neko installation, not next to haxe.exe.
set NEKOTOOLS=C:\HaxeToolkit\neko\nekotools.exe
rem A booted Neko binary is still linked against neko.dll, which is not on PATH
rem by default, so the generated .exe finds its runtime.
set PATH=C:\HaxeToolkit\neko;%PATH%

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
"%NEKOTOOLS%" boot "%OUT%\test.n" || exit /b 1
echo building validator...
rem The tools live in src\tools but declare the default package, so the folder
rem itself is the class path, not src.
"%HAXE%" -cp "%ROOT%\src" -cp "%ROOT%\src\tools" -main Validate -neko "%OUT%\validate.n" || exit /b 1
"%NEKOTOOLS%" boot "%OUT%\validate.n" || exit /b 1
echo built.

:run
"%OUT%\test.exe" %*
exit /b %ERRORLEVEL%
