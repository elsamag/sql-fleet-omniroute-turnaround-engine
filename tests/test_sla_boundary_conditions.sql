-- ============================================================================
-- SCRIPT: tests/test_sla_boundary_conditions.sql
-- REPO: sql-logistics-omniroute-turnaround-pipeline
-- CLIENT: OmniRoute Freight Systems
-- AUTHOR: Samuel Chinwendu Agu | Elsamag IT Solutions
-- DIALECT: SQLite / ANSI Standard SQL Compatible
-- ============================================================================

-- Rule 88 Architectural Intent:
-- Verify that turnaround hour boundaries map deterministically to the
-- correct SLA tiers and financial penalty assessments without threshold drift.

BEGIN TRANSACTION;

-- Step 1: Create isolated in-memory test fixture table
CREATE TEMP TABLE IF NOT EXISTS temp_test_manifest (
  test_case_id TEXT PRIMARY KEY,
  test_label TEXT NOT NULL,
  dispatched_at TEXT NOT NULL,
  completed_at TEXT NOT NULL,
  base_rate_usd REAL NOT NULL,
  expected_tier TEXT NOT NULL,
  expected_penalty REAL NOT NULL
);

-- Step 2: Seed boundary stress cases across exact decimal thresholds
INSERT INTO temp_test_manifest (
  test_case_id,
  test_label,
  dispatched_at,
  completed_at,
  base_rate_usd,
  expected_tier,
  expected_penalty
) VALUES
  (
    'TC-01',
    'Zero Duration Lower Bound',
    '2026-09-01 00:00:00',
    '2026-09-01 00:00:00',
    1000.00,
    'SLA Target Achieved',
    0.00
  ),
  (
    'TC-02',
    'Exact 12-Hour Target Boundary',
    '2026-09-01 00:00:00',
    '2026-09-01 12:00:00',
    1000.00,
    'SLA Target Achieved',
    0.00
  ),
  (
    'TC-03',
    '12.01-Hour Standard Window Edge',
    '2026-09-01 00:00:00',
    '2026-09-01 12:00:36',
    1000.00,
    'SLA Standard Window',
    0.00
  ),
  (
    'TC-04',
    'Exact 24-Hour Standard Boundary',
    '2026-09-01 00:00:00',
    '2026-09-02 00:00:00',
    1000.00,
    'SLA Standard Window',
    0.00
  ),
  (
    'TC-05',
    '24.01-Hour Grace Period Edge',
    '2026-09-01 00:00:00',
    '2026-09-02 00:00:36',
    1000.00,
    'SLA Grace Period',
    0.00
  ),
  (
    'TC-06',
    'Exact 48-Hour Grace Period Upper Bound',
    '2026-09-01 00:00:00',
    '2026-09-03 00:00:00',
    1000.00,
    'SLA Grace Period',
    0.00
  ),
  (
    'TC-07',
    '48.01-Hour Critical Breach Boundary',
    '2026-09-01 00:00:00',
    '2026-09-03 00:00:36',
    1000.00,
    'SLA Critical Breach',
    150.00
  ),
  (
    'TC-08',
    'Extended Multi-Day Critical Breach',
    '2026-09-01 00:00:00',
    '2026-09-05 12:00:00',
    2000.00,
    'SLA Critical Breach',
    300.00
  );

-- Step 3: Run boundary calculations and compare actual vs expected
WITH calculated_results AS (
  SELECT
    test_case_id,
    test_label,
    ROUND(
      (julianday(completed_at) - julianday(dispatched_at)) * 24.0,
      2
    ) AS calculated_hours,
    base_rate_usd,
    expected_tier,
    expected_penalty,
    CASE 
      WHEN ROUND((julianday(completed_at) - julianday(dispatched_at)) * 24.0, 2) <= 12.00 
        THEN 'SLA Target Achieved'
      WHEN ROUND((julianday(completed_at) - julianday(dispatched_at)) * 24.0, 2) <= 24.00 
        THEN 'SLA Standard Window'
      WHEN ROUND((julianday(completed_at) - julianday(dispatched_at)) * 24.0, 2) <= 48.00 
        THEN 'SLA Grace Period'
      ELSE 'SLA Critical Breach'
    END AS actual_tier,
    CASE 
      WHEN ROUND((julianday(completed_at) - julianday(dispatched_at)) * 24.0, 2) > 48.00 
        THEN ROUND(base_rate_usd * 0.15, 2)
      ELSE 0.00
    END AS actual_penalty
  FROM temp_test_manifest
),
assertion_evaluation AS (
  SELECT
    test_case_id,
    test_label,
    calculated_hours,
    actual_tier,
    expected_tier,
    actual_penalty,
    expected_penalty,
    CASE 
      WHEN actual_tier = expected_tier 
       AND actual_penalty = expected_penalty 
        THEN 'PASS'
      ELSE 'FAIL'
    END AS test_status
  FROM calculated_results
)
SELECT 
  test_case_id,
  test_label,
  calculated_hours,
  actual_tier,
  actual_penalty,
  test_status
FROM assertion_evaluation;

-- Step 4: Raise terminal audit exception if any assertion fails
SELECT 
  CASE 
    WHEN COUNT(*) > 0 
      THEN RAISE(ABORT, 'CRITICAL TEST FAILURE: SLA boundary condition breach detected.')
    ELSE 1
  END AS suite_health_status
FROM (
  SELECT test_case_id
  FROM temp_test_manifest t
  WHERE 
    CASE 
      WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 12.00 
        THEN 'SLA Target Achieved'
      WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 24.00 
        THEN 'SLA Standard Window'
      WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) <= 48.00 
        THEN 'SLA Grace Period'
      ELSE 'SLA Critical Breach'
    END != t.expected_tier
    OR
    CASE 
      WHEN ROUND((julianday(t.completed_at) - julianday(t.dispatched_at)) * 24.0, 2) > 48.00 
        THEN ROUND(t.base_rate_usd * 0.15, 2)
      ELSE 0.00
    END != t.expected_penalty
);

-- Clean up temporary test table
DROP TABLE IF EXISTS temp_test_manifest;

COMMIT;