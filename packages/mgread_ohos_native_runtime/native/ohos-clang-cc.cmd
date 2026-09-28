@echo off
setlocal
if "%OHOS_SDK_NATIVE%"=="" set "OHOS_SDK_NATIVE=D:\DevEco Studio\sdk\default\openharmony\native"
"%OHOS_SDK_NATIVE%\llvm\bin\clang.exe" --target=aarch64-unknown-linux-ohos --sysroot="%OHOS_SDK_NATIVE%\sysroot" -D__MUSL__ %*
exit /b %ERRORLEVEL%
