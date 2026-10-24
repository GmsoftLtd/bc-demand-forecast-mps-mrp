# BC Time Series Demand Forecast

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Business Central](https://img.shields.io/badge/BC-v29+-blue.svg)](https://learn.microsoft.com/en-us/dynamics365/business-central/)

A free, MIT-licensed Business Central extension that turns posted sales (or consumption) into a **demand forecast that MPS and MRP really use**. It calls the forecasting engine every tenant already has: codeunit 2000 **"Time Series Management"** (Azure AI time series: ARIMA, ETS, STL, TBATS).

**Companion blog post:** [Codeunit 2000 Forecasting in Business Central: From Sales History to MPS and MRP](https://insidebusinesscentral.com/codeunit-2000-time-series-forecast-mps-mrp/)

> If this saves you time, please **star the repo**. It helps other Business Central folks find it.

Part of the replenishment set:

- [bc-safety-stock](https://github.com/GmsoftLtd/bc-safety-stock): how much buffer to hold (50100-50199)
- [bc-eoq-calculator](https://github.com/GmsoftLtd/bc-eoq-calculator): how much to order (50200-50299)
- [bc-reorder-point](https://github.com/GmsoftLtd/bc-reorder-point): when to order (50300-50399)
- [bc-replenishment-policy](https://github.com/GmsoftLtd/bc-replenishment-policy): which policy (50400-50499)
- **bc-demand-forecast-mps-mrp**: what demand to plan for (50500-50599)

---

## What it does

```mermaid
flowchart TB
    subgraph A["1. Forecast with codeunit 2000"]
        direction LR
        ILE[("Item Ledger Entries<br/>Sale or Consumption")] -->|PrepareData| TSB["Time Series Buffer<br/>table 2000"]
        TSB -->|Forecast| SVC{{"Azure AI<br/>time series service"}}
        SVC -->|GetForecast| TSF["Time Series Forecast<br/>table 2001"]
    end
    subgraph B["2. Plan with MPS and MRP"]
        direction LR
        PFE[("Demand Forecast<br/>Entries")] --> SETUP["Inventory Setup<br/>Current Demand Forecast"]
        SETUP --> PLAN["Planning Worksheet<br/>Calculate Regenerative Plan"]
        PLAN --> PO["Planned production<br/>and purchase orders"]
    end
    TSF -->|"your code: Qty = -Value"| PFE
    classDef bc fill:#e8f0fb,stroke:#0b1f3a,color:#0b1f3a;
    classDef ai fill:#fff1e8,stroke:#ff6b35,color:#0b1f3a;
    class ILE,TSB,TSF,PFE,SETUP,PLAN,PO bc;
    class SVC ai;
```

1. Reads Item Ledger Entries of type **Sale** (or **Consumption**) for the filtered items.
2. Sends one series per item to codeunit 2000 with `PrepareData`, `Forecast` and `GetForecast`.
3. Flips the sign (sales are negative in the ledger), optionally drops lines whose range (Delta %) is too wide.
4. Replaces the future **Demand Forecast Entries** of those items in the forecast you choose.
5. Optionally makes it the **Current Demand Forecast** in Inventory Setup.

| Demand Source | Forecast type written | Used by |
|---|---|---|
| Sales | Sales Item | MPS (independent demand, consumed by sales) |
| Consumption | Component | MRP (dependent demand, consumed by component need) |

## How it calls codeunit 2000

```mermaid
sequenceDiagram
    autonumber
    participant R as Report "Create Time Series Forecast"
    participant B as Codeunit "Demand Forecast Builder"
    participant T as Codeunit 2000 "Time Series Management"
    participant S as Azure AI time series service
    participant F as Production Forecast Entry
    R->>B: SetParameters(name, source, period, history, horizon, model...)
    R->>B: ForecastItems(Item)
    loop each batch of items
        B->>T: Initialize('', NoKey, 0, true)
        B->>T: PrepareData(ItemLedgerEntry, "Item No.", "Posting Date", Quantity, Month, start, 24)
        Note right of T: sums Quantity per item and month,<br/>fills empty months with 0
        B->>T: Forecast(6, 80, ARIMA)
        T->>S: send series
        S-->>T: forecast + range
        B->>T: GetForecast(TempTimeSeriesForecast)
        B->>F: delete future entries, insert new ones (Qty = -Value)
    end
    R->>B: SetAsCurrentDemandForecast() (optional)
```

```al
TimeSeriesManagement.Initialize('', NoKey, 0, true);   // BC online, Microsoft-hosted service
TimeSeriesManagement.PrepareData(
    ItemLedgerEntry,
    ItemLedgerEntry.FieldNo("Item No."),      // one series per item
    ItemLedgerEntry.FieldNo("Posting Date"),
    ItemLedgerEntry.FieldNo(Quantity),
    DateRec."Period Type"::Month,
    ForecastStart,                            // history runs back from this date
    24);                                      // periods of history
TimeSeriesManagement.Forecast(6, 80, 0);       // 6 periods, 80% confidence, 0 = ARIMA
TimeSeriesManagement.GetForecast(TempTimeSeriesForecast);
```

## How MPS and MRP use it

```mermaid
flowchart TB
    subgraph MPS["MPS: independent demand (end items)"]
        direction TB
        SO["Sales in the period<br/>open orders + shipped"] --> NETMPS["Remaining forecast<br/>= forecast - sales<br/>(never below 0)"]
        SF["Sales item forecast<br/>from Sale history"] --> NETMPS
        SO --> DEM1["Demand profile"]
        NETMPS --> DEM1
        DEM1 --> PPO["Planned production orders<br/>for finished goods"]
    end
    subgraph MRP["MRP: dependent demand (components)"]
        direction TB
        DEP["Component need from<br/>planned production orders"] --> NETMRP["Remaining component forecast<br/>= forecast - component need"]
        CF["Component forecast<br/>from Consumption history"] --> NETMRP
        DEP --> DEM2["Demand profile"]
        NETMRP --> DEM2
        DEM2 --> PPU["Planned purchase orders and<br/>lower-level production orders"]
    end
    PPO -->|BOM explosion| DEP
    classDef f fill:#fff1e8,stroke:#ff6b35,color:#0b1f3a;
    classDef n fill:#e8f0fb,stroke:#0b1f3a,color:#0b1f3a;
    class SF,CF f;
    class SO,NETMPS,DEM1,PPO,DEP,NETMRP,DEM2,PPU n;
```

Planning reduces the forecast by the sales in the same forecast period (open orders and shipped), and only the remainder enters the demand profile. A forecast period runs from the forecast date to the next forecast date.

## Objects

| Type | ID | Name |
|---|---|---|
| Codeunit | 50500 | Demand Forecast Builder |
| Codeunit | 50501 | Location Series Example (SetPreparedData, item x location) |
| Report | 50500 | Create Time Series Forecast (search: *Create Time Series Demand Forecast*) |
| Enum | 50500 | Time Series Model (ordinals = codeunit 2000 model option) |
| Enum | 50501 | Forecast Demand Source |
| Enum | 50502 | Forecast Period |
| Permission set | 50500 | Time Series Forecast |

## Install

**Sandbox first.**

1. Clone, download symbols for BC 29 and publish from VS Code, or upload a release `.app` in Extension Management.
2. Assign the permission set **Time Series Demand Forecast**.
3. Search **Create Time Series Demand Forecast**, filter a few items, keep the defaults (TS-FCST, Sales, Month, 24 / 6 periods, ARIMA, 80%).
4. Check **Demand Forecasts** > TS-FCST.
5. **Planning Worksheet** > **Calculate Regenerative Plan**, tick MPS and MRP, Use Forecast = TS-FCST.

It writes only Demand Forecast Entries (and Inventory Setup if you choose). Delete the forecast name and it is all gone.

## Notes

- BC online uses the Microsoft-hosted service and counts against the tenant's Azure AI usage. On-premises: pass your own Azure ML URI and key to `Initialize` (keep the key in isolated storage).
- The model parameter is an Option: 0 ARIMA, 1 ETS, 2 STL, 3 ETS+ARIMA, 4 ETS+STL, 5 ALL, 6 TBATS. STL needs more than two years of data.
- Items are sent 50 per call to avoid service time-outs (`SetBatchSize`).
- Forecast at item level (blank location and variant). See codeunit 50501 for location level.
- Do not forecast make-to-order (Order policy) end items, and do not combine a forecast with a reorder point on the same item: you count demand twice.

## Build

Compiled with the AL compiler 18.1 against Base Application 29.0, with CodeCop, UICop and PerTenantExtensionCop: no warnings.

## Contributing

PRs welcome for location and variant level, a Query-based history reader, and a forecast accuracy check.

## License

MIT. See [LICENSE](LICENSE).
