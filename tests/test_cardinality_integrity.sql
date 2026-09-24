-- ============================================================================
-- SCRIPT: tests/test_cardinality_integrity.sql
-- REPO: sql-logistics-omniroute-turnaround-pipeline
-- CLIENT: OmniRoute Freight Systems
-- AUTHOR: Samuel Chinwendu Agu | Elsamag IT Solutions
-- DIALECT: SQLite / ANSI Standard SQL Compatible
-- ============================================================================

-- Rule 88 Architectural Intent:
-- Enforce strict 1-to-1 cardinality validation using a portable CHECK 
-- constraint gate. Any duplicate fan-out immediately throws a fatal 
-- constraint violation that halts CI with exit code 1.

.bail on

DROP TABLE IF EXISTS temp_assertion_gate;

CREATE TEMP TABLE temp_assertion_gate (
  assertion_name TEXT PRIMARY KEY,
  actual_count INTEGER NOT NULL,
  expected_count INTEGER NOT NULL,
  passed INTEGER CHECK(passed = 1)
);

-- Assertion 1: Verify view output row count matches unique completed dispatches exactly
INSERT INTO temp_assertion_gate (assertion_name, actual_count, expected_count, passed)
SELECT 
  'cardinality_1_to_1_parity' AS assertion_name,
  (SELECT COUNT(*) FROM v_fleet_turnaround_analytics) AS actual_count,
  (SELECT COUNT(DISTINCT d.dispatch_id) 
   FROM raw_fleet_dispatches d
   WHERE d.dispatch_status = 'COMPLETED' 
     AND d.completed_at IS NOT NULL
     AND d.dispatched_at >= date('now', '-30 days')) AS expected_count,
  CASE 
    WHEN (SELECT COUNT(*) FROM v_fleet_turnaround_analytics) = 
         (SELECT COUNT(DISTINCT d.dispatch_id) 
          FROM raw_fleet_dispatches d
          WHERE d.dispatch_status = 'COMPLETED' 
            AND d.completed_at IS NOT NULL
            AND d.dispatched_at >= date('now', '-30 days'))
    THEN 1 
    ELSE 0 
  END AS passed;

-- Assertion 2: Verify zero duplicate dispatch_id records exist in the view
INSERT INTO temp_assertion_gate (assertion_name, actual_count, expected_count, passed)
SELECT 
  'zero_duplicate_dispatch_ids' AS assertion_name,
  (SELECT COUNT(*) 
   FROM (
     SELECT dispatch_id 
     FROM v_fleet_turnaround_analytics 
     GROUP BY dispatch_id 
     HAVING COUNT(*) > 1
   )) AS actual_count,
  0 AS expected_count,
  CASE 
    WHEN (SELECT COUNT(*) 
          FROM (
            SELECT dispatch_id 
            FROM v_fleet_turnaround_analytics 
            GROUP BY dispatch_id 
            HAVING COUNT(*) > 1
          )) = 0 
    THEN 1 
    ELSE 0 
  END AS passed;

SELECT 
  assertion_name,
  actual_count,
  expected_count,
  'PASS' AS test_status
FROM temp_assertion_gate;

DROP TABLE temp_assertion_gate;
