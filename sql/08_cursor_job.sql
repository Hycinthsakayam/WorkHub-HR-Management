/* =====================================================================
   WorkHub - Stage 1 consolidation : cursor job (monthly payroll inputs)
   Script : 08_cursor_job.sql               Run after 07.
   Re-runnable.

   usp_Job_GenerateMonthlyPayrollInputs walks every employee with a CURSOR,
   aggregates that employee's timesheets for the month and writes one
   auditable row to PayrollInput. Every run is logged in JobRunLog.
   Same formula as the Python PayrollCalculator:
     base      = salary / 12
     hourly    = base / 176
     overtime  = hourly x overtime hours x 1.5   (managers: x 0, overtime-exempt)
     gross     = base + overtime
     deduction = 12% provident fund on base + 10% tax on gross
     net       = gross - deduction

   SQL Server Express has no SQL Server Agent, so the job is scheduled with
   Windows Task Scheduler running jobs\run_monthly_payroll_job.bat.
   ===================================================================== */

USE WorkHubDB;
GO

IF OBJECT_ID(N'dbo.PayrollInput', N'U') IS NULL
CREATE TABLE dbo.PayrollInput
(
    PayrollInputID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollInput PRIMARY KEY,
    EmployeeID     INT           NOT NULL CONSTRAINT FK_PayrollInput_Employee REFERENCES dbo.Employee (EmployeeID) ON DELETE CASCADE,
    PeriodYear     INT           NOT NULL,
    PeriodMonth    INT           NOT NULL CONSTRAINT CK_PayrollInput_Month CHECK (PeriodMonth BETWEEN 1 AND 12),
    DaysWorked     INT           NOT NULL,
    TotalHours     DECIMAL(7,2)  NOT NULL,
    OvertimeHours  DECIMAL(7,2)  NOT NULL,
    BasePay        DECIMAL(12,2) NOT NULL,
    OvertimePay    DECIMAL(12,2) NOT NULL,
    GrossPay       DECIMAL(12,2) NOT NULL,
    Deductions     DECIMAL(12,2) NOT NULL,
    NetPay         DECIMAL(12,2) NOT NULL,
    GeneratedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_PayrollInput_GeneratedAt DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_PayrollInput_Period UNIQUE (EmployeeID, PeriodYear, PeriodMonth),
    CONSTRAINT CK_PayrollInput_Net CHECK (NetPay = GrossPay - Deductions)
);
GO

IF OBJECT_ID(N'dbo.JobRunLog', N'U') IS NULL
CREATE TABLE dbo.JobRunLog
(
    JobRunID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_JobRunLog PRIMARY KEY,
    JobName       NVARCHAR(100) NOT NULL,
    Parameters    NVARCHAR(200) NULL,
    StartedAt     DATETIME2(3)  NOT NULL,
    FinishedAt    DATETIME2(3)  NULL,
    RowsProcessed INT           NULL,
    Status        NVARCHAR(20)  NOT NULL CONSTRAINT CK_JobRunLog_Status CHECK (Status IN (N'Running', N'Succeeded', N'Failed')),
    Message       NVARCHAR(4000) NULL
);
GO

CREATE OR ALTER PROCEDURE dbo.usp_Job_GenerateMonthlyPayrollInputs
    @Year  INT = NULL,        -- default: previous calendar month
    @Month INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Year IS NULL OR @Month IS NULL
    BEGIN
        DECLARE @Prev DATE = DATEADD(MONTH, -1, CAST(GETDATE() AS DATE));
        SELECT @Year = YEAR(@Prev), @Month = MONTH(@Prev);
    END;

    DECLARE @From DATE = DATEFROMPARTS(@Year, @Month, 1);
    DECLARE @To   DATE = EOMONTH(@From);
    DECLARE @RunID INT, @Rows INT = 0;

    INSERT INTO dbo.JobRunLog (JobName, Parameters, StartedAt, Status)
    VALUES (N'MonthlyPayrollInputs', CONCAT(@Year, N'-', RIGHT(CONCAT(N'0', @Month), 2)), SYSDATETIME(), N'Running');
    SET @RunID = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM dbo.PayrollInput WHERE PeriodYear = @Year AND PeriodMonth = @Month;   -- re-runnable

        DECLARE @EmployeeID INT, @Salary DECIMAL(12,2), @IsManager BIT,
                @Days INT, @Hours DECIMAL(7,2), @OT DECIMAL(7,2),
                @Base DECIMAL(12,2), @OTPay DECIMAL(12,2), @Gross DECIMAL(12,2), @Deduct DECIMAL(12,2);

        DECLARE employee_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT EmployeeID, Salary, dbo.fn_IsManager(EmployeeID)
            FROM dbo.Employee
            ORDER BY EmployeeID;

        OPEN employee_cursor;
        FETCH NEXT FROM employee_cursor INTO @EmployeeID, @Salary, @IsManager;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @Days  = COUNT(*),
                   @Hours = ISNULL(SUM(HoursWorked), 0),
                   @OT    = ISNULL(SUM(OvertimeHours), 0)
            FROM dbo.Timesheet
            WHERE EmployeeID = @EmployeeID AND WorkDate BETWEEN @From AND @To;

            SET @Base   = ROUND(@Salary / 12.0, 2);
            SET @OTPay  = ROUND(CAST(@Base AS DECIMAL(38,10)) / 176 * @OT
                                * CASE WHEN @IsManager = 1 THEN 0 ELSE 1.5 END, 2);
            SET @Gross  = @Base + @OTPay;
            SET @Deduct = ROUND(@Base * 0.12, 2) + ROUND(@Gross * 0.10, 2);

            INSERT INTO dbo.PayrollInput (EmployeeID, PeriodYear, PeriodMonth, DaysWorked, TotalHours, OvertimeHours,
                                          BasePay, OvertimePay, GrossPay, Deductions, NetPay)
            VALUES (@EmployeeID, @Year, @Month, @Days, @Hours, @OT,
                    @Base, @OTPay, @Gross, @Deduct, @Gross - @Deduct);

            SET @Rows += 1;
            FETCH NEXT FROM employee_cursor INTO @EmployeeID, @Salary, @IsManager;
        END;

        CLOSE employee_cursor;
        DEALLOCATE employee_cursor;

        COMMIT TRANSACTION;

        UPDATE dbo.JobRunLog
        SET FinishedAt = SYSDATETIME(), RowsProcessed = @Rows, Status = N'Succeeded',
            Message = CONCAT(@Rows, N' payroll input row(s) generated for ', @Year, N'-', RIGHT(CONCAT(N'0', @Month), 2))
        WHERE JobRunID = @RunID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        UPDATE dbo.JobRunLog
        SET FinishedAt = SYSDATETIME(), RowsProcessed = 0, Status = N'Failed', Message = ERROR_MESSAGE()
        WHERE JobRunID = @RunID;
        THROW;
    END CATCH;

    -- Run summary
    SELECT @Year AS PeriodYear, @Month AS PeriodMonth, COUNT(*) AS Employees,
           SUM(OvertimeHours) AS TotalOvertimeHours,
           SUM(GrossPay) AS TotalGross, SUM(Deductions) AS TotalDeductions, SUM(NetPay) AS TotalNet
    FROM dbo.PayrollInput
    WHERE PeriodYear = @Year AND PeriodMonth = @Month;
END;
GO

PRINT 'Cursor job created.';
GO
