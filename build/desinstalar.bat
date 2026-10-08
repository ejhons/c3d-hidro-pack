@echo off
rem desinstalar.bat - remove o bundle Hydro do usuario atual
setlocal
set "DESTINO=%APPDATA%\Autodesk\ApplicationPlugins\Hydro.bundle"
if exist "%DESTINO%" (
  rmdir /S /Q "%DESTINO%"
  echo Hydro removido de "%DESTINO%".
) else (
  echo Nada para remover em "%DESTINO%".
)
endlocal
