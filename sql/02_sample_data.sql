/* =====================================================================
   WorkHub - Employee and HR Management System
   Sprint 1 : Sample data (SQL Server)
   Script   : 02_sample_data.sql
   >= 10 rows in every table; Timesheet (highest volume) gets ~1,700 rows.
   Every foreign key relationship is respected.
   ===================================================================== */

USE WorkHubDB;
GO
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   Plant (10 rows) - four manufacturing plants + supporting sites
   --------------------------------------------------------------------- */
SET IDENTITY_INSERT dbo.Plant ON;
INSERT INTO dbo.Plant (PlantID, PlantName, City) VALUES
 (1,  N'Ferrovia Pune Works',          N'Pune'),
 (2,  N'Ferrovia Chennai Works',       N'Chennai'),
 (3,  N'Ferrovia Coimbatore Works',    N'Coimbatore'),
 (4,  N'Ferrovia Vadodara Works',      N'Vadodara'),
 (5,  N'Ferrovia Corporate HQ',        N'Mumbai'),
 (6,  N'Ferrovia R&D Centre',          N'Bengaluru'),
 (7,  N'Ferrovia North Warehouse',     N'Gurugram'),
 (8,  N'Ferrovia South Warehouse',     N'Hosur'),
 (9,  N'Ferrovia East Logistics Hub',  N'Kolkata'),
 (10, N'Ferrovia Training Centre',     N'Hyderabad');
SET IDENTITY_INSERT dbo.Plant OFF;
GO

/* ---------------------------------------------------------------------
   Department (12 rows)
   --------------------------------------------------------------------- */
SET IDENTITY_INSERT dbo.Department ON;
INSERT INTO dbo.Department (DepartmentID, DepartmentName, PlantID) VALUES
 (1,  N'Human Resources',            5),
 (2,  N'Finance & Payroll',          5),
 (3,  N'Production - Pune',          1),
 (4,  N'Quality Assurance - Pune',   1),
 (5,  N'Production - Chennai',       2),
 (6,  N'Maintenance - Chennai',      2),
 (7,  N'Production - Coimbatore',    3),
 (8,  N'Production - Vadodara',      4),
 (9,  N'Research & Development',     6),
 (10, N'Supply Chain',               7),
 (11, N'Logistics',                  9),
 (12, N'Learning & Development',     10);
SET IDENTITY_INSERT dbo.Department OFF;
GO

/* ---------------------------------------------------------------------
   Employee (30 rows) - managers are listed before their reports.
   Reporting hierarchy:
     1 Arjun Mehta (HR Director, top of hierarchy)
       |- 2 Priya Nair  -> 20, 26
       |- 3 Rahul Verma -> 21, 22
       |- 4 Sneha Iyer  -> 9, 10, 11, 28
       |- 5 Karthik Raman -> 12, 13, 14, 27
       |- 6 Ananya Desai -> 15, 16, 30
       |- 7 Vikram Singh -> 17, 29
       |- 8 Meera Pillai -> 18, 19
       |- 23 Manoj Tiwari -> 24, 25
   --------------------------------------------------------------------- */
