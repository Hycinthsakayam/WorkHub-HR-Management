/* =====================================================================
   WorkHub - Sprint 1 task S1-T5 : Verify the schema
   Script : 03_verify_constraints.sql
   For each UNIQUE, CHECK, DEFAULT and FOREIGN KEY constraint, inserts one
   valid and one invalid row and reports whether the database accepted or
   rejected it as expected. Every check runs in its own transaction that is
   rolled back, so the sample data is left untouched.
   ===================================================================== */

USE WorkHubDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

IF OBJECT_ID('tempdb..#Results') IS NOT NULL DROP TABLE #Results;
CREATE TABLE #Results (TestName NVARCHAR(100), Expected NVARCHAR(10), Actual NVARCHAR(10), Outcome NVARCHAR(4), Detail NVARCHAR(400));
GO

IF OBJECT_ID('tempdb..#RunCheck') IS NOT NULL DROP PROCEDURE #RunCheck;
GO

CREATE PROCEDURE #RunCheck
    @TestName NVARCHAR(100),
    @Expected NVARCHAR(10),      -- 'ACCEPT' or 'REJECT'
    @Sql      NVARCHAR(MAX)
AS
BEGIN
    DECLARE @Actual NVARCHAR(10), @Detail NVARCHAR(400) = N'';
    BEGIN TRANSACTION;           -- each check is isolated and rolled back
    BEGIN TRY
        EXEC sp_executesql @Sql;
        SET @Actual = N'ACCEPT';
    END TRY
    BEGIN CATCH
        SET @Actual = N'REJECT';
        SET @Detail = LEFT(ERROR_MESSAGE(), 400);
    END CATCH;
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #Results VALUES (@TestName, @Expected, @Actual,
        CASE WHEN @Expected = @Actual THEN N'PASS' ELSE N'FAIL' END, @Detail);
END;
GO

-- UNIQUE: Employee.Email
EXEC #RunCheck N'UQ Email - new address',        N'ACCEPT', N'INSERT INTO dbo.Employee (FirstName, LastName, Email, DepartmentID, ManagerID, HireDate, Salary) VALUES (N''Test'', N''User'', N''test.user@ferrovia.com'', 1, 1, ''2026-01-01'', 500000)';
EXEC #RunCheck N'UQ Email - duplicate address',  N'REJECT', N'INSERT INTO dbo.Employee (FirstName, LastName, Email, DepartmentID, ManagerID, HireDate, Salary) VALUES (N''Dup'', N''User'', N''arjun.mehta@ferrovia.com'', 1, 1, ''2026-01-01'', 500000)';

-- CHECK: Employee.Salary >= 0
EXEC #RunCheck N'CK Salary - zero',              N'ACCEPT', N'INSERT INTO dbo.Employee (FirstName, LastName, Email, DepartmentID, ManagerID, HireDate, Salary) VALUES (N''Zero'', N''Pay'', N''zero.pay@ferrovia.com'', 1, 1, ''2026-01-01'', 0)';
EXEC #RunCheck N'CK Salary - negative',          N'REJECT', N'INSERT INTO dbo.Employee (FirstName, LastName, Email, DepartmentID, ManagerID, HireDate, Salary) VALUES (N''Neg'', N''Pay'', N''neg.pay@ferrovia.com'', 1, 1, ''2026-01-01'', -1)';

-- CHECK: employee cannot be their own manager
EXEC #RunCheck N'CK Not own manager - other mgr', N'ACCEPT', N'UPDATE dbo.Employee SET ManagerID = 2 WHERE EmployeeID = 20';
EXEC #RunCheck N'CK Not own manager - self',      N'REJECT', N'UPDATE dbo.Employee SET ManagerID = 20 WHERE EmployeeID = 20';

-- FK: Employee.DepartmentID / ManagerID, Department.PlantID
EXEC #RunCheck N'FK Employee.DepartmentID - valid',   N'ACCEPT', N'UPDATE dbo.Employee SET DepartmentID = 12 WHERE EmployeeID = 20';
EXEC #RunCheck N'FK Employee.DepartmentID - invalid', N'REJECT', N'UPDATE dbo.Employee SET DepartmentID = 999 WHERE EmployeeID = 20';
EXEC #RunCheck N'FK Employee.ManagerID - invalid',    N'REJECT', N'UPDATE dbo.Employee SET ManagerID = 999 WHERE EmployeeID = 20';
EXEC #RunCheck N'FK Department.PlantID - valid',      N'ACCEPT', N'INSERT INTO dbo.Department (DepartmentName, PlantID) VALUES (N''Safety'', 1)';
EXEC #RunCheck N'FK Department.PlantID - invalid',    N'REJECT', N'INSERT INTO dbo.Department (DepartmentName, PlantID) VALUES (N''Ghost'', 999)';

