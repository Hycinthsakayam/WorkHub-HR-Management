# WorkHub – Employee and HR Management System

My capstone project for the Hexaware training (Python track).

WorkHub is an HR system for a manufacturing company that still handles employee records, leave,
timesheets and performance reviews on paper and in Excel. The goal is to move all of that into a
proper database and later build a console app on top of it.

## Sprint 1 – Database

This sprint was about the database, so this repo only has the database work so far.

What I did:

- Designed the database `WorkHubDB` in SQL Server with 6 tables: Plant, Department, Employee,
  LeaveRequest, Timesheet and PerformanceReview
- Drew the ER diagram ([docs/ER_Diagram.md](docs/ER_Diagram.md))
- Added primary keys, foreign keys and constraints (unique email, salary not negative, rating
  1 to 5, hours 0 to 24, leave status defaults to Pending, and so on)
- Inserted sample data: 30 employees and 1,710 timesheet rows
- Wrote a script that tests every constraint with good and bad data (all 25 pass)
- Added views, stored procedures, triggers and a cursor job for monthly payroll
- Set up a few MongoDB collections with validation and aggregation queries
- Added the new "course waitlist" requirement on the database side

## How to run

You need SQL Server with SSMS, and MongoDB if you want to run the Mongo part.

Run the scripts in the `sql` folder in order (`01`, `02`, `05` to `09`), or just run:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_databases.ps1
```

To check the constraints, run `sql/03_verify_constraints.sql`.

## Next

Sprint 2 will be the Python side: entity classes and the business rules.
