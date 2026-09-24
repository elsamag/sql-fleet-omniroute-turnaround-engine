-- ============================================================================
-- SCRIPT: tests/test_sla_boundary_conditions.sql
-- REPO: sql-logistics-omniroute-turnaround-pipeline
-- CLIENT: OmniRoute Freight Systems
-- AUTHOR: Samuel Chinwendu Agu | Elsamag IT Solutions
-- DIALECT: SQLite / ANSI Standard SQL Compatible
-- ============================================================================

-- Architectural Intent:
-- Enforce deterministic SLA tiers and financial penalty calculations across 
-- decimal boundary thresholds using a portable CHECK constraint gate.

.bail on

DROP TABLE IF EXISTS temp_test_manifest;
DROP TABLE IF EXISTS temp_sla_test_results;

-- Step 1: Create isolated in-memory test fixture table
CREATE TEMP TABLE temp_test_manifest (
  test_case_id TEXT PRIMARY KEY,
  test_label TEXT NOT NULL,
  dispatched_at TEXT NOT NULL,
  completed_at TEXT NOT NULL,
  base_rate_usd REAL NOT NULL,
  expected_tier TEXT NOT NULL,
  expected_penalty REAL NOT NULL
);

-- Step 2: Seed boundary stress cases across exact decimal thresholds
INSERT INTO temp_test_manifest VALUES
  ('TC-01', 'Zero Duration Lower Bound', '2026-09-01 00:00:00', '2026-09-01 00:00:00', 1000.00, 'SLA Target Achieved', 0.00),
  ('TC-02', 'Exact 12h Target Boundary', '2026-09-01 00:00:00', '2026-09-01 12:00:00', 1000.00, 'SLA Target Achieved', 0.00),
  ('TC-03', '12.01h Standard Window Edge', '2026-09-01 00:00:00', '2026-09-01 12:00:36', 1000.00, 'SLA Standard Window', 0.00),
  ('TC-04', 'Exact 24h Standard Boundary', '2026-09-01 00:00:00', '2026-09-02 00:00:00', 1000.00, 'SLA Standard Window', 0.00),
  ('TC-05', '24.01h Grace Period Edge', '2026-09-01 00:00:00', '2026-09-02 00:00:36', 1000.00, 'SLA Grace Period', 0.00),
  ('TC-06', 'Exact 48h Grace Upper Bound', '2026-09-01 00:00:00', '2026-09-03 00:00:00', 1000.00, 'SLA Grace Period', 0.00),
  ('TC-07', '48.01h Critical Breach Edge', '2026-09-01 00:00:00', '2026-09-03 00:00:36', 1000.00, 'SLA Critical Breach', 150.00),
  ('TC-08', 'Extended Critical Breach', '2026-09-01 00:00:00', '2026-09-05 12:00:00', 2000.00, 'SLA Critical Breach', 300.00);

-- Step 3: Create assertion gate table with strict CHECK constraint
CREATE TEMP TABLE temp_sla_test_results (
  test_case_id TEXT PRIMARY KEY,
  test_label TEXT NOT NULL,
  calculated_hours REAL NOT NULL,
  actual_tier TEXT NOT NULL,
  actual_penalty REAL NOT NULL,
  passed INTEGER CHECK(passed = 1)
);

-- Step 4: Evaluate boundaries and insert into gate table
INSERT INTO temp_sla_test_results
SELECT
  t.test_case_id,
  t.test_label,
  ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) AS calculated_hours,
  CASE 
    WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 12.00 
      THEN 'SLA Target Achieved'
    WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 24.00 
      THEN 'SLA Standard Window'
    WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 48.00 
      THEN 'SLA Grace Period'
    ELSE 'SLA Critical Breach'
  END AS actual_tier,
  CASE 
    WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) > 48.00 
      THEN ROUND(t.base_rate_usd * 0.15, 2)
    ELSE 0.00
  END AS actual_penalty,
  CASE 
    WHEN (
      CASE 
        WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 12.00 
          THEN 'SLA Target Achieved'
        WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 24.00 
          THEN 'SLA Standard Window'
        WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 48.00 
          THEN 'SLA Grace Period'
        ELSE 'SLA Critical Breach'
      END
    ) = t.expected_tier
    AND (
      CASE 
        WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) > 48.00 
          THEN ROUND(t.base_rate_usd * 0.15, 2)
        ELSE 0.00
      END
    ) = t.expected_penalty
    THEN 1
    ELSE 0
  END AS passed
FROM temp_test_manifest t;

-- Step 5: Output verified audit ledger
SELECT 
  test_case_id, 
  test_label, 
  calculated_hours, 
  actual_tier, 
  actual_penalty, 
  'PASS' AS test_status
FROM temp_sla_test_results;

-- Clean up temporary test structures
DROP TABLE temp_sla_test_results;
DROP TABLE temp_test_manifest;
