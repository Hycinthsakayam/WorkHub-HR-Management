/* =====================================================================
   WorkHub - Stage 1 consolidation : audit tables and triggers
   Script : 07_triggers.sql                 Run after 06.
   Re-runnable.

   Triggers enforce the cross-row rules that a CHECK constraint cannot
   express (a CHECK only sees one row) and keep an audit trail:
     trg_LeaveRequest_Audit          every insert / status change / delete -> LeaveRequestAudit
     trg_LeaveRequest_NoOverlap      no two APPROVED leaves of one employee may overlap   (50001)
     trg_Timesheet_DailyLimit        total hours per employee per day <= 24               (50003)
     trg_PerformanceReview_OnePerCycle  one review per employee per calendar year         (50005)
     trg_Employee_NoCircularManager  no reporting cycles (A > B > A)                      (50007)
     trg_Employee_SalaryHistory      every salary change -> SalaryHistory (auditable payroll)
   ===================================================================== */

USE WorkHubDB;
GO

/* ---------------------------------------------------------------------
   Audit tables
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.LeaveRequestAudit', N'U') IS NULL
CREATE TABLE dbo.LeaveRequestAudit
(
    AuditID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LeaveRequestAudit PRIMARY KEY,
    LeaveID     INT           NOT NULL,
    EmployeeID  INT           NOT NULL,
    Action      NVARCHAR(10)  NOT NULL CONSTRAINT CK_LeaveRequestAudit_Action CHECK (Action IN (N'INSERT', N'UPDATE', N'DELETE')),
    OldStatus   NVARCHAR(20)  NULL,
    NewStatus   NVARCHAR(20)  NULL,
    ChangedAt   DATETIME2(0)  NOT NULL CONSTRAINT DF_LeaveRequestAudit_ChangedAt DEFAULT (SYSDATETIME()),
    ChangedBy   NVARCHAR(128) NOT NULL CONSTRAINT DF_LeaveRequestAudit_ChangedBy DEFAULT (SUSER_SNAME())
);
GO

IF OBJECT_ID(N'dbo.SalaryHistory', N'U') IS NULL
CREATE TABLE dbo.SalaryHistory
(
    SalaryHistoryID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalaryHistory PRIMARY KEY,
    EmployeeID      INT           NOT NULL,
    OldSalary       DECIMAL(12,2) NOT NULL,
    NewSalary       DECIMAL(12,2) NOT NULL,
    ChangedAt       DATETIME2(0)  NOT NULL CONSTRAINT DF_SalaryHistory_ChangedAt DEFAULT (SYSDATETIME()),
    ChangedBy       NVARCHAR(128) NOT NULL CONSTRAINT DF_SalaryHistory_ChangedBy DEFAULT (SUSER_SNAME())
);
GO

/* ---------------------------------------------------------------------
   1. Leave audit trail
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_LeaveRequest_Audit
ON dbo.LeaveRequest
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    -- INSERT: rows only in inserted
    INSERT INTO dbo.LeaveRequestAudit (LeaveID, EmployeeID, Action, OldStatus, NewStatus)
    SELECT i.LeaveID, i.EmployeeID, N'INSERT', NULL, i.Status
    FROM inserted AS i
    WHERE NOT EXISTS (SELECT 1 FROM deleted);

    -- UPDATE: only when the status actually changed
    INSERT INTO dbo.LeaveRequestAudit (LeaveID, EmployeeID, Action, OldStatus, NewStatus)
    SELECT i.LeaveID, i.EmployeeID, N'UPDATE', d.Status, i.Status
    FROM inserted AS i
    JOIN deleted  AS d ON d.LeaveID = i.LeaveID
    WHERE i.Status <> d.Status;

    -- DELETE: rows only in deleted
    INSERT INTO dbo.LeaveRequestAudit (LeaveID, EmployeeID, Action, OldStatus, NewStatus)
    SELECT d.LeaveID, d.EmployeeID, N'DELETE', d.Status, NULL
    FROM deleted AS d
    WHERE NOT EXISTS (SELECT 1 FROM inserted);
END;
GO

/* ---------------------------------------------------------------------
   2. No overlapping approved leave
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_LeaveRequest_NoOverlap
ON dbo.LeaveRequest
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted AS i
        JOIN dbo.LeaveRequest AS other
          ON other.EmployeeID = i.EmployeeID
         AND other.LeaveID   <> i.LeaveID
         AND other.Status     = N'Approved'
         AND other.StartDate <= i.EndDate
         AND i.StartDate     <= other.EndDate
        WHERE i.Status = N'Approved')
    BEGIN
        ;THROW 50001, N'An approved leave cannot overlap another approved leave of the same employee.', 1;
    END;
END;
GO

/* ---------------------------------------------------------------------
   3. At most 24 hours per employee per day (across all timesheet rows)
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_Timesheet_DailyLimit
ON dbo.Timesheet
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT EmployeeID, WorkDate FROM inserted) AS k
        JOIN dbo.Timesheet AS t ON t.EmployeeID = k.EmployeeID AND t.WorkDate = k.WorkDate
        GROUP BY k.EmployeeID, k.WorkDate
        HAVING SUM(t.HoursWorked) > 24)
    BEGIN
        ;THROW 50003, N'Total hours worked for one employee on one day cannot exceed 24.', 1;
    END;
END;
GO

/* ---------------------------------------------------------------------
   4. One performance review per employee per review cycle (year)
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_PerformanceReview_OnePerCycle
ON dbo.PerformanceReview
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT EmployeeID, YEAR(ReviewDate) AS Cycle FROM inserted) AS k
        JOIN dbo.PerformanceReview AS r ON r.EmployeeID = k.EmployeeID AND YEAR(r.ReviewDate) = k.Cycle
        GROUP BY k.EmployeeID, k.Cycle
        HAVING COUNT(*) > 1)
    BEGIN
        ;THROW 50005, N'An employee can have only one performance review per review cycle.', 1;
    END;
END;
GO

/* ---------------------------------------------------------------------
   5. No circular reporting (walk up from every changed employee)
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_Employee_NoCircularManager
ON dbo.Employee
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(ManagerID) RETURN;

    DECLARE @Cycles INT = 0;
    WITH Chain AS
    (
        SELECT i.EmployeeID AS StartID, e.ManagerID AS CurrentID, 1 AS Depth
        FROM inserted AS i
        JOIN dbo.Employee AS e ON e.EmployeeID = i.EmployeeID
        WHERE e.ManagerID IS NOT NULL
        UNION ALL
        SELECT c.StartID, e.ManagerID, c.Depth + 1
        FROM Chain AS c
        JOIN dbo.Employee AS e ON e.EmployeeID = c.CurrentID
        WHERE e.ManagerID IS NOT NULL AND c.CurrentID <> c.StartID AND c.Depth < 100
    )
    SELECT @Cycles = COUNT(*) FROM Chain WHERE CurrentID = StartID;   -- assigns, returns no rows

    IF @Cycles > 0
    BEGIN
        ;THROW 50007, N'This manager assignment would create a reporting cycle.', 1;
    END;
END;
GO

/* ---------------------------------------------------------------------
   6. Salary history (auditable payroll inputs)
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_Employee_SalaryHistory
ON dbo.Employee
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Salary) RETURN;
    INSERT INTO dbo.SalaryHistory (EmployeeID, OldSalary, NewSalary)
    SELECT i.EmployeeID, d.Salary, i.Salary
    FROM inserted AS i
    JOIN deleted  AS d ON d.EmployeeID = i.EmployeeID
    WHERE i.Salary <> d.Salary;
END;
GO

PRINT 'Audit tables and triggers created.';
GO