SET IDENTITY_INSERT dbo.Employee ON;
INSERT INTO dbo.Employee (EmployeeID, FirstName, LastName, Email, DepartmentID, ManagerID, HireDate, Salary) VALUES
 (1,  N'Arjun',    N'Mehta',       N'arjun.mehta@ferrovia.com',          1,  NULL, '2012-04-02', 3200000.00),
 (2,  N'Priya',    N'Nair',        N'priya.nair@ferrovia.com',           1,  1,    '2015-06-15', 1450000.00),
 (3,  N'Rahul',    N'Verma',       N'rahul.verma@ferrovia.com',          2,  1,    '2014-01-20', 1800000.00),
 (4,  N'Sneha',    N'Iyer',        N'sneha.iyer@ferrovia.com',           3,  1,    '2016-03-01', 1650000.00),
 (5,  N'Karthik',  N'Raman',       N'karthik.raman@ferrovia.com',        5,  1,    '2013-09-09', 1600000.00),
 (6,  N'Ananya',   N'Desai',       N'ananya.desai@ferrovia.com',         9,  1,    '2017-11-13', 1900000.00),
 (7,  N'Vikram',   N'Singh',       N'vikram.singh@ferrovia.com',         7,  1,    '2015-02-23', 1550000.00),
 (8,  N'Meera',    N'Pillai',      N'meera.pillai@ferrovia.com',         8,  1,    '2018-07-30', 1500000.00),
 (9,  N'Rohan',    N'Kulkarni',    N'rohan.kulkarni@ferrovia.com',       3,  4,    '2019-05-06',  620000.00),
 (10, N'Divya',    N'Menon',       N'divya.menon@ferrovia.com',          4,  4,    '2020-08-17',  680000.00),
 (11, N'Aditya',   N'Joshi',       N'aditya.joshi@ferrovia.com',         3,  4,    '2021-01-11',  540000.00),
 (12, N'Lakshmi',  N'Subramanian', N'lakshmi.subramanian@ferrovia.com',  5,  5,    '2019-10-01',  590000.00),
 (13, N'Suresh',   N'Babu',        N'suresh.babu@ferrovia.com',          6,  5,    '2018-12-03',  610000.00),
 (14, N'Fatima',   N'Sheikh',      N'fatima.sheikh@ferrovia.com',        5,  5,    '2022-02-14',  560000.00),
 (15, N'Nikhil',   N'Patil',       N'nikhil.patil@ferrovia.com',         9,  6,    '2019-04-22', 1150000.00),
 (16, N'Kavya',    N'Reddy',       N'kavya.reddy@ferrovia.com',          9,  6,    '2020-06-08', 1080000.00),
 (17, N'Ganesh',   N'Murugan',     N'ganesh.murugan@ferrovia.com',       7,  7,    '2021-09-27',  520000.00),
 (18, N'Pooja',    N'Shah',        N'pooja.shah@ferrovia.com',           8,  8,    '2020-03-16',  575000.00),
 (19, N'Imran',    N'Khan',        N'imran.khan@ferrovia.com',           8,  8,    '2022-07-04',  530000.00),
 (20, N'Neha',     N'Gupta',       N'neha.gupta@ferrovia.com',           1,  2,    '2021-11-29',  720000.00),
 (21, N'Siddharth',N'Rao',         N'siddharth.rao@ferrovia.com',        2,  3,    '2018-05-14',  860000.00),
 (22, N'Ritu',     N'Agarwal',     N'ritu.agarwal@ferrovia.com',         2,  3,    '2020-10-19',  790000.00),
 (23, N'Manoj',    N'Tiwari',      N'manoj.tiwari@ferrovia.com',         10, 1,    '2016-08-08',  980000.00),
 (24, N'Deepa',    N'Krishnan',    N'deepa.krishnan@ferrovia.com',       10, 23,   '2021-03-22',  610000.00),
 (25, N'Arvind',   N'Chauhan',     N'arvind.chauhan@ferrovia.com',       11, 23,   '2022-01-10',  580000.00),
 (26, N'Swati',    N'Bhatt',       N'swati.bhatt@ferrovia.com',          12, 2,    '2019-07-01',  700000.00),
 (27, N'Harish',   N'Kumar',       N'harish.kumar@ferrovia.com',         6,  5,    '2017-04-17',  600000.00),
 (28, N'Ishita',   N'Banerjee',    N'ishita.banerjee@ferrovia.com',      4,  4,    '2023-02-06',  650000.00),
 (29, N'Tarun',    N'Malhotra',    N'tarun.malhotra@ferrovia.com',       7,  7,    '2023-06-12',  515000.00),
 (30, N'Zoya',     N'Fernandes',   N'zoya.fernandes@ferrovia.com',       9,  6,    '2022-09-05', 1020000.00);
