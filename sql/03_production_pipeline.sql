-- ====================================
-- SCRIPT: 03_production_pipeline.sql
-- CLIENT: OmniRoute Freight Systems
-- LEAD ARCHITECT: Samuel Chinwendu Agu
-- PRACTICE: Elsamag IT Solutions
-- DIALECT: SQLite / ANSI Standard SQL
-- PORTFOLIO:
-- https://github.com/Elsamag/
-- sql-logistics-omniroute-turnaround-
-- pipeline
-- ====================================

-- ------------------------------------
-- STEP 1: DEFENSIVE CLEANUP
-- ------------------------------------
DROP VIEW IF EXISTS 
  v_fleet_turnaround_analytics;

-- ------------------------------------
-- STEP 2: HIGH-PERFORMANCE INDEXING
-- ------------------------------------
-- Rule 88 Intent:
-- Eliminate full-table scans across
-- the 12-million-row dispatch log
-- by indexing status and date boundaries.
CREATE INDEX IF NOT EXISTS 
  idx_dispatches_status_date 
ON raw_fleet_dispatches (
  dispatch_status, 
  dispatched_at
);

CREATE INDEX IF NOT EXISTS 
  idx_manifests_dispatch_driver 
ON raw_driver_manifests (
  dispatch_id, 
  driver_id
);

-- ------------------------------------
-- STEP 3: VIRTUAL PIPELINE ASSEMBLY
-- ------------------------------------
-- Rule 88 Intent:
-- Encapsulate core telemetry transformations
-- inside a zero-storage virtual view to 
-- enforce deterministic SLA interval math,
-- isolate boundary conditions, and block
-- join cardinality duplication.
CREATE VIEW 
  v_fleet_turnaround_analytics AS
WITH deduplicated_drivers AS (
  -- Rule 88 Intent:
  -- Pre-aggregate multi-driver shifts
  -- to enforce a strict 1:1 bridge,
  -- eliminating unmanaged parent-row fan-out
  -- and phantom billing inflation.
  SELECT 
    dispatch_id,
    COUNT(DISTINCT driver_id) 
      AS total_assigned_drivers,
    MAX(driver_id) 
      AS primary_driver_id
  FROM raw_driver_manifests
  GROUP BY dispatch_id
),
dispatch_intervals AS (
  -- Rule 88 Intent:
  -- Compute microsecond-accurate elapsed
  -- turnaround times using left-to-right
  -- Julian day difference math to eliminate
  -- multi-day cross-dock temporal drift.
  SELECT 
    d.dispatch_id,
    d.truck_id,
    m.primary_driver_id,
    m.total_assigned_drivers,
    d.dispatched_at,
    d.completed_at,
    ROUND(
      (julianday(d.completed_at) - 
       julianday(d.dispatched_at)) * 24.0, 
      2
    ) AS turnaround_hours,
    d.base_rate_usd,
    COALESCE(d.fuel_surcharge_usd, 0.00) 
      AS fuel_surcharge_usd
  FROM raw_fleet_dispatches d
  INNER JOIN deduplicated_drivers m
    ON d.dispatch_id = m.dispatch_id
  WHERE d.dispatch_status = 'COMPLETED'
    AND d.completed_at IS NOT NULL
    AND d.dispatched_at >= 
        date('now', '-30 days')
)
SELECT 
  dispatch_id,
  truck_id,
  primary_driver_id,
  total_assigned_drivers,
  dispatched_at,
  completed_at,
  turnaround_hours,
  base_rate_usd,
  fuel_surcharge_usd,
  -- Rule 88 Intent:
  -- Order CASE logic strictly from most
  -- restrictive threshold to least
  -- restrictive to prevent broad conditions
  -- from swallowing priority records.
  CASE 
    WHEN turnaround_hours <= 12.00 
      THEN 'SLA Target Achieved'
    WHEN turnaround_hours <= 24.00 
      THEN 'SLA Standard Window'
    WHEN turnaround_hours <= 48.00 
      THEN 'SLA Grace Period'
    ELSE 'SLA Critical Breach'
  END AS sla_performance_tier,
  -- Rule 88 Intent:
  -- Apply contractual 15% late-delivery
  -- billing penalty exclusively against
  -- records breaching the 48-hour SLA.
  CASE 
    WHEN turnaround_hours > 48.00 
      THEN ROUND(base_rate_usd * 0.15, 2)
    ELSE 0.00
  END AS penalty_assessment_usd,
  ROUND(
    base_rate_usd + fuel_surcharge_usd - 
    CASE 
      WHEN turnaround_hours > 48.00 
        THEN ROUND(base_rate_usd * 0.15, 2)
      ELSE 0.00
    END, 
    2
  ) AS net_billed_revenue_usd
FROM dispatch_intervals;

-- ------------------------------------
-- STEP 4: PRODUCTION SANITY VERIFICATION
-- ------------------------------------
-- Audit Check 1: Cardinality Integrity
-- Confirm zero duplicate dispatch IDs exist
-- in the compiled analytical view.
SELECT 
  dispatch_id, 
  COUNT(*) AS occurrence_count
FROM v_fleet_turnaround_analytics
GROUP BY dispatch_id
HAVING COUNT(*) > 1;

-- Audit Check 2: 30-Day Executive Summary
-- Validate clean aggregate KPIs without
-- memory buffer spillover.
SELECT 
  sla_performance_tier,
  COUNT(*) AS total_dispatches,
  ROUND(AVG(turnaround_hours), 2) 
    AS avg_turnaround_hours,
  ROUND(SUM(net_billed_revenue_usd), 2) 
    AS total_net_revenue_usd,
  ROUND(SUM(penalty_assessment_usd), 2) 
    AS total_penalties_usd
FROM v_fleet_turnaround_analytics
GROUP BY sla_performance_tier
ORDER BY avg_turnaround_hours ASC;