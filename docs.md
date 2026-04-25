# Data Warehouse & Data Mining — Project Documentation

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Repository Structure](#3-repository-structure)
4. [Tech Stack](#4-tech-stack)
5. [Data Layer](#5-data-layer)
6. [Backend API](#6-backend-api)
7. [Frontend](#7-frontend)
8. [SSAS Cubes](#8-ssas-cubes)
9. [Getting Started](#9-getting-started)
10. [API Reference](#10-api-reference)
11. [OLAP Operations](#11-olap-operations)

---

## 1. Project Overview

An end-to-end OLAP analytics platform built for retail data analysis. It ingests raw CSV retail transaction data, transforms it into a SQL Server star-schema data warehouse, and exposes five classic OLAP operations through a .NET REST API consumed by a React dashboard.

**Core capabilities:**
- KPI summaries (revenue, quantity, customers, products, transactions)
- Sales trend analysis by year/quarter/month
- City-level and product-level breakdowns
- Inventory tracking
- Interactive OLAP: Roll-up, Drill-down, Slice, Dice, Pivot
- Dual-mode query engine: SSAS MDX (preferred) with SQL Server fallback

---

## 2. Architecture

```
┌─────────────────────┐
│   React Web UI      │  Vite SPA — port 5173
└──────────┬──────────┘
           │ HTTP/REST (/api/*)
┌──────────▼──────────┐
│   .NET 10 API       │  ASP.NET Core — port 5000/5001
└──────────┬──────────┘
           │
  ┌────────┴────────┐
  │                 │
  ▼                 ▼
SSAS MDX        SQL Server      ← OlapService tries SSAS first,
(preferred)     (fallback)        falls back to T-SQL if unavailable
  │                 │
  └────────┬────────┘
           ▼
   DataWarehouse DB             ← Star schema (SQL Server)
   Dim_Time / Dim_Customer
   Dim_Product / Fact_Sales
   Fact_Inventory
           │
           │ ETL (etl.sql)
           ▼
   DatabaseMock DB              ← Staging / source-of-truth
           │
           │ BULK INSERT
           ▼
   CSV files (retail data)
```

**Request flow:**
1. User interacts with React UI → Axios sends `GET /api/olap/<operation>` or `GET /api/dashboard/<metric>`
2. API controller calls `OlapService`
3. `OlapService` attempts MDX query against SSAS; on failure, runs equivalent T-SQL against `DataWarehouse`
4. Results serialized as `OlapResult` JSON → React renders table + recharts chart

---

## 3. Repository Structure

```
data-warehouse-and-data-mining/
├── apps/
│   ├── api/                  # .NET 10 C# backend
│   ├── web/                  # React + TypeScript frontend
│   └── dataCubes/            # SSAS Multidimensional project
├── migration/
│   ├── init_staging_db.sql   # Create DatabaseMock schema
│   ├── init_data_warehouse.sql # Create DataWarehouse star schema
│   ├── etl.sql               # Load dimensions and facts from staging
│   └── mock_staging_data.sql # Populate staging via BULK INSERT from CSV
├── clean.py                  # Python script: clean raw CSV → cleaned_data_final.csv
├── cleaned_data_final.csv    # ~31 MB cleaned retail data
├── mock_data.csv             # ~44 MB raw mock data
└── package.json              # Root monorepo scripts
```

---

## 4. Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React 19, TypeScript 6, Vite 8 |
| Charts | Recharts 3 |
| HTTP client | Axios |
| Backend | ASP.NET Core (.NET 10), C# |
| ORM | Dapper |
| OLAP engine | SSAS Multidimensional (MDX) |
| SSAS client | Microsoft.AnalysisServices.AdomdClient 19 |
| SQL driver | Microsoft.Data.SqlClient 7 |
| Database | SQL Server (instance: `localhost\MSSQLSERVER01`) |
| Data prep | Python + pandas |

---

## 5. Data Layer

### 5.1 Source Data

Raw data comes from a UK online retail CSV dataset. `clean.py` filters to UK-only rows, removes nulls, and converts types to produce `cleaned_data_final.csv`.

### 5.2 Staging Database — `DatabaseMock`

Mirrors the operational schema. Populated via `mock_staging_data.sql` (BULK INSERT from CSV).

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `VANPHONGDAIDIEN` | MaTP, TenTP | Branch offices |
| `CUAHANG` | MaCH, MaTP | Stores (linked to branches) |
| `KHACHHANG` | MaKH, LoaiKH, ThanhPho | Customers (types: DL, BD, CA) |
| `KHACHHANG_DULICH` | — | Tour customer subtype |
| `KHACHHANG_BUUDIEN` | — | Postal customer subtype |
| `MATHANG` | MaMH, MoTa, Size, Weight, Gia | Products |
| `MHLUUTRU` | MaCH, MaMH, SoLuong | Inventory per store |
| `DONDATHANG` | MaDon, MaKH, NgayDat | Order headers |
| `MHDUOCDAT` | MaDon, MaMH, SoLuong, DonGia | Order line items |

### 5.3 Data Warehouse — `DataWarehouse`

Star schema optimized for OLAP queries.

**Dimensions:**

| Table | Key | Notable Columns |
|-------|-----|-----------------|
| `Dim_Time` | TimeID (YYYYMM) | Year, Quarter, Month — spans 2010–2035 |
| `Dim_Customer` | CustomerID | TenKH, LoaiKH, ThanhPho |
| `Dim_Product` | ProductID | MoTa, Size, Weight, Gia |

**Facts:**

| Table | Grain | Measures |
|-------|-------|----------|
| `Fact_Sales` | One row per order-product | Quantity, Price, TotalAmount |
| `Fact_Inventory` | One row per product-month | StockQuantity |

All fact tables carry FK indexes on every dimension key for fast join performance.

### 5.4 ETL — `migration/etl.sql`

Run manually (or scheduled) against SQL Server. Steps executed in order:

1. **Dim_Time** — generated with a recursive CTE; no staging dependency
2. **Dim_Customer** — joins `KHACHHANG` + `VANPHONGDAIDIEN` to resolve city
3. **Dim_Product** — directly from `MATHANG`
4. **Fact_Sales** — joins `MHDUOCDAT` + `DONDATHANG`; derives `TimeID` from order date
5. **Fact_Inventory** — from `MHLUUTRU`; TimeID set to current YYYYMM

All steps use `NOT EXISTS` upsert logic — safe to re-run without duplicates.

**To run ETL:**
```sql
-- In SSMS connected to localhost\MSSQLSERVER01
USE DataWarehouse;
GO
-- Run migration/etl.sql
```

---

## 6. Backend API

### 6.1 Project layout (`apps/api/`)

```
apps/api/
├── Controllers/
│   ├── DashboardController.cs   # KPI + chart data endpoints
│   └── OlapController.cs        # 5 OLAP operation endpoints
├── Services/
│   ├── IOlapService.cs          # Interface
│   └── OlapService.cs           # ~556 lines; MDX + SQL implementations
├── Models/
│   └── OlapResult.cs            # DTOs: OlapResult, KpiData
├── Program.cs                   # App startup, DI, CORS
└── appsettings.json             # Connection strings + OlapSettings
```

### 6.2 Configuration (`appsettings.json`)

```json
{
  "ConnectionStrings": {
    "SqlServer": "Server=localhost\\MSSQLSERVER01;Database=DataWarehouse;User Id=duong12;Password=12345678;TrustServerCertificate=True",
    "SSAS": "Data Source=localhost\\MSSQLSERVER01;Catalog=DataWarehouse;Integrated Security=SSPI"
  },
  "OlapSettings": {
    "UseSsas": true
  }
}
```

Set `UseSsas: false` to force SQL-only mode (useful when SSAS is not deployed).

### 6.3 Dual-mode query engine

`OlapService` exposes every operation in two implementations:
- **MDX path** — sends MDX queries to SSAS via `AdomdClient`; faster for pre-aggregated data
- **SQL path** — equivalent T-SQL against `DataWarehouse`; always available as fallback

The `Program.cs` DI registration always uses `OlapService`; the mode is controlled by `OlapSettings.UseSsas` and caught exceptions per call.

---

## 7. Frontend

### 7.1 Project layout (`apps/web/src/`)

```
src/
├── api/
│   └── client.ts               # Axios instance, all API call functions
├── components/
│   ├── Dashboard/
│   │   ├── KPICard.tsx          # Single KPI metric tile
│   │   └── SalesChart.tsx       # Sales trend line/bar chart
│   ├── Layout/
│   │   └── Sidebar.tsx          # Navigation sidebar
│   └── OLAP/
│       ├── RollupPanel.tsx      # Roll-up UI + results
│       ├── DrilldownPanel.tsx   # Drill-down UI + results
│       ├── SlicePanel.tsx       # Slice UI + results
│       ├── DicePanel.tsx        # Dice (multi-filter) UI + results
│       ├── PivotPanel.tsx       # Pivot table UI + results
│       ├── OlapChart.tsx        # Recharts wrapper for OLAP results
│       ├── OlapTable.tsx        # Generic data-grid for OLAP results
│       └── shared.tsx           # Shared form controls, helpers
├── pages/
│   └── AnalyticsPage.tsx        # Main page; renders all panels
├── types/
│   └── index.ts                 # OlapResult, KpiData, and other DTOs
├── App.tsx                      # Root layout (header + outlet)
└── main.tsx                     # ReactDOM.createRoot entry point
```

### 7.2 API proxy

In development, `vite.config.ts` proxies `/api` to the backend:

```ts
proxy: {
  '/api': 'https://olive-synthesis-peter-pizza.trycloudflare.com'
}
```

For local development without Cloudflare, change the proxy target to `http://localhost:5000`.

### 7.3 Data flow in a panel (example: RollupPanel)

1. User selects granularity (Year / Quarter / Month) and clicks **Run**
2. `client.ts` sends `GET /api/olap/rollup?granularity=Month`
3. Response: `{ operationType, columnHeaders: string[], rows: any[][] }`
4. Panel passes data to `<OlapTable>` (renders a `<table>`) and `<OlapChart>` (renders a recharts `<BarChart>`)

---

## 8. SSAS Cubes

Located in `apps/dataCubes/`. This is a Visual Studio SSAS Multidimensional project.

**Cubes:**
- `sale.cube` — Sales fact aggregated by all three dimensions
- `inventory.cube` — Inventory fact aggregated by Product and Time
- `Data Warehouse.cube` — Main combined cube definition

**Dimensions:**
- `Dim Time.dim` — Hierarchy: Year → Quarter → Month
- `Dim Customer.dim` — Attributes: LoaiKH, ThanhPho
- `Dim Product.dim` — Attributes: MoTa, Size, Gia

**Deployment:** Open `dataCubes.sln` in Visual Studio with SSAS tools installed, configure the data source to point to your SQL Server instance, then deploy to SSAS.

**Partitions:** Time-based partitions are defined for incremental cube processing.

---

## 9. Getting Started

### Prerequisites

- Node.js 20+
- .NET SDK 10.0
- SQL Server 2019+ with instance `MSSQLSERVER01`
- (Optional) SQL Server Analysis Services for MDX mode
- Python 3.10+ with pandas (for data prep only)

### Step 1 — Database setup

```bash
# In SSMS or sqlcmd, run in order:
1. migration/init_staging_db.sql     # creates DatabaseMock
2. migration/init_data_warehouse.sql # creates DataWarehouse
3. migration/mock_staging_data.sql   # loads staging from CSV (update file path inside)
4. migration/etl.sql                 # populates DataWarehouse from staging
```

### Step 2 — (Optional) Deploy SSAS cubes

Open `apps/dataCubes/dataCubes.sln` in Visual Studio → Deploy to local SSAS instance.

If skipping SSAS, set `"UseSsas": false` in `apps/api/appsettings.json`.

### Step 3 — Install and run

```bash
# From repo root — installs both web and api dependencies
npm run setup

# Start both services concurrently
npm run dev
```

Individual commands:
```bash
npm run dev:web   # Vite on http://localhost:5173
npm run dev:api   # .NET on http://localhost:5000
```

### Step 4 — Open the app

Navigate to [http://localhost:5173](http://localhost:5173).

---

## 10. API Reference

Base URL: `http://localhost:5000/api`

### Dashboard endpoints

| Method | Path | Query params | Description |
|--------|------|--------------|-------------|
| GET | `/dashboard/kpi` | — | Total revenue, qty, customers, products, transactions |
| GET | `/dashboard/sales-trend` | `granularity` (Year\|Quarter\|Month) | Time-series revenue |
| GET | `/dashboard/by-city` | — | Revenue grouped by customer city |
| GET | `/dashboard/by-product` | — | Revenue grouped by product |
| GET | `/dashboard/inventory` | — | Current stock quantity per product |

### OLAP endpoints

| Method | Path | Query params | Description |
|--------|------|--------------|-------------|
| GET | `/olap/rollup` | `granularity` | Aggregate sales upward along time hierarchy |
| GET | `/olap/drilldown` | `year`, `quarter?` | Expand a time period into finer granularity |
| GET | `/olap/slice` | `dimension`, `value` | Fix one dimension, return the rest |
| GET | `/olap/dice` | `startDate`, `endDate`, `customerType?`, `city?` | Filter across multiple dimensions |
| GET | `/olap/pivot` | `rowDim`, `colDim` | Cross-tabulate two dimensions |

### Response format

All endpoints return `OlapResult`:

```json
{
  "operationType": "RollUp",
  "columnHeaders": ["Month", "TotalRevenue", "TotalQuantity"],
  "rows": [
    ["2023-01", 152430.5, 3200],
    ["2023-02", 98210.0, 2100]
  ]
}
```

KPI endpoint returns `KpiData`:

```json
{
  "totalRevenue": 1250000.0,
  "totalQuantity": 45000,
  "totalCustomers": 320,
  "totalProducts": 85,
  "totalTransactions": 12400
}
```

---

## 11. OLAP Operations

| Operation | What it does | Example |
|-----------|--------------|---------|
| **Roll-up** | Aggregates data along a dimension hierarchy (Month → Quarter → Year) | Total revenue per year |
| **Drill-down** | Expands a summary into finer detail | Click on Q1 2023 → see Jan, Feb, Mar |
| **Slice** | Selects one value of a dimension, returns a lower-dimensional result | Only customers of type "DL" |
| **Dice** | Filters on multiple dimensions simultaneously | 2022–2023, type "CA", city "HCM" |
| **Pivot** | Rotates axes — rows become columns | Products as columns, months as rows |

All five operations are available in both MDX (SSAS) and T-SQL (SQL Server fallback) implementations inside `OlapService.cs`.