SET IDENTITY_INSERT dbo.Employee OFF;
GO

/* ---------------------------------------------------------------------
   LeaveRequest (30 rows) - mix of Approved / Pending / Rejected
   --------------------------------------------------------------------- */
INSERT INTO dbo.LeaveRequest (EmployeeID, LeaveType, StartDate, EndDate, Status) VALUES
 (9,  N'Annual', '2026-03-09', '2026-03-13', N'Approved'),
 (9,  N'Sick',   '2026-07-02', '2026-07-03', N'Approved'),
 (9,  N'Annual', '2026-12-21', '2026-12-24', N'Pending'),
 (10, N'Casual', '2026-05-18', '2026-05-18', N'Approved'),
 (10, N'Annual', '2026-12-28', '2026-12-31', N'Pending'),
 (11, N'Annual', '2026-08-10', '2026-08-14', N'Rejected'),
 (11, N'Sick',   '2026-11-23', '2026-11-24', N'Pending'),
 (12, N'Annual', '2026-11-16', '2026-11-20', N'Approved'),
 (13, N'Casual', '2026-02-06', '2026-02-06', N'Approved'),
 (13, N'Annual', '2026-12-14', '2026-12-18', N'Pending'),
 (14, N'Sick',   '2026-04-13', '2026-04-15', N'Approved'),
 (15, N'Annual', '2026-06-01', '2026-06-12', N'Approved'),
 (15, N'Casual', '2026-11-27', '2026-11-27', N'Pending'),
 (16, N'Annual', '2026-10-05', '2026-10-09', N'Approved'),
 (17, N'Sick',   '2026-09-14', '2026-09-15', N'Approved'),
 (17, N'Annual', '2026-12-07', '2026-12-11', N'Pending'),
 (18, N'Sick',   '2026-11-19', '2026-11-20', N'Approved'),
 (19, N'Annual', '2026-01-19', '2026-01-23', N'Approved'),
 (20, N'Casual', '2026-03-27', '2026-03-27', N'Approved'),
 (20, N'Annual', '2026-12-22', '2026-12-31', N'Pending'),
 (21, N'Annual', '2026-04-20', '2026-04-30', N'Approved'),
 (22, N'Sick',   '2026-08-24', '2026-08-25', N'Rejected'),
 (24, N'Annual', '2026-07-13', '2026-07-17', N'Approved'),
 (25, N'Casual', '2026-11-18', '2026-11-19', N'Approved'),
 (26, N'Annual', '2026-09-21', '2026-09-25', N'Approved'),
 (27, N'Unpaid', '2026-05-04', '2026-05-15', N'Approved'),
 (28, N'Annual', '2026-12-01', '2026-12-04', N'Pending'),
 (29, N'Sick',   '2026-10-26', '2026-10-27', N'Approved'),
 (30, N'Annual', '2026-02-16', '2026-02-20', N'Approved'),
 (4,  N'Annual', '2026-11-30', '2026-12-04', N'Pending');
GO

/* ---------------------------------------------------------------------
   Timesheet (highest-volume table) - one row per employee per weekday
   from 2026-09-01 to 2026-11-18  =>  30 employees x 57 weekdays = 1,710 rows.
   Overtime is a deterministic 0.0 - 2.0 h pattern; HoursWorked = 8 + overtime.
   Weekday test uses 1900-01-01 (a Monday) so it does not depend on DATEFIRST.
   --------------------------------------------------------------------- */
;WITH Days AS
(
    SELECT CAST('2026-09-01' AS DATE) AS WorkDate
    UNION ALL
    SELECT DATEADD(DAY, 1, WorkDate) FROM Days WHERE WorkDate < '2026-11-18'
),
Overtime AS
(
    SELECT e.EmployeeID,
           d.WorkDate,
           CAST(((e.EmployeeID * 7 + DAY(d.WorkDate) * 3) % 5) * 0.5 AS DECIMAL(4,2)) AS OT
    FROM dbo.Employee AS e
    CROSS JOIN Days AS d
    WHERE DATEDIFF(DAY, '19000101', d.WorkDate) % 7 < 5
)
INSERT INTO dbo.Timesheet (EmployeeID, WorkDate, HoursWorked, OvertimeHours)
SELECT EmployeeID, WorkDate, 8 + OT, OT
FROM Overtime
OPTION (MAXRECURSION 200);
GO

