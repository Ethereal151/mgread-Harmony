@echo off
setlocal
if "%OHOS_SDK_NATIVE%"=="" set "OHOS_SDK_NATIVE=D:\DevEco Studio\sdk\default\openharmony\native"
if "%MGREAD_OHOS_TARGET_ARCH%"=="" set "MGREAD_OHOS_TARGET_ARCH=arm64"
if /I "%MGREAD_OHOS_TARGET_ARCH%"=="x64" goto x64
if /I "%MGREAD_OHOS_TARGET_ARCH%"=="arm64" goto arm64
echo Unsupported MgRead OHOS Rust target: %MGREAD_OHOS_TARGET_ARCH% 1>&2
exit /b 2
:x64
"%OHOS_SDK_NATIVE%\llvm\bin\clang.exe" --target=x86_64-linux-ohos %*
exit /b %ERRORLEVEL%
:arm64
"%OHOS_SDK_NATIVE%\llvm\bin\clang.exe" --target=aarch64-linux-ohos %*
exit /b %ERRORLEVEL%
