/* =====================================================================
   WorkHub - Stage 1 consolidation : functions and views (reports)
   Script : 05_functions_and_views.sql      Run after 01 and 02.
   Re-runnable: every object uses CREATE OR ALTER.
   ===================================================================== */

USE WorkHubDB;
GO

/* ---------------------------------------------------------------------
   Helper functions
   --------------------------------------------------------------------- */

-- Working days (Mon-Fri) in an inclusive date range. 1900-01-01 was a Monday,
-- so the weekday test does not depend on SET DATEFIRST.
CREATE OR ALTER FUNCTION dbo.fn_WorkingDays (@StartDate DATE, @EndDate DATE)
RETURNS INT
AS
BEGIN
    IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate RETURN 0;
    DECLARE @Day DATE = @StartDate, @Count INT = 0;
    WHILE @Day <= @EndDate
    BEGIN
        IF DATEDIFF(DAY, '19000101', @Day) % 7 < 5 SET @Count += 1;
        SET @Day = DATEADD(DAY, 1, @Day);
    END;
    RETURN @Count;
END;
GO

-- 1 if the employee has at least one direct report (i.e. is a manager).
CREATE OR ALTER FUNCTION dbo.fn_IsManager (@EmployeeID INT)
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN EXISTS (SELECT 1 FROM dbo.Employee WHERE ManagerID = @EmployeeID) THEN 1 ELSE 0 END;
END;
GO

-- Yearly entitlement in working days; NULL = unlimited. Managers get 5 extra Annual days.
-- Same policy as the Python entity layer (Employee / Manager.leave_entitlement).
CREATE OR ALTER FUNCTION dbo.fn_LeaveEntitlement (@EmployeeID INT, @LeaveType NVARCHAR(30))
RETURNS INT
AS
BEGIN
    RETURN CASE @LeaveType
               WHEN N'Annual' THEN 20 + CASE WHEN dbo.fn_IsManager(@EmployeeID) = 1 THEN 5 ELSE 0 END
               WHEN N'Sick'   THEN 10
               WHEN N'Casual' THEN 6
               ELSE NULL                     -- Unpaid: unlimited
           END;
END;
GO

-- Leave balance for every employee and leave type in a year (inline table-valued function).
CREATE OR ALTER FUNCTION dbo.fn_LeaveBalance (@Year INT)
RETURNS TABLE
AS
RETURN
    SELECT e.EmployeeID,
           e.FirstName + N' ' + e.LastName AS EmployeeName,
           t.LeaveType,
           dbo.fn_LeaveEntitlement(e.EmployeeID, t.LeaveType) AS Entitlement,
           ISNULL(u.UsedDays, 0) AS UsedDays,
           dbo.fn_LeaveEntitlement(e.EmployeeID, t.LeaveType) - ISNULL(u.UsedDays, 0) AS RemainingDays
    FROM dbo.Employee AS e
    CROSS JOIN (VALUES (N'Annual'), (N'Sick'), (N'Casual'), (N'Unpaid')) AS t (LeaveType)
    OUTER APPLY (
        SELECT SUM(dbo.fn_WorkingDays(l.StartDate, l.EndDate)) AS UsedDays
        FROM dbo.LeaveRequest AS l
        WHERE l.EmployeeID = e.EmployeeID
          AND l.LeaveType = t.LeaveType
          AND l.Status = N'Approved'
          AND YEAR(l.StartDate) = @Year
    ) AS u;
GO

/* ---------------------------------------------------------------------
   Views
   --------------------------------------------------------------------- */

-- Employee directory: employee + department + plant + manager in one row.
CREATE OR ALTER VIEW dbo.vw_EmployeeDirectory
AS
SELECT e.EmployeeID,
       e.FirstName + N' ' + e.LastName AS EmployeeName,
       e.Email,
       CASE WHEN dbo.fn_IsManager(e.EmployeeID) = 1 THEN N'Manager' ELSE N'Employee' END AS Role,
       d.DepartmentID, d.DepartmentName,
       p.PlantID, p.PlantName, p.City,
       e.ManagerID,
       m.FirstName + N' ' + m.LastName AS ManagerName,
       e.HireDate, e.Salary
FROM dbo.Employee AS e
LEFT JOIN dbo.Department AS d ON d.DepartmentID = e.DepartmentID
LEFT JOIN dbo.Plant      AS p ON p.PlantID      = d.PlantID
LEFT JOIN dbo.Employee   AS m ON m.EmployeeID   = e.ManagerID;
GO

-- Reporting hierarchy with level and full path (recursive CTE inside a view).
CREATE OR ALTER VIEW dbo.vw_ReportingHierarchy
AS
WITH Hierarchy AS
(
    SELECT EmployeeID, ManagerID, FirstName + N' ' + LastName AS EmployeeName, 0 AS Level,
           CAST(FirstName + N' ' + LastName AS NVARCHAR(1000)) AS ReportingPath
    FROM dbo.Employee
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.ManagerID, e.FirstName + N' ' + e.LastName, h.Level + 1,
           CAST(h.ReportingPath + N' > ' + e.FirstName + N' ' + e.LastName AS NVARCHAR(1000))
    FROM dbo.Employee AS e
    JOIN Hierarchy AS h ON e.ManagerID = h.EmployeeID
)
SELECT EmployeeID, ManagerID, EmployeeName, Level, ReportingPath FROM Hierarchy;
GO

