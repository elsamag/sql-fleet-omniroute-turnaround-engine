-- ============================================================================
-- SCRIPT: 01_schema_ddl.sql
-- PIPELINE: OmniRoute Fleet Telemetry
-- REPO: sql-logistics-omniroute-turnaround-pipeline
-- CLIENT: OmniRoute Freight Systems
-- AUTHOR: Samuel Chinwendu Agu
-- ROLE: Lead Technical Consultant
-- PRACTICE: Elsamag IT Solutions
-- DIALECT: SQLite / ANSI SQL Compatible
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- TABLE 1: raw_fleet_dispatches
-- ----------------------------------------------------------------------------
-- Rule 88 Architectural Intent:
-- Stores immutable trip telemetry records. 
-- Captures state transitions, timestamps, 
-- and commercial freight billing baselines.
-- Primary key constraints prevent trip
-- identifier collisions across regions.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS raw_fleet_dispatches;

CREATE TABLE raw_fleet_dispatches (
  dispatch_id TEXT NOT NULL,
  truck_id TEXT NOT NULL,
  origin_hub_id TEXT NOT NULL,
  destination_hub_id TEXT NOT NULL,
  dispatched_at TEXT NOT NULL,
  completed_at TEXT,
  dispatch_status TEXT NOT NULL,
  cargo_weight_kg REAL NOT NULL,
  base_rate_usd REAL NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_raw_fleet_dispatches 
    PRIMARY KEY (dispatch_id),
  CONSTRAINT chk_dispatch_status 
    CHECK (
      dispatch_status IN (
        'PENDING',
        'DISPATCHED',
        'IN_TRANSIT',
        'COMPLETED',
        'CANCELLED'
      )
    ),
  CONSTRAINT chk_base_rate_positive 
    CHECK (base_rate_usd >= 0.00),
  CONSTRAINT chk_cargo_weight_positive 
    CHECK (cargo_weight_kg > 0.00)
);

-- ----------------------------------------------------------------------------
-- TABLE 2: raw_driver_manifests
-- ----------------------------------------------------------------------------
-- Rule 88 Architectural Intent:
-- Captures driver assignments and crew 
-- shift logs per freight movement.
-- Implements explicit foreign keys to 
-- enforce referential integrity.
-- Serves as the source of one-to-many
-- relationship fan-out hazards.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS raw_driver_manifests;

CREATE TABLE raw_driver_manifests (
  manifest_id TEXT NOT NULL,
  dispatch_id TEXT NOT NULL,
  driver_id TEXT NOT NULL,
  shift_role TEXT NOT NULL,
  assigned_at TEXT NOT NULL,
  released_at TEXT,
  CONSTRAINT pk_raw_driver_manifests 
    PRIMARY KEY (manifest_id),
  CONSTRAINT fk_manifest_dispatch 
    FOREIGN KEY (dispatch_id) 
    REFERENCES raw_fleet_dispatches (dispatch_id) 
    ON DELETE RESTRICT 
    ON UPDATE CASCADE,
  CONSTRAINT chk_shift_role 
    CHECK (
      shift_role IN (
        'PRIMARY',
        'RELIEF',
        'ESCORT',
        'TRAINEE'
      )
    )
);

-- ----------------------------------------------------------------------------
-- TABLE 3: raw_telemetry_events
-- ----------------------------------------------------------------------------
-- Rule 88 Architectural Intent:
-- High-frequency IoT waypoint pings.
-- Tracks GPS checkpoints and speed
-- metrics between terminal gates.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS raw_telemetry_events;

CREATE TABLE raw_telemetry_events (
  event_id TEXT NOT NULL,
  dispatch_id TEXT NOT NULL,
  event_timestamp TEXT NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  speed_kmh REAL NOT NULL,
  fuel_level_pct REAL NOT NULL,
  CONSTRAINT pk_raw_telemetry_events 
    PRIMARY KEY (event_id),
  CONSTRAINT fk_telemetry_dispatch 
    FOREIGN KEY (dispatch_id) 
    REFERENCES raw_fleet_dispatches (dispatch_id) 
    ON DELETE CASCADE,
  CONSTRAINT chk_speed_positive 
    CHECK (speed_kmh >= 0.00),
  CONSTRAINT chk_fuel_range 
    CHECK (
      fuel_level_pct >= 0.00 
      AND fuel_level_pct <= 100.00
    )
);

-- ============================================================================
-- PERFORMANCE OPTIMIZATION: DEFENSIVE INDEX TOPOLOGY
-- ============================================================================

-- Rule 88 Architectural Intent:
-- Eliminates unindexed table scans on
-- routine 30-day reporting windows.
-- Enables composite index seek on
-- status and temporal boundary gates.
CREATE INDEX IF NOT EXISTS idx_dispatches_status_date 
  ON raw_fleet_dispatches (
    dispatch_status, 
    dispatched_at
  );

-- Rule 88 Architectural Intent:
-- Optimizes join resolution between
-- dispatch parent records and driver
-- manifest child rows, preventing
-- full scans on deduplication filters.
CREATE INDEX IF NOT EXISTS idx_manifests_dispatch_driver 
  ON raw_driver_manifests (
    dispatch_id, 
    driver_id
  );

-- Rule 88 Architectural Intent:
-- Accelerates chronological ordering 
-- and spatial route reconciliation
-- during waypoint forensic audits.
CREATE INDEX IF NOT EXISTS idx_telemetry_dispatch_time 
  ON raw_telemetry_events (
    dispatch_id, 
    event_timestamp
  );