/* ---------------------------------------------------------------------
   PerformanceReview (32 rows) - 2025 cycle complete, 2026 cycle partial.
   ReviewerID is the employee's manager.
   --------------------------------------------------------------------- */
INSERT INTO dbo.PerformanceReview (EmployeeID, ReviewerID, ReviewDate, Rating, Comments) VALUES
 (2,  1, '2025-12-10', 5, N'Led the HR digitisation programme.'),
 (3,  1, '2025-12-10', 4, N'Closed the year with clean audits.'),
 (4,  1, '2025-12-11', 4, N'Pune output up 8 percent.'),
 (5,  1, '2025-12-11', 3, N'Chennai downtime still above target.'),
 (6,  1, '2025-12-12', 5, N'Two patents filed.'),
 (7,  1, '2025-12-12', 4, N'Strong safety record.'),
 (8,  1, '2025-12-15', 3, N'Needs better shift planning.'),
 (9,  4, '2025-12-16', 4, N'Reliable line supervisor.'),
 (10, 4, '2025-12-16', 5, N'Reduced defect rate significantly.'),
 (11, 4, '2025-12-17', 3, N'Developing well.'),
 (12, 5, '2025-12-17', 4, N'Good teamwork.'),
 (13, 5, '2025-12-18', 2, N'Missed several preventive maintenance windows.'),
 (15, 6, '2025-12-18', 5, N'Excellent research output.'),
 (16, 6, '2025-12-19', 4, N'Strong prototype delivery.'),
 (17, 7, '2025-12-19', 3, N'Meets expectations.'),
 (18, 8, '2025-12-22', 4, N'Consistent quality.'),
 (21, 3, '2025-12-22', 4, N'Accurate payroll processing.'),
 (23, 1, '2025-12-23', 4, N'Supplier lead times reduced.'),
 (2,  1, '2026-10-12', 4, N'Mid-year check-in completed.'),
 (4,  1, '2026-10-13', 5, N'Plant expansion delivered on time.'),
 (6,  1, '2026-10-14', 4, N'R&D roadmap on track.'),
 (9,  4, '2026-10-15', 3, N'Needs to mentor juniors more.'),
 (10, 4, '2026-10-15', 5, N'Quality lead for the ISO audit.'),
 (12, 5, '2026-10-16', 4, N'Improved changeover times.'),
 (15, 6, '2026-10-19', 5, N'Outstanding work on the new alloy.'),
 (16, 6, '2026-10-19', 4, N'Solid contributor.'),
 (18, 8, '2026-10-20', 3, N'Average quarter.'),
 (20, 2, '2026-10-21', 4, N'Recruitment drive success.'),
 (21, 3, '2026-10-21', 5, N'Automated month-end close.'),
 (24, 23, '2026-10-22', 4, N'Inventory accuracy improved.'),
 (26, 2, '2026-10-23', 4, N'Training calendar delivered.'),
 (30, 6, '2026-10-26', 5, N'Excellent simulation models.');
GO

/* Row counts */
SELECT 'Plant' AS TableName, COUNT(*) AS [Rows] FROM dbo.Plant
UNION ALL SELECT 'Department', COUNT(*) FROM dbo.Department
UNION ALL SELECT 'Employee', COUNT(*) FROM dbo.Employee
UNION ALL SELECT 'LeaveRequest', COUNT(*) FROM dbo.LeaveRequest
UNION ALL SELECT 'Timesheet', COUNT(*) FROM dbo.Timesheet
UNION ALL SELECT 'PerformanceReview', COUNT(*) FROM dbo.PerformanceReview;
GO
