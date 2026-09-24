DROP VIEW IF EXISTS v_fleet_turnaround_analytics;

CREATE VIEW v_fleet_turnaround_analytics AS
WITH deduplicated_drivers AS (
  SELECT 
    dispatch_id,
    COUNT(DISTINCT driver_id) AS total_assigned_drivers,
    MAX(driver_id) AS primary_driver_id
  FROM raw_driver_manifests
  GROUP BY dispatch_id
),
dispatch_intervals AS (
  SELECT 
    d.dispatch_id,
    d.truck_id,
    m.primary_driver_id,
    m.total_assigned_drivers,
    d.dispatched_at,
    d.completed_at,
    ROUND(
      (julianday(d.completed_at) - julianday(d.dispatched_at)) * 24.0, 
      2
    ) AS turnaround_hours,
    d.base_rate_usd
  FROM raw_fleet_dispatches d
  INNER JOIN deduplicated_drivers m
    ON d.dispatch_id = m.dispatch_id
  WHERE d.dispatch_status = 'COMPLETED'
    AND d.completed_at IS NOT NULL
    AND d.dispatched_at >= date('now', '-30 days')
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
  CASE 
    WHEN turnaround_hours <= 12.00 THEN 'SLA Target Achieved'
    WHEN turnaround_hours <= 24.00 THEN 'SLA Standard Window'
    WHEN turnaround_hours <= 48.00 THEN 'SLA Grace Period'
    ELSE 'SLA Critical Breach'
  END AS sla_performance_tier,
  CASE 
    WHEN turnaround_hours > 48.00 THEN ROUND(base_rate_usd * 0.15, 2)
    ELSE 0.00
  END AS penalty_assessment_usd
FROM dispatch_intervals;
