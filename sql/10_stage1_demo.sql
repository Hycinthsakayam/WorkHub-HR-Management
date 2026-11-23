/* =====================================================================
   WorkHub - Stage 1 review demo script (SQL Server)
   Script : 10_stage1_demo.sql
   Run section by section in SSMS: select a block and press F5.
   SAFE: every block that changes data runs inside BEGIN TRAN ... ROLLBACK,
   except section 6 (the payroll job), whose output table is meant to persist.
   ===================================================================== */

USE WorkHubDB;
SET NOCOUNT ON;
GO

/* ---------- 1. VIEWS (reports) ---------------------------------------- */
SELECT TOP 5 * FROM dbo.vw_EmployeeDirectory ORDER BY EmployeeID;
SELECT * FROM dbo.vw_DepartmentHeadcount ORDER BY Headcount DESC, DepartmentID;
SELECT * FROM dbo.vw_EmployeesOnLeaveToday;
SELECT * FROM dbo.vw_PendingLeaveApprovals ORDER BY ManagerID, StartDate;
SELECT * FROM dbo.vw_SalaryDistributionByDepartment ORDER BY DepartmentID;
SELECT * FROM dbo.vw_ReviewCycleCompletion ORDER BY ReviewCycle;
SELECT TOP 8 * FROM dbo.vw_ReportingHierarchy ORDER BY ReportingPath;
SELECT * FROM dbo.fn_LeaveBalance(2026) WHERE EmployeeID IN (4, 9) ORDER BY EmployeeID, LeaveType;
GO

/* ---------- 2. STORED PROCEDURES - reports ----------------------------- */
EXEC dbo.usp_Report_DepartmentsByHeadcount;
EXEC dbo.usp_Report_EmployeesOnLeave @AsOf = '2026-11-19';
EXEC dbo.usp_Report_AverageOvertimeByDepartment @FromDate = '2026-10-01', @ToDate = '2026-10-31';
EXEC dbo.usp_Report_TopRatedEmployees @TopN = 5;
EXEC dbo.usp_Report_PendingLeaveApprovals @ManagerID = 4;
EXEC dbo.usp_Report_SalaryDistribution;
EXEC dbo.usp_GetLeaveBalance @EmployeeID = 9, @Year = 2026;
GO

/* ---------- 3. STORED PROCEDURES - business rules (each error is caught) */
BEGIN TRY EXEC dbo.usp_GetEmployeeById @EmployeeID = 999; END TRY
BEGIN CATCH SELECT 'usp_GetEmployeeById 999' AS Test, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage; END CATCH;

BEGIN TRY EXEC dbo.usp_RequestLeave @EmployeeID = 9, @LeaveType = N'Annual', @StartDate = '2026-12-01', @EndDate = '2026-12-31'; END TRY
BEGIN CATCH SELECT 'Leave over balance' AS Test, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage; END CATCH;

BEGIN TRY EXEC dbo.usp_RequestLeave @EmployeeID = 9, @LeaveType = N'Annual', @StartDate = '2026-03-10', @EndDate = '2026-03-11'; END TRY
BEGIN CATCH SELECT 'Leave overlaps approved' AS Test, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage; END CATCH;

BEGIN TRY EXEC dbo.usp_ApproveLeave @LeaveID = 3, @ApproverID = 5; END TRY
BEGIN CATCH SELECT 'Approve by wrong manager' AS Test, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage; END CATCH;

BEGIN TRY EXEC dbo.usp_SubmitTimesheet @EmployeeID = 9, @WorkDate = '2026-11-20', @HoursWorked = 24.5; END TRY
BEGIN CATCH SELECT 'Timesheet 24.5 h' AS Test, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage; END CATCH;

BEGIN TRY EXEC dbo.usp_SubmitPerformanceReview @EmployeeID = 9, @ReviewerID = 4, @ReviewDate = '2026-11-20', @Rating = 4; END TRY
BEGIN CATCH SELECT 'Second review same cycle' AS Test, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage; END CATCH;

BEGIN TRY EXEC dbo.usp_AssignManager @EmployeeID = 4, @ManagerID = 9; END TRY
BEGIN CATCH SELECT 'Circular manager' AS Test, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage; END CATCH;
GO

