@echo off
rem ============================================================
rem instalar.bat - instala o bundle Hydro para o USUARIO ATUAL
rem   Uso:  instalar.bat                      (instala a versao de desenvolvimento)
rem         instalar.bat "..\dist\Hydro.bundle"  (instala a versao compilada)
rem Nao precisa de administrador. Destino:
rem   %APPDATA%\Autodesk\ApplicationPlugins\Hydro.bundle
rem ============================================================
setlocal
set "ORIGEM=%~1"
if "%ORIGEM%"=="" set "ORIGEM=%~dp0..\Hydro.bundle"
set "DESTINO=%APPDATA%\Autodesk\ApplicationPlugins\Hydro.bundle"

if not exist "%ORIGEM%\PackageContents.xml" (
  echo [ERRO] PackageContents.xml nao encontrado em "%ORIGEM%"
  exit /b 1
)

if exist "%DESTINO%" (
  echo Removendo versao anterior...
  rmdir /S /Q "%DESTINO%"
)

echo Copiando "%ORIGEM%" para "%DESTINO%"...
xcopy "%ORIGEM%" "%DESTINO%" /E /I /Y /Q >nul
if errorlevel 1 (
  echo [ERRO] Falha ao copiar.
  exit /b 1
)

echo.
echo Instalado. Feche e abra o AutoCAD/Civil 3D (ou use o comando APPAUTOLOADER).
echo Se aparecer aviso de seguranca, adicione a pasta abaixo em TRUSTEDPATHS:
echo   %DESTINO%\Contents
endlocal
