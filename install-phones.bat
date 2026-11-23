@echo off
rem Builds the phone app on this computer and installs it on every phone with
rem Wireless debugging on (or plugged in). --list shows the phones and their
rem versions; --no-build installs the last build again.
python "%~dp0apps\dinner_planner\tool\install_phones.py" %*
if "%~1"=="" pause
