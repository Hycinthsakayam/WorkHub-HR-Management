/* =====================================================================
   WorkHub - NEW BUSINESS REQUIREMENT : training course waitlist
   Script : 09_course_waitlist.sql          Run after 08.
   Re-runnable (drops and recreates only the course objects).

   User story (added to the backlog after Sprint 1):
     "As an employee I want to enrol in a training course; if the course is
      full I want to join a waitlist and be enrolled automatically when a
      seat frees up, in the order people joined."

   Design
     TrainingCourse    course with a seat Capacity (CHECK > 0)
     CourseEnrollment  one row per employee per course: Enrolled / Waitlisted / Cancelled
     usp_EnrollInCourse      enrol if a seat is free, otherwise waitlist      (50008 errors)
     usp_CancelEnrollment    cancel an enrolment or waitlist place
     trg_CourseEnrollment_PromoteWaitlist  seat freed -> first waitlisted person promoted
     trg_CourseEnrollment_Capacity         never more Enrolled than Capacity
     vw_CourseWaitlist       live seats and waitlist positions (ROW_NUMBER)
   ===================================================================== */

USE WorkHubDB;
GO

DROP VIEW      IF EXISTS dbo.vw_CourseWaitlist;
DROP PROCEDURE IF EXISTS dbo.usp_EnrollInCourse;
DROP PROCEDURE IF EXISTS dbo.usp_CancelEnrollment;
DROP TABLE     IF EXISTS dbo.CourseEnrollment;
DROP TABLE     IF EXISTS dbo.TrainingCourse;
GO

CREATE TABLE dbo.TrainingCourse
(
    CourseID     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TrainingCourse PRIMARY KEY,
    CourseTitle  NVARCHAR(150)     NOT NULL CONSTRAINT UQ_TrainingCourse_Title UNIQUE,
    StartDate    DATE              NOT NULL,
    Capacity     INT               NOT NULL CONSTRAINT CK_TrainingCourse_Capacity CHECK (Capacity > 0),
    DepartmentID INT               NULL CONSTRAINT FK_TrainingCourse_Department REFERENCES dbo.Department (DepartmentID)
);
GO

CREATE TABLE dbo.CourseEnrollment
(
    EnrollmentID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CourseEnrollment PRIMARY KEY,
    CourseID     INT          NOT NULL CONSTRAINT FK_CourseEnrollment_Course   REFERENCES dbo.TrainingCourse (CourseID) ON DELETE CASCADE,
    EmployeeID   INT          NOT NULL CONSTRAINT FK_CourseEnrollment_Employee REFERENCES dbo.Employee (EmployeeID) ON DELETE CASCADE,
    Status       NVARCHAR(20) NOT NULL CONSTRAINT CK_CourseEnrollment_Status CHECK (Status IN (N'Enrolled', N'Waitlisted', N'Cancelled')),
    RequestedAt  DATETIME2(7) NOT NULL CONSTRAINT DF_CourseEnrollment_RequestedAt DEFAULT (SYSDATETIME()),
    PromotedAt   DATETIME2(0) NULL,           -- set when moved from the waitlist to Enrolled
    CONSTRAINT UQ_CourseEnrollment_CourseEmployee UNIQUE (CourseID, EmployeeID)
);
CREATE INDEX IX_CourseEnrollment_Course_Status ON dbo.CourseEnrollment (CourseID, Status, RequestedAt);
GO

/* ---------------------------------------------------------------------
   Trigger: never exceed capacity
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_CourseEnrollment_Capacity
ON dbo.CourseEnrollment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM dbo.TrainingCourse AS c
        WHERE c.CourseID IN (SELECT CourseID FROM inserted)
          AND (SELECT COUNT(*) FROM dbo.CourseEnrollment AS e
               WHERE e.CourseID = c.CourseID AND e.Status = N'Enrolled') > c.Capacity)
    BEGIN
        ;THROW 50008, N'Course is full: enrolled count cannot exceed capacity.', 1;
    END;
END;
GO

/* ---------------------------------------------------------------------
   Trigger: a freed seat promotes the earliest waitlisted employee(s)
   --------------------------------------------------------------------- */
