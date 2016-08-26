@IF EXIST "%~dp0\node.exe" (
  "%~dp0\node.exe"  "%~dp0\index" %*
) ELSE (
  node  "%~dp0\index" %*
)