/* ---------- 4. Happy path inside a rolled-back transaction ------------- */
BEGIN TRANSACTION;
    EXEC dbo.usp_GetLeaveBalance @EmployeeID = 9, @Year = 2026;          -- Annual remaining 15
    EXEC dbo.usp_ApproveLeave @LeaveID = 3, @ApproverID = 4;             -- approved, remaining 11
    SELECT LeaveID, EmployeeID, Action, OldStatus, NewStatus, ChangedBy  -- audit trigger wrote this
    FROM dbo.LeaveRequestAudit WHERE LeaveID = 3;
ROLLBACK TRANSACTION;
GO

/* ---------- 5. TRIGGERS fired by direct SQL (bypassing the procedures) - */
-- 5a. Overlap guard: approving leave #3 (21-24 Dec) after inserting an overlapping approved leave
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO dbo.LeaveRequest (EmployeeID, LeaveType, StartDate, EndDate, Status)
        VALUES (9, N'Casual', '2026-12-22', '2026-12-22', N'Approved');
        UPDATE dbo.LeaveRequest SET Status = N'Approved' WHERE LeaveID = 3;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT 'trg_LeaveRequest_NoOverlap' AS TriggerTest, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH;

-- 5b. Daily 24 h limit across two timesheet rows (Rohan already has 8-10 h on 2026-10-05)
BEGIN TRY
    INSERT INTO dbo.Timesheet (EmployeeID, WorkDate, HoursWorked) VALUES (9, '2026-10-05', 16);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT 'trg_Timesheet_DailyLimit' AS TriggerTest, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH;

-- 5c. One review per cycle
BEGIN TRY
    INSERT INTO dbo.PerformanceReview (EmployeeID, ReviewerID, ReviewDate, Rating) VALUES (9, 4, '2026-12-01', 5);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT 'trg_PerformanceReview_OnePerCycle' AS TriggerTest, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH;

-- 5d. Circular reporting: 1 -> 24 while 24 -> 23 -> 1
BEGIN TRY
    UPDATE dbo.Employee SET ManagerID = 24 WHERE EmployeeID = 1;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT 'trg_Employee_NoCircularManager' AS TriggerTest, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH;

-- 5e. Salary history (rolled back)
BEGIN TRANSACTION;
    UPDATE dbo.Employee SET Salary = Salary * 1.10 WHERE EmployeeID = 9;
    SELECT EmployeeID, OldSalary, NewSalary, ChangedBy FROM dbo.SalaryHistory WHERE EmployeeID = 9;
ROLLBACK TRANSACTION;
GO

/* ---------- 6. CURSOR JOB - monthly payroll inputs --------------------- */
EXEC dbo.usp_Job_GenerateMonthlyPayrollInputs @Year = 2026, @Month = 10;
SELECT TOP 5 EmployeeID, DaysWorked, OvertimeHours, BasePay, OvertimePay, GrossPay, Deductions, NetPay
FROM dbo.PayrollInput WHERE PeriodYear = 2026 AND PeriodMonth = 10 AND EmployeeID IN (4, 9) ORDER BY EmployeeID;
SELECT TOP 5 JobRunID, JobName, Parameters, StartedAt, FinishedAt, RowsProcessed, Status, Message
FROM dbo.JobRunLog ORDER BY JobRunID DESC;
GO

/* ---------- 7. NEW REQUIREMENT - course waitlist (rolled back) --------- */
SELECT CourseID, CourseTitle, Capacity, SeatsTaken, EmployeeName, Status, WaitlistPosition
FROM dbo.vw_CourseWaitlist WHERE CourseID = 1
ORDER BY CASE Status WHEN N'Enrolled' THEN 0 ELSE 1 END, WaitlistPosition;

BEGIN TRANSACTION;
    EXEC dbo.usp_EnrollInCourse @CourseID = 1, @EmployeeID = 29;     -- full -> Waitlisted, position 3
    EXEC dbo.usp_CancelEnrollment @CourseID = 1, @EmployeeID = 11;   -- seat freed -> Fatima Sheikh promoted
ROLLBACK TRANSACTION;

BEGIN TRY EXEC dbo.usp_EnrollInCourse @CourseID = 1, @EmployeeID = 9; END TRY
BEGIN CATCH SELECT 'Enrol twice' AS Test, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage; END CATCH;
GO

/* ---------- 8. Inventory of database objects --------------------------- */
SELECT type_desc AS ObjectType, COUNT(*) AS Count
FROM sys.objects
WHERE is_ms_shipped = 0 AND type IN ('U','V','P','TR','FN','IF')
  AND name NOT LIKE 'sp[_]%diagram%' AND name NOT IN ('sysdiagrams', 'fn_diagramobjects')
GROUP BY type_desc ORDER BY type_desc;
GO
