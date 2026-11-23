# WorkHubDB – ER Diagram

GitHub renders the diagram below automatically (Mermaid). In SSMS you can also generate it with
**WorkHubDB → Database Diagrams → New Database Diagram → add all six tables**.

```mermaid
erDiagram
    Plant ||--o{ Department : "hosts"
    Department ||--o{ Employee : "employs"
    Employee ||--o{ Employee : "manages (ManagerID)"
    Employee ||--o{ LeaveRequest : "requests"
    Employee ||--o{ Timesheet : "records"
    Employee ||--o{ PerformanceReview : "is reviewed in"
    Employee |o--o{ PerformanceReview : "reviews (ReviewerID)"

    Plant {
        INT PlantID PK "IDENTITY(1,1)"
        NVARCHAR_100 PlantName "NOT NULL, UNIQUE"
        NVARCHAR_50 City "NOT NULL"
    }
    Department {
        INT DepartmentID PK "IDENTITY(1,1)"
        NVARCHAR_100 DepartmentName "NOT NULL"
        INT PlantID FK "-> Plant"
    }
    Employee {
        INT EmployeeID PK "IDENTITY(1,1)"
        NVARCHAR_50 FirstName "NOT NULL"
        NVARCHAR_50 LastName "NOT NULL"
        NVARCHAR_100 Email "NOT NULL, UNIQUE"
        INT DepartmentID FK "-> Department"
        INT ManagerID FK "-> Employee, <> EmployeeID"
        DATE HireDate "NOT NULL"
        DECIMAL_12_2 Salary "CHECK >= 0"
    }
    LeaveRequest {
        INT LeaveID PK "IDENTITY(1,1)"
        INT EmployeeID FK "-> Employee, ON DELETE CASCADE"
        NVARCHAR_30 LeaveType "Annual | Sick | Casual | Unpaid"
        DATE StartDate "NOT NULL"
        DATE EndDate "CHECK EndDate >= StartDate"
        NVARCHAR_20 Status "DEFAULT 'Pending'"
    }
    Timesheet {
        INT TimesheetID PK "IDENTITY(1,1)"
        INT EmployeeID FK "-> Employee, ON DELETE CASCADE"
        DATE WorkDate "NOT NULL"
        DECIMAL_4_2 HoursWorked "CHECK 0..24"
        DECIMAL_4_2 OvertimeHours "DEFAULT 0, CHECK >= 0"
    }
    PerformanceReview {
        INT ReviewID PK "IDENTITY(1,1)"
        INT EmployeeID FK "-> Employee, ON DELETE CASCADE"
        INT ReviewerID FK "-> Employee"
        DATE ReviewDate "NOT NULL"
        INT Rating "CHECK BETWEEN 1 AND 5"
        NVARCHAR_500 Comments
    }
```

## Relationships

| Relationship | Type | Implementation |
|---|---|---|
| LeaveRequest – Employee | Many-to-One | `LeaveRequest.EmployeeID` → `Employee.EmployeeID` |
| Timesheet – Employee | Many-to-One | `Timesheet.EmployeeID` → `Employee.EmployeeID` |
| PerformanceReview – Employee | Many-to-One | `PerformanceReview.EmployeeID` → `Employee.EmployeeID` |
| Employee – Department | Many-to-One | `Employee.DepartmentID` → `Department.DepartmentID` |
| Department – Plant | Many-to-One | `Department.PlantID` → `Plant.PlantID` |
| Employee – Manager | Many-to-One (self) | `Employee.ManagerID` → `Employee.EmployeeID` (reporting hierarchy) |
| PerformanceReview – Reviewer | Many-to-One | `PerformanceReview.ReviewerID` → `Employee.EmployeeID` |

The three relationships required by the case study are the first three rows. The other
foreign keys enforce the "Identifier of the related …" columns so the data stays consistent.

`ReviewerID` uses `NO ACTION` because SQL Server does not allow a second cascade path to
`Employee`; `EmployeeService.delete_employee()` clears it inside the same transaction instead.
