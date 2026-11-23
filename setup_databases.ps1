# =====================================================================
# WorkHub - rebuild both databases in the correct order.
#   powershell -ExecutionPolicy Bypass -File .\setup_databases.ps1
#   powershell -ExecutionPolicy Bypass -File .\setup_databases.ps1 -SkipMongo
#
# WARNING: drops and recreates SQL Server WorkHubDB (and its saved database
# diagram) and the three MongoDB collections.
# =====================================================================
param(
    [string]$SqlServer = "localhost\SQLEXPRESS",
    [string]$MongoUri  = "mongodb://localhost:27017",
    [switch]$SkipMongo
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$sqlScripts = @(
    "01_create_schema.sql", "02_sample_data.sql", "05_functions_and_views.sql",
    "06_stored_procedures.sql", "07_triggers.sql", "08_cursor_job.sql", "09_course_waitlist.sql"
)
foreach ($script in $sqlScripts) {
    Write-Host "SQL Server  > $script" -ForegroundColor Cyan
    sqlcmd -S $SqlServer -E -C -b -i "sql\$script" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$script failed (exit $LASTEXITCODE)" }
}
Write-Host "SQL Server  > generating payroll inputs for 2026-10 (cursor job)" -ForegroundColor Cyan
sqlcmd -S $SqlServer -E -C -b -d WorkHubDB -Q "SET NOCOUNT ON; EXEC dbo.usp_Job_GenerateMonthlyPayrollInputs 2026, 10;" | Out-Null

if (-not $SkipMongo) {
    foreach ($script in "01_collections_and_validation.js", "02_seed_data.js") {
        Write-Host "MongoDB     > $script" -ForegroundColor Green
        mongosh --quiet $MongoUri --file "mongodb\$script" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$script failed (exit $LASTEXITCODE)" }
    }
}

Write-Host "`nRow counts:" -ForegroundColor Yellow
sqlcmd -S $SqlServer -E -C -W -d WorkHubDB -Q "SET NOCOUNT ON; SELECT 'Plant' T, COUNT(*) N FROM Plant UNION ALL SELECT 'Department', COUNT(*) FROM Department UNION ALL SELECT 'Employee', COUNT(*) FROM Employee UNION ALL SELECT 'LeaveRequest', COUNT(*) FROM LeaveRequest UNION ALL SELECT 'Timesheet', COUNT(*) FROM Timesheet UNION ALL SELECT 'PerformanceReview', COUNT(*) FROM PerformanceReview UNION ALL SELECT 'TrainingCourse', COUNT(*) FROM TrainingCourse UNION ALL SELECT 'CourseEnrollment', COUNT(*) FROM CourseEnrollment UNION ALL SELECT 'PayrollInput', COUNT(*) FROM PayrollInput;"
if (-not $SkipMongo) {
    mongosh --quiet "$MongoUri/WorkHubDB" --eval "['employee_profiles','review_feedback','hr_notifications'].forEach(c => print(c.padEnd(18), db.getCollection(c).countDocuments()))"
}
Write-Host "`nDone." -ForegroundColor Yellow
