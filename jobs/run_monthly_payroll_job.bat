@echo off
REM ====================================================================
REM WorkHub - monthly payroll inputs job (cursor procedure)
REM SQL Server Express has no SQL Server Agent, so schedule this file with
REM Windows Task Scheduler: Create Basic Task > Monthly > day 1, 02:00 >
REM Start a program > this .bat file.
REM With no parameters the procedure processes the previous month.
REM Every run is recorded in dbo.JobRunLog.
REM ====================================================================
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -d WorkHubDB -Q "EXEC dbo.usp_Job_GenerateMonthlyPayrollInputs;" >> "%~dp0payroll_job.log" 2>&1
exit /b %ERRORLEVEL%
