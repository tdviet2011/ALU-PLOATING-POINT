@echo off
rem Starts the local ALU demo server and opens the page. Needs Python 3; uses Vivado xsim if it is found.
cd /d "%~dp0"
python alu_server.py --open
if errorlevel 1 py -3 alu_server.py --open
pause
