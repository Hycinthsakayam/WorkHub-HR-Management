/* =====================================================================
   WorkHub - Stage 1 consolidation : stored procedures
   Script : 06_stored_procedures.sql        Run after 05.
   Re-runnable (CREATE OR ALTER).

   Business errors are raised with THROW and fixed error numbers that match
   the seven Python exceptions, so the application and the database speak
   the same language:
     50001 InvalidLeaveRequest      50005 DuplicateReview
     50002 InsufficientLeaveBalance 50006 EmployeeNotFound
     50003 InvalidTimesheet         50007 CircularReporting
     50004 UnauthorizedApproval     50000 general validation (e.g. rating 1-5)
   ===================================================================== */

USE WorkHubDB;
GO

/* =====================================================================
   Lookups
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_GetEmployeeById
    @EmployeeID INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID)
    BEGIN
        DECLARE @Msg NVARCHAR(200) = CONCAT(N'Employee with ID ', @EmployeeID, N' was not found.');
        THROW 50006, @Msg, 1;
    END;
    SELECT * FROM dbo.vw_EmployeeDirectory WHERE EmployeeID = @EmployeeID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetLeaveBalance
    @EmployeeID INT,
    @Year       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID)
    BEGIN
        DECLARE @Msg NVARCHAR(200) = CONCAT(N'Employee with ID ', @EmployeeID, N' was not found.');
        THROW 50006, @Msg, 1;
    END;
    SET @Year = ISNULL(@Year, YEAR(GETDATE()));
    SELECT LeaveType, Entitlement, UsedDays, RemainingDays
    FROM dbo.fn_LeaveBalance(@Year)
    WHERE EmployeeID = @EmployeeID;
END;
GO

/* =====================================================================
   Leave workflow
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_RequestLeave
    @EmployeeID INT,
    @LeaveType  NVARCHAR(30),
    @StartDate  DATE,
    @EndDate    DATE,
    @NewLeaveID INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Msg NVARCHAR(400), @Days INT, @Remaining INT;

    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID)
    BEGIN
        SET @Msg = CONCAT(N'Employee with ID ', @EmployeeID, N' was not found.');
        THROW 50006, @Msg, 1;
    END;
    IF @EndDate < @StartDate
    BEGIN
        SET @Msg = CONCAT(N'End date ', @EndDate, N' must not be before start date ', @StartDate, N'.');
        THROW 50001, @Msg, 1;
    END;
    IF EXISTS (SELECT 1 FROM dbo.LeaveRequest
               WHERE EmployeeID = @EmployeeID AND Status = N'Approved'
                 AND StartDate <= @EndDate AND @StartDate <= EndDate)
        THROW 50001, N'Requested leave overlaps an already-approved leave.', 1;

    SET @Days = dbo.fn_WorkingDays(@StartDate, @EndDate);
    IF @Days = 0
        THROW 50001, N'Requested leave contains no working days.', 1;

    SELECT @Remaining = RemainingDays
    FROM dbo.fn_LeaveBalance(YEAR(@StartDate))
    WHERE EmployeeID = @EmployeeID AND LeaveType = @LeaveType;

    IF @Remaining IS NOT NULL AND @Days > @Remaining
    BEGIN
        SET @Msg = CONCAT(N'Insufficient ', @LeaveType, N' leave balance: requested ', @Days,
                          N' day(s), remaining ', @Remaining, N' day(s).');
        THROW 50002, @Msg, 1;
    END;

    INSERT INTO dbo.LeaveRequest (EmployeeID, LeaveType, StartDate, EndDate)   -- Status defaults to Pending
    VALUES (@EmployeeID, @LeaveType, @StartDate, @EndDate);
    SET @NewLeaveID = CAST(SCOPE_IDENTITY() AS INT);
    SELECT @NewLeaveID AS NewLeaveID, @Days AS WorkingDays, @Remaining AS RemainingBeforeApproval;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ApproveLeave
    @LeaveID    INT,
    @ApproverID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @EmployeeID INT, @ManagerID INT, @Status NVARCHAR(20), @Type NVARCHAR(30),
            @Start DATE, @End DATE, @Days INT, @Remaining INT, @Msg NVARCHAR(400);

    SELECT @EmployeeID = l.EmployeeID, @ManagerID = e.ManagerID, @Status = l.Status,
           @Type = l.LeaveType, @Start = l.StartDate, @End = l.EndDate
    FROM dbo.LeaveRequest AS l
    JOIN dbo.Employee AS e ON e.EmployeeID = l.EmployeeID
    WHERE l.LeaveID = @LeaveID;

    IF @EmployeeID IS NULL
    BEGIN
        SET @Msg = CONCAT(N'Leave request with ID ', @LeaveID, N' was not found.');
        THROW 50001, @Msg, 1;
    END;
    IF @ManagerID IS NULL OR @ManagerID <> @ApproverID
    BEGIN
        SET @Msg = CONCAT(N'Employee #', @ApproverID, N' is not the manager of employee #', @EmployeeID,
                          N' and cannot approve this leave request.');
        THROW 50004, @Msg, 1;
    END;
    IF @Status <> N'Pending'
    BEGIN
        SET @Msg = CONCAT(N'Leave request #', @LeaveID, N' is already ', @Status, N'; only a Pending request can be approved.');
        THROW 50001, @Msg, 1;
    END;

    SET @Days = dbo.fn_WorkingDays(@Start, @End);
    SELECT @Remaining = RemainingDays FROM dbo.fn_LeaveBalance(YEAR(@Start))
    WHERE EmployeeID = @EmployeeID AND LeaveType = @Type;
    IF @Remaining IS NOT NULL AND @Days > @Remaining
    BEGIN
        SET @Msg = CONCAT(N'Insufficient ', @Type, N' leave balance: requested ', @Days,
                          N' day(s), remaining ', @Remaining, N' day(s).');
        THROW 50002, @Msg, 1;
    END;

    BEGIN TRANSACTION;
        UPDATE dbo.LeaveRequest SET Status = N'Approved' WHERE LeaveID = @LeaveID;   -- triggers: audit + overlap guard
    COMMIT TRANSACTION;

    SELECT @LeaveID AS LeaveID, N'Approved' AS Status,
           CASE WHEN @Remaining IS NULL THEN NULL ELSE @Remaining - @Days END AS RemainingBalance;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RejectLeave
    @LeaveID    INT,
    @ApproverID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @EmployeeID INT, @ManagerID INT, @Status NVARCHAR(20), @Msg NVARCHAR(400);
    SELECT @EmployeeID = l.EmployeeID, @ManagerID = e.ManagerID, @Status = l.Status
    FROM dbo.LeaveRequest AS l JOIN dbo.Employee AS e ON e.EmployeeID = l.EmployeeID
    WHERE l.LeaveID = @LeaveID;

    IF @EmployeeID IS NULL
    BEGIN
        SET @Msg = CONCAT(N'Leave request with ID ', @LeaveID, N' was not found.');
        THROW 50001, @Msg, 1;
    END;
    IF @ManagerID IS NULL OR @ManagerID <> @ApproverID
    BEGIN
        SET @Msg = CONCAT(N'Employee #', @ApproverID, N' is not the manager of employee #', @EmployeeID, N'.');
        THROW 50004, @Msg, 1;
    END;
    IF @Status <> N'Pending'
        THROW 50001, N'Only a Pending request can be rejected.', 1;

    UPDATE dbo.LeaveRequest SET Status = N'Rejected' WHERE LeaveID = @LeaveID;
    SELECT @LeaveID AS LeaveID, N'Rejected' AS Status;
END;
GO

/* =====================================================================
   Timesheet, review, hierarchy
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_SubmitTimesheet
    @EmployeeID    INT,
    @WorkDate      DATE,
    @HoursWorked   DECIMAL(4,2),
    @OvertimeHours DECIMAL(4,2) = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Msg NVARCHAR(400);
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID)
    BEGIN
        SET @Msg = CONCAT(N'Employee with ID ', @EmployeeID, N' was not found.');
        THROW 50006, @Msg, 1;
    END;
    IF @HoursWorked < 0 OR @HoursWorked > 24
    BEGIN
        SET @Msg = CONCAT(N'Hours worked must be between 0 and 24 for a single day (got ', @HoursWorked, N').');
        THROW 50003, @Msg, 1;
    END;
    IF @OvertimeHours < 0 OR @OvertimeHours > @HoursWorked
        THROW 50003, N'Overtime hours must be between 0 and hours worked.', 1;

    INSERT INTO dbo.Timesheet (EmployeeID, WorkDate, HoursWorked, OvertimeHours)   -- trigger checks the 24 h daily total
    VALUES (@EmployeeID, @WorkDate, @HoursWorked, @OvertimeHours);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewTimesheetID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_SubmitPerformanceReview
    @EmployeeID INT,
    @ReviewerID INT,
    @ReviewDate DATE,
    @Rating     INT,
    @Comments   NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Msg NVARCHAR(400);
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID)
    BEGIN
        SET @Msg = CONCAT(N'Employee with ID ', @EmployeeID, N' was not found.');
        THROW 50006, @Msg, 1;
    END;
    IF @Rating NOT BETWEEN 1 AND 5
        THROW 50000, N'Rating must be between 1 and 5 inclusive.', 1;    -- 50000 = general validation error
    IF EXISTS (SELECT 1 FROM dbo.PerformanceReview
               WHERE EmployeeID = @EmployeeID AND YEAR(ReviewDate) = YEAR(@ReviewDate))
    BEGIN
        SET @Msg = CONCAT(N'Employee #', @EmployeeID, N' already has a review in the ', YEAR(@ReviewDate), N' review cycle.');
        THROW 50005, @Msg, 1;
    END;
    INSERT INTO dbo.PerformanceReview (EmployeeID, ReviewerID, ReviewDate, Rating, Comments)
    VALUES (@EmployeeID, @ReviewerID, @ReviewDate, @Rating, @Comments);
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewReviewID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AssignManager
    @EmployeeID INT,
    @ManagerID  INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Msg NVARCHAR(400);
    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID)
    BEGIN
        SET @Msg = CONCAT(N'Employee with ID ', @EmployeeID, N' was not found.');
        THROW 50006, @Msg, 1;
    END;
    IF @ManagerID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @ManagerID)
    BEGIN
        SET @Msg = CONCAT(N'Employee with ID ', @ManagerID, N' was not found.');
        THROW 50006, @Msg, 1;
    END;
    -- Walk up the chain from the proposed manager; reaching the employee means a cycle.
    DECLARE @Cycle BIT = 0;
    WITH Chain AS
    (
        SELECT EmployeeID, ManagerID, 0 AS Depth FROM dbo.Employee WHERE EmployeeID = @ManagerID
        UNION ALL
        SELECT e.EmployeeID, e.ManagerID, c.Depth + 1
        FROM dbo.Employee AS e JOIN Chain AS c ON e.EmployeeID = c.ManagerID
        WHERE c.Depth < 100
    )
    SELECT @Cycle = 1 FROM Chain WHERE EmployeeID = @EmployeeID;

    IF @Cycle = 1
    BEGIN
        SET @Msg = CONCAT(N'Assigning #', @ManagerID, N' as manager of #', @EmployeeID, N' would create a reporting cycle.');
        THROW 50007, @Msg, 1;
    END;
    UPDATE dbo.Employee SET ManagerID = @ManagerID WHERE EmployeeID = @EmployeeID;   -- trigger re-checks cycles by ID
    SELECT @EmployeeID AS EmployeeID, @ManagerID AS NewManagerID;
END;
GO

/* =====================================================================
   Parameterised reports (mirror the Python ReportGenerator)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_Report_DepartmentsByHeadcount
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DepartmentID, DepartmentName, PlantName, Headcount
    FROM dbo.vw_DepartmentHeadcount
    ORDER BY Headcount DESC, DepartmentID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_EmployeesOnLeave
    @AsOf DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOf = ISNULL(@AsOf, CAST(GETDATE() AS DATE));
    SELECT l.LeaveID, e.EmployeeID, e.FirstName + N' ' + e.LastName AS EmployeeName, l.LeaveType, l.StartDate, l.EndDate
    FROM dbo.LeaveRequest AS l JOIN dbo.Employee AS e ON e.EmployeeID = l.EmployeeID
    WHERE l.Status = N'Approved' AND @AsOf BETWEEN l.StartDate AND l.EndDate
    ORDER BY l.StartDate;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_AverageOvertimeByDepartment
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.DepartmentID, d.DepartmentName,
           CAST(AVG(t.OvertimeHours) AS DECIMAL(5,2)) AS AvgOvertimeHours,
           SUM(t.OvertimeHours) AS TotalOvertimeHours
    FROM dbo.Timesheet AS t
    JOIN dbo.Employee   AS e ON e.EmployeeID = t.EmployeeID
    JOIN dbo.Department AS d ON d.DepartmentID = e.DepartmentID
    WHERE t.WorkDate BETWEEN @FromDate AND @ToDate
    GROUP BY d.DepartmentID, d.DepartmentName
    ORDER BY d.DepartmentID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_TopRatedEmployees
    @TopN INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@TopN) e.EmployeeID, e.FirstName + N' ' + e.LastName AS EmployeeName,
           CAST(AVG(CAST(r.Rating AS DECIMAL(4,2))) AS DECIMAL(4,2)) AS AvgRating,
           COUNT(*) AS Reviews
    FROM dbo.PerformanceReview AS r
    JOIN dbo.Employee AS e ON e.EmployeeID = r.EmployeeID
    GROUP BY e.EmployeeID, e.FirstName, e.LastName
    ORDER BY AvgRating DESC, e.EmployeeID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_PendingLeaveApprovals
    @ManagerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT LeaveID, EmployeeID, EmployeeName, LeaveType, StartDate, EndDate, WorkingDays
    FROM dbo.vw_PendingLeaveApprovals
    WHERE ManagerID = @ManagerID
    ORDER BY StartDate;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_SalaryDistribution
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.vw_SalaryDistributionByDepartment ORDER BY DepartmentID;
END;
GO

PRINT 'Stored procedures created.';
GO
