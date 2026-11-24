@echo off
rem Downloads the newest phone app from GitHub's releases and installs it over
rem adb on every phone with Wireless debugging on (or plugged in), keeping what
rem the app holds. --list shows the phones and their versions.
python "%~dp0apps\dinner_planner\tool\install_phones.py" %*
if "%~1"=="" pause
