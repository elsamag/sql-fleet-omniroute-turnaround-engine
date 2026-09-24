-- ============================================================================
-- SCRIPT: sql/01_schema_ddl.sql
-- REPO: sql-logistics-omniroute-turnaround-pipeline
-- CLIENT: OmniRoute Freight Systems
-- AUTHOR: Samuel Chinwendu Agu | Elsamag IT Solutions
-- DIALECT: SQLite / ANSI Standard SQL Compatible
-- ============================================================================

-- Rule 88 Architectural Intent:
-- Define base operational tables, composite indexes for 30-day temporal scans,
-- and seed deterministic fixture data to validate cardinality in CI/CD.

DROP TABLE IF EXISTS raw_driver_manifests;
DROP TABLE IF EXISTS raw_fleet_dispatches;

CREATE TABLE raw_fleet_dispatches (
  dispatch_id TEXT PRIMARY KEY,
  truck_id TEXT NOT NULL,
  dispatched_at TEXT NOT NULL,
  completed_at TEXT,
  dispatch_status TEXT NOT NULL,
  base_rate_usd REAL NOT NULL
);

CREATE TABLE raw_driver_manifests (
  manifest_id TEXT PRIMARY KEY,
  dispatch_id TEXT NOT NULL,
  driver_id TEXT NOT NULL,
  assigned_at TEXT NOT NULL,
  FOREIGN KEY (dispatch_id) REFERENCES raw_fleet_dispatches(dispatch_id)
);

CREATE INDEX idx_dispatches_status_date 
ON raw_fleet_dispatches (dispatch_status, dispatched_at);

CREATE INDEX idx_manifests_dispatch_driver 
ON raw_driver_manifests (dispatch_id, driver_id);

-- Seed CI Fixtures: Includes deliberate 1-to-many driver assignments
INSERT INTO raw_fleet_dispatches VALUES
  ('DSP-1001', 'TRK-01', datetime('now', '-5 days'), datetime('now', '-4 days'), 'COMPLETED', 1200.00),
  ('DSP-1002', 'TRK-02', datetime('now', '-3 days'), datetime('now', '-1 days'), 'COMPLETED', 1850.00),
  ('DSP-1003', 'TRK-03', datetime('now', '-2 days'), NULL, 'IN_TRANSIT', 950.00),
  ('DSP-1004', 'TRK-04', datetime('now', '-40 days'), datetime('now', '-38 days'), 'COMPLETED', 2100.00);

-- DSP-1001 has two drivers assigned (tests cardinality fan-out prevention)
INSERT INTO raw_driver_manifests VALUES
  ('MNF-501', 'DSP-1001', 'DRV-88', datetime('now', '-5 days')),
  ('MNF-502', 'DSP-1001', 'DRV-99', datetime('now', '-5 days')),
  ('MNF-503', 'DSP-1002', 'DRV-12', datetime('now', '-3 days')),
  ('MNF-504', 'DSP-1003', 'DRV-44', datetime('now', '-2 days')),
  ('MNF-505', 'DSP-1004', 'DRV-77', datetime('now', '-40 days'));
