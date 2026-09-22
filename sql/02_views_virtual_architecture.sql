-- ============================================================================
-- SCRIPT: 02_views_virtual_architecture.sql
-- SYSTEM: OmniRoute Freight Systems
-- REPO: sql-logistics-omniroute-turnaround-pipeline
-- AUTHOR: Samuel Chinwendu Agu
-- ROLE: Lead Technical Consultant
-- PRACTICE: Elsamag IT Solutions
-- DIALECT: SQLite / ANSI SQL Compatible
-- ============================================================================

-- Clean slate initialization for views
DROP VIEW IF EXISTS v_fleet_turnaround_sla_master;
DROP VIEW IF EXISTS v_dispatch_temporal_intervals;
DROP VIEW IF EXISTS v_manifest_driver_summary;

-- ============================================================================
-- 1. DRIVER ASSIGNMENT SUMMARY VIEW
-- ============================================================================

-- Rule 88 Intent:
-- Encapsulate driver manifest records 
-- into a deterministic 1-to-1 virtual
-- table. Pre-aggregating driver rows
-- stops downstream Cartesian joins 
-- from multiplying dispatch billing.
CREATE VIEW v_manifest_driver_summary AS
SELECT 
  dispatch_id,
  COUNT(DISTINCT driver_id) 
    AS assigned_driver_count,
  MAX(driver_id) 
    AS primary_driver_id,
  MIN(assigned_at) 
    AS first_assigned_at,
  MAX(assigned_at) 
    AS last_assigned_at
FROM raw_driver_manifests
GROUP BY dispatch_id;

-- ============================================================================
-- 2. TEMPORAL INTERVAL RESOLUTION VIEW
-- ============================================================================

-- Rule 88 Intent:
-- Standardize elapsed trip turnaround
-- time using deterministic Julian day
-- math. Enforces upstream date filtering
-- so consumers never query unindexed
-- historical rows.
CREATE VIEW v_dispatch_temporal_intervals AS
SELECT 
  d.dispatch_id,
  d.truck_id,
  d.origin_hub_id,
  d.destination_hub_id,
  d.dispatch_status,
  d.dispatched_at,
  d.completed_at,
  ROUND(
    (julianday(d.completed_at) - 
     julianday(d.dispatched_at)) * 24.0, 
    2
  ) AS turnaround_hours,
  d.base_rate_usd,
  d.fuel_surcharge_usd
FROM raw_fleet_dispatches d
WHERE d.dispatch_status = 'COMPLETED'
  AND d.completed_at IS NOT NULL
  AND d.dispatched_at IS NOT NULL
  AND d.dispatched_at <= d.completed_at;

-- ============================================================================
-- 3. FLEET TURNAROUND SLA MASTER VIEW
-- ============================================================================

-- Rule 88 Intent:
-- Consolidate clean intervals and 
-- driver manifests into an audited
-- executive consumption view.
-- Applies strict top-to-bottom CASE 
-- logic to bin turnaround tiers and
-- assess breach penalties.
CREATE VIEW v_fleet_turnaround_sla_master AS
SELECT 
  ti.dispatch_id,
  ti.truck_id,
  COALESCE(ds.primary_driver_id, 'UNASSIGNED') 
    AS primary_driver_id,
  COALESCE(ds.assigned_driver_count, 0) 
    AS total_drivers,
  ti.origin_hub_id,
  ti.destination_hub_id,
  ti.dispatched_at,
  ti.completed_at,
  ti.turnaround_hours,
  ti.base_rate_usd,
  ti.fuel_surcharge_usd,
  ROUND(
    ti.base_rate_usd + ti.fuel_surcharge_usd, 
    2
  ) AS total_gross_revenue_usd,
  CASE 
    WHEN ti.turnaround_hours <= 12.00 
      THEN 'SLA Target Achieved'
    WHEN ti.turnaround_hours <= 24.00 
      THEN 'SLA Standard Window'
    WHEN ti.turnaround_hours <= 48.00 
      THEN 'SLA Grace Period'
    ELSE 'SLA Critical Breach'
  END AS sla_status_tier,
  CASE 
    WHEN ti.turnaround_hours > 48.00 
      THEN ROUND(ti.base_rate_usd * 0.15, 2)
    ELSE 0.00
  END AS penalty_assessment_usd,
  CASE 
    WHEN ti.turnaround_hours > 48.00 
      THEN ROUND(
        (ti.base_rate_usd + ti.fuel_surcharge_usd) 
        - (ti.base_rate_usd * 0.15), 
        2
      )
    ELSE ROUND(
      ti.base_rate_usd + ti.fuel_surcharge_usd, 
      2
    )
  END AS net_settlement_revenue_usd
FROM v_dispatch_temporal_intervals ti
LEFT JOIN v_manifest_driver_summary ds
  ON ti.dispatch_id = ds.dispatch_id;