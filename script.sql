-- Drop Existing Tables (if they exist)
BEGIN
    -- Dropping the tables if they already exist to start fresh
    EXECUTE IMMEDIATE 'DROP TABLE Employee CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE Attendance CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE LeaveRequest CASCADE CONSTRAINTS';
    EXECUTE IMMEDIATE 'DROP TABLE Payroll CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN NULL;  -- Ignore errors if the tables don't exist
END;
/

-- Create Tables
-- Employee Table: Stores details of employees like name, role, department, etc.
CREATE TABLE Employee (
    EmployeeID      NUMBER PRIMARY KEY,  -- Unique ID for each employee
    FullName        VARCHAR2(100) NOT NULL,  -- Employee's full name
    Department      VARCHAR2(50),  -- Department the employee belongs to
    Role            VARCHAR2(50),  -- Role of the employee (e.g., Software Engineer)
    JoiningDate     DATE,  -- The date when the employee joined
    ContactNumber   VARCHAR2(15),  -- Contact number of the employee
    Email           VARCHAR2(100) UNIQUE  -- Email address of the employee
);

-- Attendance Table: Tracks employee clock-in and clock-out times
CREATE TABLE Attendance (
    AttendanceID    NUMBER PRIMARY KEY,  -- Unique ID for each attendance record
    EmployeeID      NUMBER NOT NULL,  -- Reference to Employee table
    ClockInTime     DATE DEFAULT SYSDATE,  -- Clock-in time (defaults to current date and time)
    ClockOutTime    DATE,  -- Clock-out time
    AttendanceDate  DATE DEFAULT SYSDATE,  -- Date of attendance (defaults to current date)
    TotalHoursWorked NUMBER,  -- Total hours worked on the day (calculated automatically)
    CONSTRAINT fk_employee FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)  -- Foreign key to Employee table
);

-- LeaveRequest Table: Stores leave requests made by employees
CREATE TABLE LeaveRequest (
    LeaveRequestID  NUMBER PRIMARY KEY,  -- Unique ID for each leave request
    EmployeeID      NUMBER NOT NULL,  -- Reference to Employee table
    LeaveStartDate  DATE,  -- The start date of the leave
    LeaveEndDate    DATE,  -- The end date of the leave
    LeaveType       VARCHAR2(20) CHECK (LeaveType IN ('Sick', 'Casual', 'Paid')),  -- Type of leave
    Status          VARCHAR2(20) DEFAULT 'Pending',  -- Status of the leave request (Pending/Approved)
    CONSTRAINT fk_employee_leave FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)  -- Foreign key to Employee table
);

-- Payroll Table: Manages payroll information for employees
CREATE TABLE Payroll (
    PayrollID       NUMBER PRIMARY KEY,  -- Unique ID for each payroll record
    EmployeeID      NUMBER NOT NULL,  -- Reference to Employee table
    Salary          NUMBER,  -- Basic salary of the employee
    Bonus           NUMBER DEFAULT 0,  -- Bonus (default to 0)
    Deductions      NUMBER DEFAULT 0,  -- Deductions (default to 0)
    TotalPay        NUMBER,  -- Total pay (calculated automatically)
    PayrollDate     DATE DEFAULT SYSDATE,  -- Date of payroll (defaults to current date)
    CONSTRAINT fk_employee_salary FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)  -- Foreign key to Employee table
);

-- Create Indexes to speed up queries
CREATE INDEX idx_employee_attendance ON Attendance(EmployeeID);
CREATE INDEX idx_employee_leave ON LeaveRequest(EmployeeID);

-- Create Triggers
-- Trigger to calculate the TotalHoursWorked for an employee when they clock out
CREATE OR REPLACE TRIGGER trg_calculate_hours
AFTER UPDATE OF ClockOutTime ON Attendance
FOR EACH ROW
BEGIN
    -- Calculate the total hours worked by subtracting ClockInTime from ClockOutTime
    :NEW.TotalHoursWorked := ( :NEW.ClockOutTime - :NEW.ClockInTime ) * 24;
END;
/

-- Trigger to calculate the TotalPay for payroll by adding salary, bonus, and subtracting deductions
CREATE OR REPLACE TRIGGER trg_calculate_payroll
AFTER INSERT ON Payroll
FOR EACH ROW
BEGIN
    -- Calculate the total pay by adding Salary + Bonus - Deductions
    :NEW.TotalPay := :NEW.Salary + :NEW.Bonus - :NEW.Deductions;
END;
/