-- FK + DEFAULT + CHECK: LeaveRequest
EXEC #RunCheck N'FK LeaveRequest.EmployeeID - valid',   N'ACCEPT', N'INSERT INTO dbo.LeaveRequest (EmployeeID, LeaveType, StartDate, EndDate) VALUES (9, N''Casual'', ''2027-01-04'', ''2027-01-04'')';
EXEC #RunCheck N'FK LeaveRequest.EmployeeID - invalid', N'REJECT', N'INSERT INTO dbo.LeaveRequest (EmployeeID, LeaveType, StartDate, EndDate) VALUES (999, N''Casual'', ''2027-01-04'', ''2027-01-04'')';
EXEC #RunCheck N'DF LeaveRequest.Status = Pending',     N'ACCEPT', N'INSERT INTO dbo.LeaveRequest (EmployeeID, LeaveType, StartDate, EndDate) VALUES (9, N''Casual'', ''2027-02-01'', ''2027-02-01''); IF (SELECT Status FROM dbo.LeaveRequest WHERE LeaveID = SCOPE_IDENTITY()) <> N''Pending'' THROW 50001, ''Default not applied'', 1;';
EXEC #RunCheck N'CK LeaveRequest dates - end before start', N'REJECT', N'INSERT INTO dbo.LeaveRequest (EmployeeID, LeaveType, StartDate, EndDate) VALUES (9, N''Annual'', ''2027-03-10'', ''2027-03-01'')';
EXEC #RunCheck N'CK LeaveRequest status - unknown',    N'REJECT', N'INSERT INTO dbo.LeaveRequest (EmployeeID, LeaveType, StartDate, EndDate, Status) VALUES (9, N''Annual'', ''2027-03-01'', ''2027-03-02'', N''Maybe'')';

-- FK + DEFAULT + CHECK: Timesheet
EXEC #RunCheck N'CK HoursWorked - 24 hours',     N'ACCEPT', N'INSERT INTO dbo.Timesheet (EmployeeID, WorkDate, HoursWorked) VALUES (9, ''2027-01-05'', 24)';
EXEC #RunCheck N'CK HoursWorked - negative',     N'REJECT', N'INSERT INTO dbo.Timesheet (EmployeeID, WorkDate, HoursWorked) VALUES (9, ''2027-01-05'', -1)';
EXEC #RunCheck N'DF OvertimeHours = 0',          N'ACCEPT', N'INSERT INTO dbo.Timesheet (EmployeeID, WorkDate, HoursWorked) VALUES (9, ''2027-01-06'', 8); IF (SELECT OvertimeHours FROM dbo.Timesheet WHERE TimesheetID = SCOPE_IDENTITY()) <> 0 THROW 50002, ''Default not applied'', 1;';
EXEC #RunCheck N'FK Timesheet.EmployeeID - invalid', N'REJECT', N'INSERT INTO dbo.Timesheet (EmployeeID, WorkDate, HoursWorked) VALUES (999, ''2027-01-05'', 8)';

-- FK + CHECK: PerformanceReview
EXEC #RunCheck N'CK Rating - 1',                 N'ACCEPT', N'INSERT INTO dbo.PerformanceReview (EmployeeID, ReviewerID, ReviewDate, Rating) VALUES (11, 4, ''2027-01-10'', 1)';
EXEC #RunCheck N'CK Rating - 5',                 N'ACCEPT', N'INSERT INTO dbo.PerformanceReview (EmployeeID, ReviewerID, ReviewDate, Rating) VALUES (11, 4, ''2027-01-10'', 5)';
EXEC #RunCheck N'CK Rating - 0',                 N'REJECT', N'INSERT INTO dbo.PerformanceReview (EmployeeID, ReviewerID, ReviewDate, Rating) VALUES (11, 4, ''2027-01-10'', 0)';
EXEC #RunCheck N'CK Rating - 6',                 N'REJECT', N'INSERT INTO dbo.PerformanceReview (EmployeeID, ReviewerID, ReviewDate, Rating) VALUES (11, 4, ''2027-01-10'', 6)';
EXEC #RunCheck N'FK PerformanceReview.ReviewerID - invalid', N'REJECT', N'INSERT INTO dbo.PerformanceReview (EmployeeID, ReviewerID, ReviewDate, Rating) VALUES (11, 999, ''2027-01-10'', 3)';

GO

SELECT TestName, Expected, Actual, Outcome FROM #Results;
SELECT SUM(CASE WHEN Outcome = N'PASS' THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN Outcome = N'FAIL' THEN 1 ELSE 0 END) AS Failed
FROM #Results;
GO