-- Report: departments by headcount.
CREATE OR ALTER VIEW dbo.vw_DepartmentHeadcount
AS
SELECT d.DepartmentID, d.DepartmentName, p.PlantName, COUNT(e.EmployeeID) AS Headcount
FROM dbo.Department AS d
LEFT JOIN dbo.Plant    AS p ON p.PlantID = d.PlantID
LEFT JOIN dbo.Employee AS e ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentID, d.DepartmentName, p.PlantName;
GO

-- Report: salary distribution by department.
CREATE OR ALTER VIEW dbo.vw_SalaryDistributionByDepartment
AS
SELECT d.DepartmentID, d.DepartmentName,
       COUNT(*) AS Headcount,
       MIN(e.Salary) AS MinSalary,
       MAX(e.Salary) AS MaxSalary,
       CAST(AVG(e.Salary) AS DECIMAL(12,2)) AS AvgSalary
FROM dbo.Employee AS e
JOIN dbo.Department AS d ON d.DepartmentID = e.DepartmentID
GROUP BY d.DepartmentID, d.DepartmentName;
GO

-- Report: employees on leave today (approved leave covering today's date).
CREATE OR ALTER VIEW dbo.vw_EmployeesOnLeaveToday
AS
SELECT l.LeaveID, e.EmployeeID, e.FirstName + N' ' + e.LastName AS EmployeeName,
       l.LeaveType, l.StartDate, l.EndDate
FROM dbo.LeaveRequest AS l
JOIN dbo.Employee AS e ON e.EmployeeID = l.EmployeeID
WHERE l.Status = N'Approved'
  AND CAST(GETDATE() AS DATE) BETWEEN l.StartDate AND l.EndDate;
GO

-- Report: pending leave approvals with the approving manager.
CREATE OR ALTER VIEW dbo.vw_PendingLeaveApprovals
AS
SELECT l.LeaveID, e.EmployeeID, e.FirstName + N' ' + e.LastName AS EmployeeName,
       e.ManagerID, m.FirstName + N' ' + m.LastName AS ManagerName,
       l.LeaveType, l.StartDate, l.EndDate,
       dbo.fn_WorkingDays(l.StartDate, l.EndDate) AS WorkingDays
FROM dbo.LeaveRequest AS l
JOIN dbo.Employee AS e ON e.EmployeeID = l.EmployeeID
LEFT JOIN dbo.Employee AS m ON m.EmployeeID = e.ManagerID
WHERE l.Status = N'Pending';
GO

-- Leave balance for the current year (wraps the table-valued function).
CREATE OR ALTER VIEW dbo.vw_LeaveBalanceCurrentYear
AS
SELECT * FROM dbo.fn_LeaveBalance(YEAR(GETDATE()));
GO

-- Report: review cycle completion per year.
CREATE OR ALTER VIEW dbo.vw_ReviewCycleCompletion
AS
SELECT c.ReviewCycle,
       COUNT(DISTINCT r.EmployeeID) AS EmployeesReviewed,
       (SELECT COUNT(*) FROM dbo.Employee) AS TotalEmployees,
       CAST(100.0 * COUNT(DISTINCT r.EmployeeID) / NULLIF((SELECT COUNT(*) FROM dbo.Employee), 0) AS DECIMAL(5,2)) AS CompletionPct,
       CAST(AVG(CAST(r.Rating AS DECIMAL(4,2))) AS DECIMAL(4,2)) AS AvgRating
FROM (SELECT DISTINCT YEAR(ReviewDate) AS ReviewCycle FROM dbo.PerformanceReview) AS c
JOIN dbo.PerformanceReview AS r ON YEAR(r.ReviewDate) = c.ReviewCycle
GROUP BY c.ReviewCycle;
GO

-- Report: monthly payroll inputs aggregated from timesheets.
CREATE OR ALTER VIEW dbo.vw_MonthlyTimesheetSummary
AS
SELECT t.EmployeeID, e.FirstName + N' ' + e.LastName AS EmployeeName, e.DepartmentID,
       YEAR(t.WorkDate) AS PeriodYear, MONTH(t.WorkDate) AS PeriodMonth,
       COUNT(*) AS DaysWorked,
       SUM(t.HoursWorked) AS TotalHours,
       SUM(t.OvertimeHours) AS OvertimeHours
FROM dbo.Timesheet AS t
JOIN dbo.Employee AS e ON e.EmployeeID = t.EmployeeID
GROUP BY t.EmployeeID, e.FirstName, e.LastName, e.DepartmentID, YEAR(t.WorkDate), MONTH(t.WorkDate);
GO

-- Report: average overtime per timesheet entry by department and month.
CREATE OR ALTER VIEW dbo.vw_AverageOvertimeByDepartment
AS
SELECT d.DepartmentID, d.DepartmentName,
       YEAR(t.WorkDate) AS PeriodYear, MONTH(t.WorkDate) AS PeriodMonth,
       CAST(AVG(t.OvertimeHours) AS DECIMAL(5,2)) AS AvgOvertimeHours
FROM dbo.Timesheet AS t
JOIN dbo.Employee   AS e ON e.EmployeeID = t.EmployeeID
JOIN dbo.Department AS d ON d.DepartmentID = e.DepartmentID
GROUP BY d.DepartmentID, d.DepartmentName, YEAR(t.WorkDate), MONTH(t.WorkDate);
GO

PRINT 'Functions and views created.';
GO