-- Stored Procedures (simplified for easy understanding)
-- Procedure to register employee attendance (clock-in or clock-out)
CREATE OR REPLACE PROCEDURE RegisterAttendance(
    p_EmployeeID IN NUMBER,  -- Employee ID (the one who's clocking in or out)
    p_ClockOutTime IN DATE  -- Clock-out time (only if they are clocking out)
) AS
BEGIN
    -- Check if the employee has already clocked in today
    DECLARE
        v_existingAttendance Attendance.AttendanceID%TYPE;
    BEGIN
        -- Try to find an existing clock-in record for today (without a clock-out time)
        SELECT AttendanceID INTO v_existingAttendance
        FROM Attendance
        WHERE EmployeeID = p_EmployeeID
        AND AttendanceDate = SYSDATE
        AND ClockOutTime IS NULL;
        
        -- If a clock-in exists, we just update the clock-out time
        IF v_existingAttendance IS NOT NULL THEN
            UPDATE Attendance
            SET ClockOutTime = p_ClockOutTime
            WHERE AttendanceID = v_existingAttendance;
        ELSE
            -- If no clock-in exists, we insert a new record for clock-in
            INSERT INTO Attendance (EmployeeID, ClockInTime, AttendanceDate)
            VALUES (p_EmployeeID, SYSDATE, SYSDATE);
        END IF;
    END;
END;
/

-- Procedure to register leave request
CREATE OR REPLACE PROCEDURE RegisterLeaveRequest(
    p_EmployeeID IN NUMBER,  -- Employee ID (the one requesting leave)
    p_LeaveStartDate IN DATE,  -- Start date of leave
    p_LeaveEndDate IN DATE,  -- End date of leave
    p_LeaveType IN VARCHAR2  -- Type of leave (Sick, Casual, Paid)
) AS
BEGIN
    -- Insert a new leave request into the LeaveRequest table
    INSERT INTO LeaveRequest (EmployeeID, LeaveStartDate, LeaveEndDate, LeaveType, Status)
    VALUES (p_EmployeeID, p_LeaveStartDate, p_LeaveEndDate, p_LeaveType, 'Pending');
END;
/

-- Procedure to process payroll (calculate total pay)
CREATE OR REPLACE PROCEDURE ProcessPayroll(
    p_EmployeeID IN NUMBER,  -- Employee ID (the one receiving the payroll)
    p_Salary IN NUMBER,  -- Basic salary of the employee
    p_Bonus IN NUMBER,  -- Bonus for the employee
    p_Deductions IN NUMBER  -- Deductions from salary
) AS
BEGIN
    -- Insert a new payroll record into the Payroll table
    INSERT INTO Payroll (EmployeeID, Salary, Bonus, Deductions)
    VALUES (p_EmployeeID, p_Salary, p_Bonus, p_Deductions);
END;
/

-- Views (to easily get reports)
-- View to see all employee attendance records and the total hours worked
CREATE OR REPLACE VIEW v_EmployeeAttendance AS
SELECT e.EmployeeID, e.FullName, a.AttendanceDate, a.ClockInTime, a.ClockOutTime, a.TotalHoursWorked
FROM Employee e
JOIN Attendance a ON e.EmployeeID = a.EmployeeID;

-- View to see all leave requests and their current status
CREATE OR REPLACE VIEW v_LeaveRequests AS
SELECT e.FullName, lr.LeaveStartDate, lr.LeaveEndDate, lr.LeaveType, lr.Status
FROM LeaveRequest lr
JOIN Employee e ON lr.EmployeeID = e.EmployeeID;

-- View to see all payroll records
CREATE OR REPLACE VIEW v_PayrollReport AS
SELECT e.FullName, p.Salary, p.Bonus, p.Deductions, p.TotalPay
FROM Payroll p
JOIN Employee e ON p.EmployeeID = e.EmployeeID;

-- Insert Sample Data (for testing)
-- Inserting Employees
INSERT INTO Employee (EmployeeID, FullName, Department, Role, JoiningDate, ContactNumber, Email)
VALUES (1, 'John Doe', 'Engineering', 'Software Engineer', TO_DATE('2020-05-01', 'YYYY-MM-DD'), '1234567890', 'john.doe@example.com');

INSERT INTO Employee (EmployeeID, FullName, Department, Role, JoiningDate, ContactNumber, Email)
VALUES (2, 'Jane Smith', 'HR', 'HR Manager', TO_DATE('2019-02-15', 'YYYY-MM-DD'), '0987654321', 'jane.smith@example.com');

-- Insert Payroll Data (for testing)
EXEC ProcessPayroll(1, 5000, 500, 100);  -- John Doe's payroll

-- Register Attendance (John clocks in)
EXEC RegisterAttendance(1, NULL);  -- John Doe clocks in today