CREATE OR ALTER TRIGGER dbo.trg_CourseEnrollment_PromoteWaitlist
ON dbo.CourseEnrollment
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Courses where an Enrolled seat was released (cancelled or deleted)
    DECLARE @Affected TABLE (CourseID INT PRIMARY KEY);
    INSERT INTO @Affected (CourseID)
    SELECT DISTINCT d.CourseID
    FROM deleted AS d
    LEFT JOIN inserted AS i ON i.EnrollmentID = d.EnrollmentID
    WHERE d.Status = N'Enrolled' AND (i.EnrollmentID IS NULL OR i.Status <> N'Enrolled');

    IF NOT EXISTS (SELECT 1 FROM @Affected) RETURN;

    WITH FreeSeats AS
    (
        SELECT c.CourseID,
               c.Capacity - (SELECT COUNT(*) FROM dbo.CourseEnrollment AS e
                             WHERE e.CourseID = c.CourseID AND e.Status = N'Enrolled') AS Seats
        FROM dbo.TrainingCourse AS c
        JOIN @Affected AS a ON a.CourseID = c.CourseID
    ),
    Queue AS
    (
        SELECT e.EnrollmentID, e.CourseID,
               ROW_NUMBER() OVER (PARTITION BY e.CourseID ORDER BY e.RequestedAt, e.EnrollmentID) AS Position
        FROM dbo.CourseEnrollment AS e
        JOIN @Affected AS a ON a.CourseID = e.CourseID
        WHERE e.Status = N'Waitlisted'
    )
    UPDATE ce
    SET Status = N'Enrolled', PromotedAt = SYSDATETIME()
    FROM dbo.CourseEnrollment AS ce
    JOIN Queue     AS q ON q.EnrollmentID = ce.EnrollmentID
    JOIN FreeSeats AS f ON f.CourseID = q.CourseID
    WHERE q.Position <= f.Seats;
END;
GO

/* ---------------------------------------------------------------------
   View: seats and waitlist positions
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW dbo.vw_CourseWaitlist
AS
SELECT c.CourseID, c.CourseTitle, c.Capacity,
       (SELECT COUNT(*) FROM dbo.CourseEnrollment x WHERE x.CourseID = c.CourseID AND x.Status = N'Enrolled') AS SeatsTaken,
       e.EnrollmentID, e.EmployeeID, emp.FirstName + N' ' + emp.LastName AS EmployeeName, e.Status,
       CASE WHEN e.Status = N'Waitlisted'
            THEN ROW_NUMBER() OVER (PARTITION BY c.CourseID, e.Status ORDER BY e.RequestedAt, e.EnrollmentID)
       END AS WaitlistPosition,
       e.RequestedAt, e.PromotedAt
FROM dbo.TrainingCourse AS c
JOIN dbo.CourseEnrollment AS e ON e.CourseID = c.CourseID
JOIN dbo.Employee AS emp ON emp.EmployeeID = e.EmployeeID;
GO

/* ---------------------------------------------------------------------
   Procedures
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_EnrollInCourse
    @CourseID   INT,
    @EmployeeID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Msg NVARCHAR(400), @Capacity INT, @Enrolled INT, @NewStatus NVARCHAR(20), @Existing NVARCHAR(20);

    IF NOT EXISTS (SELECT 1 FROM dbo.Employee WHERE EmployeeID = @EmployeeID)
    BEGIN
        SET @Msg = CONCAT(N'Employee with ID ', @EmployeeID, N' was not found.');
        THROW 50006, @Msg, 1;
    END;

    BEGIN TRANSACTION;
        -- UPDLOCK + HOLDLOCK: two people cannot take the last seat at the same time
        SELECT @Capacity = Capacity FROM dbo.TrainingCourse WITH (UPDLOCK, HOLDLOCK) WHERE CourseID = @CourseID;
        IF @Capacity IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            SET @Msg = CONCAT(N'Training course with ID ', @CourseID, N' was not found.');
            THROW 50008, @Msg, 1;
        END;

        SELECT @Existing = Status FROM dbo.CourseEnrollment WHERE CourseID = @CourseID AND EmployeeID = @EmployeeID;
        IF @Existing IN (N'Enrolled', N'Waitlisted')
        BEGIN
            ROLLBACK TRANSACTION;
            SET @Msg = CONCAT(N'Employee #', @EmployeeID, N' is already ', @Existing, N' for course #', @CourseID, N'.');
            THROW 50008, @Msg, 1;
        END;

        SELECT @Enrolled = COUNT(*) FROM dbo.CourseEnrollment WHERE CourseID = @CourseID AND Status = N'Enrolled';
        SET @NewStatus = CASE WHEN @Enrolled < @Capacity THEN N'Enrolled' ELSE N'Waitlisted' END;

        IF @Existing = N'Cancelled'      -- re-joining goes to the back of the queue
            UPDATE dbo.CourseEnrollment SET Status = @NewStatus, RequestedAt = SYSDATETIME(), PromotedAt = NULL
            WHERE CourseID = @CourseID AND EmployeeID = @EmployeeID;
        ELSE
            INSERT INTO dbo.CourseEnrollment (CourseID, EmployeeID, Status) VALUES (@CourseID, @EmployeeID, @NewStatus);
    COMMIT TRANSACTION;

    SELECT CourseID, CourseTitle, EmployeeID, EmployeeName, Status, WaitlistPosition, Capacity, SeatsTaken
    FROM dbo.vw_CourseWaitlist WHERE CourseID = @CourseID AND EmployeeID = @EmployeeID;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CancelEnrollment
    @CourseID   INT,
    @EmployeeID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Msg NVARCHAR(400);
    IF NOT EXISTS (SELECT 1 FROM dbo.CourseEnrollment
                   WHERE CourseID = @CourseID AND EmployeeID = @EmployeeID AND Status <> N'Cancelled')
    BEGIN
        SET @Msg = CONCAT(N'Employee #', @EmployeeID, N' has no active enrolment for course #', @CourseID, N'.');
        THROW 50008, @Msg, 1;
    END;
    UPDATE dbo.CourseEnrollment SET Status = N'Cancelled'     -- trigger promotes the next waitlisted person
    WHERE CourseID = @CourseID AND EmployeeID = @EmployeeID;

    SELECT CourseID, CourseTitle, Capacity, SeatsTaken, EmployeeID, EmployeeName, Status, WaitlistPosition, PromotedAt
    FROM dbo.vw_CourseWaitlist WHERE CourseID = @CourseID AND Status <> N'Cancelled'
    ORDER BY CASE Status WHEN N'Enrolled' THEN 0 ELSE 1 END, WaitlistPosition, EmployeeID;
END;
GO

/* ---------------------------------------------------------------------
   Sample data: 10 courses, 3 of them with a waitlist
   --------------------------------------------------------------------- */
