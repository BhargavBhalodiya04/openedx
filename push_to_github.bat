@echo off
set "PATH=C:\Program Files\Git\cmd;%PATH%"
cd /d "C:\AndAI\openedx-platform"
echo ========================================================
echo Pushing AndAI Open edX codebase to GitHub...
echo Repository: https://github.com/BhargavBhalodiya04/openedx.git
echo ========================================================
git push -u origin main
echo ========================================================
echo Done!
pause
