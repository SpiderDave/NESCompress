@echo off
rem %NIMPATH%\dist\mingw32\bin\windres -O coff app.rc -o app32.res
rem %NIMPATH%\dist\mingw64\bin\windres -O coff app.rc -o app64.res
rem %NIMPATH%\dist\mingw32\bin\windres -O coff appTcc.rc -o appTcc32.res
rem %NIMPATH%\dist\mingw64\bin\windres -O coff appTcc.rc -o appTcc64.res
rem %NIMPATH%\dist\mingw32\bin\windres -O coff wWebView.rc -o wWebView32.res
rem %NIMPATH%\dist\mingw64\bin\windres -O coff wWebView.rc -o wWebView64.res
rem %NIMPATH%\dist\mingw32\bin\windres -O coff wWebViewTcc.rc -o wWebViewTcc32.res
rem %NIMPATH%\dist\mingw64\bin\windres -O coff wWebViewTcc.rc -o wWebViewTcc64.res

windres -O coff app.rc -o app32.res
windres -O coff app.rc -o app64.res
windres -O coff appTcc.rc -o appTcc32.res
windres -O coff appTcc.rc -o appTcc64.res
windres -O coff wWebView.rc -o wWebView32.res
windres -O coff wWebView.rc -o wWebView64.res
windres -O coff wWebViewTcc.rc -o wWebViewTcc32.res
windres -O coff wWebViewTcc.rc -o wWebViewTcc64.res