SET NOCOUNT ON;
SET IDENTITY_INSERT dbo.TrainingCourse ON;
INSERT INTO dbo.TrainingCourse (CourseID, CourseTitle, StartDate, Capacity, DepartmentID) VALUES
 (1,  N'Lean Manufacturing Basics',          '2026-12-07', 3,  12),
 (2,  N'Workplace Safety Refresher',         '2026-12-09', 5,  12),
 (3,  N'Leadership for New Managers',        '2026-12-14', 2,  12),
 (4,  N'Advanced Excel for Finance',         '2027-01-11', 8,  2),
 (5,  N'ISO 9001 Internal Auditor',          '2027-01-18', 6,  4),
 (6,  N'Preventive Maintenance Planning',    '2027-01-25', 6,  6),
 (7,  N'Supply Chain Analytics',             '2027-02-01', 10, 10),
 (8,  N'Effective Performance Reviews',      '2027-02-08', 12, 1),
 (9,  N'CAD Fundamentals',                   '2027-02-15', 6,  9),
 (10, N'Forklift Operator Certification',    '2027-02-22', 4,  11);
SET IDENTITY_INSERT dbo.TrainingCourse OFF;

-- Enrol through the procedure so the waitlist logic decides the status (results discarded)
DECLARE @Enrol TABLE (CourseID INT, EmployeeID INT, Seq INT IDENTITY(1,1));
INSERT INTO @Enrol (CourseID, EmployeeID) VALUES
 (1, 9), (1, 11), (1, 12), (1, 14), (1, 17),        -- capacity 3 -> 2 waitlisted
 (3, 2), (3, 23), (3, 21),                          -- capacity 2 -> 1 waitlisted
 (2, 13), (2, 27), (2, 18), (2, 19),                -- capacity 5 -> all enrolled
 (4, 21), (4, 22), (5, 10), (5, 28), (7, 24), (10, 25);

DECLARE @C INT, @E INT, @I INT = 1, @N INT = (SELECT COUNT(*) FROM @Enrol);
DECLARE @Discard TABLE (CourseID INT, CourseTitle NVARCHAR(150), EmployeeID INT, EmployeeName NVARCHAR(101),
                        Status NVARCHAR(20), WaitlistPosition BIGINT, Capacity INT, SeatsTaken INT);
WHILE @I <= @N
BEGIN
    SELECT @C = CourseID, @E = EmployeeID FROM @Enrol WHERE Seq = @I;
    INSERT INTO @Discard EXEC dbo.usp_EnrollInCourse @CourseID = @C, @EmployeeID = @E;
    SET @I += 1;
END;
GO

SELECT CourseID, CourseTitle, Capacity, SeatsTaken, EmployeeName, Status, WaitlistPosition
FROM dbo.vw_CourseWaitlist
WHERE CourseID IN (1, 3)
ORDER BY CourseID, CASE Status WHEN N'Enrolled' THEN 0 ELSE 1 END, WaitlistPosition;
GO
PRINT 'Course waitlist objects and sample data created.';
GO
