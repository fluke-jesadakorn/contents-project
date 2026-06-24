-- Database Initialization for HR Line Agent Bot & Web Admin
-- Database: hr_db
-- Target: localhost:5432

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Table: employees
CREATE TABLE IF NOT EXISTS employees (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_code         TEXT UNIQUE NOT NULL,
    line_user_id          TEXT UNIQUE,
    name                  TEXT NOT NULL,
    department            TEXT NOT NULL,
    position              TEXT NOT NULL,
    role                  TEXT NOT NULL DEFAULT 'staff', -- 'staff' | 'manager' | 'hr'
    job_description       TEXT NOT NULL,
    total_sick_leave      INT DEFAULT 30,
    used_sick_leave       INT DEFAULT 0,
    total_annual_leave    INT DEFAULT 10,
    used_annual_leave     INT DEFAULT 0,
    total_personal_leave  INT DEFAULT 6,
    used_personal_leave   INT DEFAULT 0,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table: leave_requests
CREATE TABLE IF NOT EXISTS leave_requests (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id    UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    leave_type     TEXT NOT NULL,                     -- 'sick' | 'annual' | 'personal'
    start_date     DATE NOT NULL,
    end_date       DATE NOT NULL,
    days           NUMERIC(3, 1) NOT NULL,
    reason         TEXT,
    reject_reason  TEXT,
    status         TEXT NOT NULL DEFAULT 'pending',   -- 'pending' | 'approved' | 'rejected'
    approved_by    UUID REFERENCES employees(id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table: user_sessions (State tracking for n8n multi-step bot)
CREATE TABLE IF NOT EXISTS user_sessions (
    line_user_id   TEXT PRIMARY KEY,
    current_state  TEXT NOT NULL DEFAULT 'idle',
    temp_data      JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_employees_line_user ON employees (line_user_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests (employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status ON leave_requests (status);
CREATE INDEX IF NOT EXISTS idx_user_sessions_state ON user_sessions (current_state);
