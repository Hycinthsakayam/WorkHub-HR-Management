/* =====================================================================
   WorkHub - Useful queries for SSMS (reporting hierarchy, HR analytics)
   Script : 04_reporting_queries.sql
   ===================================================================== */

USE WorkHubDB;
GO

/* 1. Full reporting hierarchy (recursive CTE) */
;WITH Hierarchy AS
(
    SELECT EmployeeID, ManagerID, FirstName + N' ' + LastName AS FullName,
           0 AS Level, CAST(FirstName + N' ' + LastName AS NVARCHAR(1000)) AS ReportingPath
    FROM dbo.Employee
    WHERE ManagerID IS NULL
    UNION ALL
    SELECT e.EmployeeID, e.ManagerID, e.FirstName + N' ' + e.LastName,
           h.Level + 1, CAST(h.ReportingPath + N' > ' + e.FirstName + N' ' + e.LastName AS NVARCHAR(1000))
    FROM dbo.Employee AS e
    JOIN Hierarchy AS h ON e.ManagerID = h.EmployeeID
)
SELECT EmployeeID, ManagerID, Level, REPLICATE(N'    ', Level) + FullName AS Employee, ReportingPath
FROM Hierarchy
ORDER BY ReportingPath;
GO

/* 2. Headcount by department and plant */
SELECT p.PlantName, d.DepartmentName, COUNT(e.EmployeeID) AS Headcount
FROM dbo.Department AS d
JOIN dbo.Plant AS p ON p.PlantID = d.PlantID
LEFT JOIN dbo.Employee AS e ON e.DepartmentID = d.DepartmentID
GROUP BY p.PlantName, d.DepartmentName
ORDER BY Headcount DESC;
GO

/* 3. Monthly payroll inputs aggregated from timesheets (October 2026) */
SELECT e.EmployeeID, e.FirstName + N' ' + e.LastName AS Employee,
       COUNT(t.TimesheetID) AS DaysWorked,
       SUM(t.HoursWorked)   AS TotalHours,
       SUM(t.OvertimeHours) AS OvertimeHours
FROM dbo.Employee AS e
LEFT JOIN dbo.Timesheet AS t
       ON t.EmployeeID = e.EmployeeID
      AND t.WorkDate >= '2026-10-01' AND t.WorkDate < '2026-11-01'
GROUP BY e.EmployeeID, e.FirstName, e.LastName
ORDER BY e.EmployeeID;
GO

/* 4. Review cycle completion for 2026 */
SELECT COUNT(DISTINCT r.EmployeeID) AS Reviewed,
       (SELECT COUNT(*) FROM dbo.Employee) AS TotalEmployees,
       CAST(100.0 * COUNT(DISTINCT r.EmployeeID) / (SELECT COUNT(*) FROM dbo.Employee) AS DECIMAL(5,2)) AS CompletionPct
FROM dbo.PerformanceReview AS r
WHERE YEAR(r.ReviewDate) = 2026;
GO

/* 5. Pending leave approvals per manager */
SELECT m.EmployeeID AS ManagerID, m.FirstName + N' ' + m.LastName AS Manager,
       l.LeaveID, e.FirstName + N' ' + e.LastName AS Employee, l.LeaveType, l.StartDate, l.EndDate
FROM dbo.LeaveRequest AS l
JOIN dbo.Employee AS e ON e.EmployeeID = l.EmployeeID
JOIN dbo.Employee AS m ON m.EmployeeID = e.ManagerID
WHERE l.Status = N'Pending'
ORDER BY m.EmployeeID, l.StartDate;
GO
