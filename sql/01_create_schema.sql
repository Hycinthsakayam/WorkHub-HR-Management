/* =====================================================================
   WorkHub - Employee and HR Management System
   Sprint 1 : Database schema (SQL Server)
   Script   : 01_create_schema.sql
   Creates the WorkHubDB database and its six tables with primary keys,
   foreign keys, unique / check / default constraints and indexes.
   Run in SSMS (or: sqlcmd -S localhost\SQLEXPRESS -E -C -i 01_create_schema.sql)
   ===================================================================== */

USE master;
GO

IF DB_ID(N'WorkHubDB') IS NOT NULL
BEGIN
    ALTER DATABASE WorkHubDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE WorkHubDB;
END
GO

CREATE DATABASE WorkHubDB;
GO

USE WorkHubDB;
GO

/* ---------------------------------------------------------------------
   1. Plant
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Plant
(
    PlantID     INT IDENTITY(1,1) NOT NULL,
    PlantName   NVARCHAR(100)     NOT NULL,
    City        NVARCHAR(50)      NOT NULL,
    CONSTRAINT PK_Plant PRIMARY KEY (PlantID),
    CONSTRAINT UQ_Plant_PlantName UNIQUE (PlantName)
);
GO

/* ---------------------------------------------------------------------
   2. Department  (Department.PlantID -> Plant)
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Department
(
    DepartmentID    INT IDENTITY(1,1) NOT NULL,
    DepartmentName  NVARCHAR(100)     NOT NULL,
    PlantID         INT               NULL,
    CONSTRAINT PK_Department PRIMARY KEY (DepartmentID),
    CONSTRAINT FK_Department_Plant FOREIGN KEY (PlantID)
        REFERENCES dbo.Plant (PlantID)
);
GO

/* ---------------------------------------------------------------------
   3. Employee  (DepartmentID -> Department, ManagerID -> Employee)
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Employee
(
    EmployeeID      INT IDENTITY(1,1) NOT NULL,
    FirstName       NVARCHAR(50)      NOT NULL,
    LastName        NVARCHAR(50)      NOT NULL,
    Email           NVARCHAR(100)     NOT NULL,
    DepartmentID    INT               NULL,
    ManagerID       INT               NULL,
    HireDate        DATE              NOT NULL,
    Salary          DECIMAL(12,2)     NOT NULL,
    CONSTRAINT PK_Employee PRIMARY KEY (EmployeeID),
    CONSTRAINT UQ_Employee_Email UNIQUE (Email),
    CONSTRAINT CK_Employee_Salary CHECK (Salary >= 0),
    CONSTRAINT CK_Employee_NotOwnManager CHECK (ManagerID IS NULL OR ManagerID <> EmployeeID),
    CONSTRAINT FK_Employee_Department FOREIGN KEY (DepartmentID)
        REFERENCES dbo.Department (DepartmentID),
    CONSTRAINT FK_Employee_Manager FOREIGN KEY (ManagerID)
        REFERENCES dbo.Employee (EmployeeID)
);
GO

/* ---------------------------------------------------------------------
   4. LeaveRequest  (EmployeeID -> Employee, many-to-one)
   --------------------------------------------------------------------- */
CREATE TABLE dbo.LeaveRequest
(
    LeaveID     INT IDENTITY(1,1) NOT NULL,
    EmployeeID  INT               NOT NULL,
    LeaveType   NVARCHAR(30)      NOT NULL,
    StartDate   DATE              NOT NULL,
    EndDate     DATE              NOT NULL,
    Status      NVARCHAR(20)      NOT NULL CONSTRAINT DF_LeaveRequest_Status DEFAULT (N'Pending'),
    CONSTRAINT PK_LeaveRequest PRIMARY KEY (LeaveID),
    CONSTRAINT FK_LeaveRequest_Employee FOREIGN KEY (EmployeeID)
        REFERENCES dbo.Employee (EmployeeID) ON DELETE CASCADE,
    CONSTRAINT CK_LeaveRequest_Dates CHECK (EndDate >= StartDate),
    CONSTRAINT CK_LeaveRequest_Status CHECK (Status IN (N'Pending', N'Approved', N'Rejected', N'Cancelled')),
    CONSTRAINT CK_LeaveRequest_Type CHECK (LeaveType IN (N'Annual', N'Sick', N'Casual', N'Unpaid'))
);
GO

/* ---------------------------------------------------------------------
   5. Timesheet  (EmployeeID -> Employee, many-to-one)
   --------------------------------------------------------------------- */
CREATE TABLE dbo.Timesheet
(
    TimesheetID     INT IDENTITY(1,1) NOT NULL,
    EmployeeID      INT               NOT NULL,
    WorkDate        DATE              NOT NULL,
    HoursWorked     DECIMAL(4,2)      NOT NULL,
    OvertimeHours   DECIMAL(4,2)      NOT NULL CONSTRAINT DF_Timesheet_Overtime DEFAULT (0),
    CONSTRAINT PK_Timesheet PRIMARY KEY (TimesheetID),
    CONSTRAINT FK_Timesheet_Employee FOREIGN KEY (EmployeeID)
        REFERENCES dbo.Employee (EmployeeID) ON DELETE CASCADE,
    CONSTRAINT CK_Timesheet_Hours CHECK (HoursWorked >= 0 AND HoursWorked <= 24),
    CONSTRAINT CK_Timesheet_Overtime CHECK (OvertimeHours >= 0)
);
GO

/* ---------------------------------------------------------------------
   6. PerformanceReview  (EmployeeID -> Employee, ReviewerID -> Employee)
   --------------------------------------------------------------------- */
CREATE TABLE dbo.PerformanceReview
(
    ReviewID    INT IDENTITY(1,1) NOT NULL,
    EmployeeID  INT               NOT NULL,
    ReviewerID  INT               NULL,
    ReviewDate  DATE              NOT NULL,
    Rating      INT               NOT NULL,
    Comments    NVARCHAR(500)     NULL,
    CONSTRAINT PK_PerformanceReview PRIMARY KEY (ReviewID),
    CONSTRAINT FK_PerformanceReview_Employee FOREIGN KEY (EmployeeID)
        REFERENCES dbo.Employee (EmployeeID) ON DELETE CASCADE,
    -- NO ACTION: SQL Server forbids a second cascade path to Employee.
    -- EmployeeService.delete_employee() clears ReviewerID inside its transaction.
    CONSTRAINT FK_PerformanceReview_Reviewer FOREIGN KEY (ReviewerID)
        REFERENCES dbo.Employee (EmployeeID),
    CONSTRAINT CK_PerformanceReview_Rating CHECK (Rating BETWEEN 1 AND 5)
);
GO

/* ---------------------------------------------------------------------
   Indexes on foreign keys / frequent filters
   --------------------------------------------------------------------- */
CREATE INDEX IX_Department_PlantID          ON dbo.Department (PlantID);
CREATE INDEX IX_Employee_DepartmentID       ON dbo.Employee (DepartmentID);
CREATE INDEX IX_Employee_ManagerID          ON dbo.Employee (ManagerID);
CREATE INDEX IX_LeaveRequest_Employee       ON dbo.LeaveRequest (EmployeeID, Status);
CREATE INDEX IX_Timesheet_Employee_Date     ON dbo.Timesheet (EmployeeID, WorkDate);
CREATE INDEX IX_PerformanceReview_Employee  ON dbo.PerformanceReview (EmployeeID, ReviewDate);
GO

PRINT 'WorkHubDB schema created successfully.';
GO
