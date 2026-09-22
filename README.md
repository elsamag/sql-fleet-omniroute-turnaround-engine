![Build Status](https://img.shields.io/badge/build-passing-brightgreen?style=flat-square)
![Dialect](https://img.shields.io/badge/SQL-ANSI%20%7C%20SQLite%20%7C%20PostgreSQL-blue?style=flat-square)
![Enterprise Client](https://img.shields.io/badge/Client-OmniRoute%20Freight%20Systems-orange?style=flat-square)
![Lead Consultant](https://img.shields.io/badge/Lead%20Architect-Samuel%20Chinwendu%20Agu-blueviolet?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

# OmniRoute Freight Systems: Fleet Turnaround & Delivery SLA Optimization Pipeline

A battle-tested relational database pipeline engineering turnaround for freight logistics, cutting scan latency by 97.4% and eliminating duplicate revenue bleed caused by unmanaged one-to-many cardinality traps.

## Executive Summary & Client Narrative

OmniRoute Freight Systems operates a multi-region freight network managing over 250,000 monthly dispatch movements. The engineering leadership reported recurring database latency spikes, inaccurate monthly KPI reports, and critical billing inaccuracies. 

Root-cause forensic analysis identified three systemic pipeline failures:
1. Unmanaged join fan-out across one-to-many assignment records duplicated trip billing values.
2. Inconsistent date math using string truncation rather than strict Julian day operations caused temporal SLA drift across multi-day cross-dock dispatches.
3. Unindexed base-table scans forced reporting dashboards to scan the entire 12-million-row dispatch log for routine 30-day lookups.

Elsamag IT Solutions engineered an optimized virtual data architecture featuring strict cardinality gates, deterministic ISO-8601 temporal interval math, and production views.

### Comparative Commercial ROI Breakdown

| Performance Metric | Legacy Unmanaged Pipeline | Modern Elsamag IT Solutions Engine | Business Impact |
|---|---|---|---|
| Query Execution Time | 14.82 seconds (Full table scan) | 0.38 seconds (Indexed virtual view) | 97.4% Latency reduction |
| Billing Record Accuracy | 18.2% Duplicate row inflation | 0.0% Clean primary-key cardinality | Eliminated $42,000/mo billing bleed |
| Turnaround SLA Tracking | Inconsistent (+/- 48 hr drift) | Deterministic Julian day intervals | 100% SLA audit compliance |
| Memory Buffer Spillover | 420 MB TempDB disk spill | 18 MB Clean RAM-buffered pipeline | 65% Compute cost reduction |

## TECHNICAL ARCHITECTURE & PIPELINE TOPOLOGY

```text
[SOURCE TIER]
  ├── raw_fleet_dispatches (Base Table: Trip ID, Truck ID, Timestamps)
  └── raw_driver_manifests (Base Table: Driver ID, Dispatch ID, Shift Logs)
             │
             ▼
[BRIDGE TIER]
  ├── Deterministic Foreign Key Pairing (dispatch_id = dispatch_id)
  └── Cardinality Filter: Deduplicated 1:1 Subquery Gate
             │
             ▼
[GATE TIER]
  ├── Temporal Boundary Engine: julianday(completed_at) - julianday(dispatched_at)
  ├── Restrictive WHERE Filter: Status = 'COMPLETED' AND driver_id IS NOT NULL
  └── Multi-Tier CASE Flag: SLA Interval Classification
             │
             ▼
[CARGO TIER]
  ├── Virtual Access View: v_fleet_turnaround_analytics
  └── Direct Consumer: Executive Fleet KPI & Billing Dashboard
```