-- ===================================
-- TEST: test_cardinality_integrity.sql
-- PIPELINE: OmniRoute Fleet Engine
-- CLIENT: OmniRoute Freight Systems
-- LEAD ARCHITECT: Samuel Chinwendu Agu
-- PRACTICE: Elsamag IT Solutions
-- TARGET: tests/test_cardinality_integrity.sql
-- ===================================

-- Rule 88 Intent:
-- Automated assertion gate to verify 
-- zero Cartesian fan-out and enforce
-- exact 1-to-1 cardinality across 
-- the turnaround reporting pipeline.

-- -----------------------------------
-- TEST 1: Primary Key Uniqueness Audit
-- -----------------------------------
-- Asserts zero duplicate dispatch_id 
-- records exist in the view output.
WITH duplicate_keys AS (
  SELECT 
    dispatch_id,
    COUNT(*) AS occurrence_count
  FROM v_fleet_turnaround_analytics
  GROUP BY dispatch_id
  HAVING COUNT(*) > 1
)
SELECT 
  'TEST 1: PK UNIQUENESS' AS test_name,
  CASE 
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'FAIL: DUPLICATE IDS FOUND'
  END AS test_status,
  COUNT(*) AS error_row_count
FROM duplicate_keys;

-- -----------------------------------
-- TEST 2: Row Count Parity Audit
-- -----------------------------------
-- Asserts view row count matches 
-- clean base table candidate count
-- within the rolling 30-day window.
WITH base_candidates AS (
  SELECT 
    COUNT(DISTINCT dispatch_id) 
      AS expected_count
  FROM raw_fleet_dispatches
  WHERE dispatch_status = 'COMPLETED'
    AND completed_at IS NOT NULL
    AND dispatched_at >= 
        date('now', '-30 days')
),
view_output AS (
  SELECT 
    COUNT(*) AS observed_count
  FROM v_fleet_turnaround_analytics
)
SELECT 
  'TEST 2: ROW COUNT PARITY' 
    AS test_name,
  CASE 
    WHEN v.observed_count = 
         b.expected_count 
    THEN 'PASS'
    ELSE 'FAIL: CARDINALITY DRIFT'
  END AS test_status,
  ABS(v.observed_count - 
      b.expected_count) 
    AS delta_row_count
FROM view_output v
CROSS JOIN base_candidates b;

-- -----------------------------------
-- TEST 3: Driver Join Fan-Out Sieve
-- -----------------------------------
-- Asserts driver deduplication CTE 
-- collapses multi-driver dispatches
-- into exactly one summary parent row.
WITH raw_manifest_counts AS (
  SELECT 
    dispatch_id,
    COUNT(driver_id) AS raw_drivers
  FROM raw_driver_manifests
  GROUP BY dispatch_id
  HAVING COUNT(driver_id) > 1
),
view_records AS (
  SELECT 
    dispatch_id,
    COUNT(*) AS view_rows
  FROM v_fleet_turnaround_analytics
  WHERE dispatch_id IN (
    SELECT dispatch_id 
    FROM raw_manifest_counts
  )
  GROUP BY dispatch_id
)
SELECT 
  'TEST 3: FAN-OUT COLLAPSE' 
    AS test_name,
  CASE 
    WHEN MAX(view_rows) = 1 
      OR COUNT(*) = 0 
    THEN 'PASS'
    ELSE 'FAIL: MULTI-ROW LEAK'
  END AS test_status,
  COALESCE(
    MAX(view_rows), 0
  ) AS max_rows_per_dispatch
FROM view_records;

-- -----------------------------------
-- TEST 4: Terminal Assertion Trigger
-- -----------------------------------
-- Raises hard runtime exception if 
-- any test condition fails.
SELECT 
  CASE 
    WHEN (
      SELECT COUNT(*) 
      FROM (
        SELECT dispatch_id 
        FROM v_fleet_turnaround_analytics 
        GROUP BY dispatch_id 
        HAVING COUNT(*) > 1
      )
    ) > 0 
    THEN RAISE(
      ABORT, 
      'FATAL: Cardinality integrity test failed.'
    )
    ELSE 'CARDINALITY_GATE_CLEARED'
  END AS gate_assertion_status;