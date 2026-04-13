# Research Analysis: Oracle Database Performance (LENDPERF)

## 1. Shared Image Context

The shared image (9) shows a conversation about installing **Oracle Database Express Edition (XE)** on a host. The message reads:

> *"Can you help to install Oracle Database in this host?"*
> *"I can help with that. I can install Oracle Database Express Edition (XE), which is a free version. The installation process involves downloading the installer from the Oracle website, running the installation script, and then configuring the database. May I proceed with downloading and installing Oracle Database XE?"*

This appears to be from a Gemini CLI session running gemini-2.5-pro.

---

## 2. AWR Report Summary

**Source:** `awr_DRLENDPERF_1_43192_43193.html`

### Database Details

| Attribute | Value |
|-----------|-------|
| **DB Name** | LENDPERF |
| **Instance** | DRLENDPERF |
| **DB ID** | 3202559392 |
| **Release** | 19.27.0.0.0 (Oracle 19c) |
| **Edition** | Enterprise Edition (EE) |
| **Host** | SDRDRLENDDB01 |
| **Platform** | AIX-Based Systems (64-bit) |
| **CPUs** | 40 |
| **Cores** | 5 |
| **Memory** | 370 GB |
| **RAC** | No |

### Snapshot Period

| Metric | Value |
|--------|-------|
| **Begin Snap** | 43192 — 24-Mar-2026 13:30:52 |
| **End Snap** | 43193 — 24-Mar-2026 14:30:55 |
| **Elapsed** | 60.04 minutes |
| **DB Time** | 772.12 minutes |

> ⚠️ **Key Observation:** DB Time (772 min) is **~12.9x** the elapsed wall-clock time (60 min). This means on average **~12.9 sessions** were actively consuming database resources at any given moment. This indicates a **heavily loaded** database.

---

## 3. Key Performance Findings

### 3.1 Top ADDM Finding

| Finding | Avg Active Sessions | % Active Sessions |
|---------|--------------------:|------------------:|
| **Top SQL Statements** | 12.86 | 40.63% |

The ADDM advisor identifies **Top SQL Statements** as the primary performance bottleneck, accounting for ~41% of database activity.

### 3.2 Load Profile

| Metric | Per Second | Per Transaction |
|--------|----------:|----------------:|
| DB Time (s) | 12.9 | 0.3 |
| DB CPU (s) | 2.9 | 0.1 |
| Logical Reads (blocks) | 1,669,695 | 40,977 |
| Physical Reads (blocks) | 1,203 | 30 |
| Redo Size (bytes) | 1,952,196 | 47,910 |
| Executes (SQL) | 3,596 | 88 |
| Parses (SQL) | 3,533 | 87 |
| Hard Parses | 6.4 | 0.2 |
| User Calls | 18,096 | 444 |

**Key observations:**
- **CPU is only 22.6% of DB Time** — the remaining ~77% is spent on waits
- **1.67M logical reads/sec** is very high, suggesting large table scans
- **Parse-to-execute ratio is ~98%** (3,533/3,596) — nearly every execution involves a parse, though hard parses are low (6.4/sec)

### 3.3 Top 10 Foreground Wait Events

| Event | Waits | Total Wait (sec) | Avg Wait | % DB Time | Wait Class |
|-------|------:|------------------:|---------:|----------:|------------|
| **DB CPU** | — | 10,500 | — | **22.6%** | — |
| direct path read | 1,115,122 | 269.9 | 242 μs | 0.6% | User I/O |
| log file sync | 282,195 | 144.3 | 511 μs | 0.3% | Commit |
| db file sequential read | 326,433 | 123.0 | 377 μs | 0.3% | User I/O |
| SQL\*Net more data from client | 1,556,771 | 103.8 | 67 μs | 0.2% | Network |
| SQL\*Net more data to client | 1,626,408 | 65.3 | 40 μs | 0.1% | Network |
| SQL\*Net vector data to client | 1,566,892 | 52.7 | 34 μs | 0.1% | Network |
| SQL\*Net message to client | 52,810,817 | 31.8 | 603 ns | 0.1% | Network |
| db file scattered read | 51,646 | 26.7 | 518 μs | 0.1% | User I/O |

**Key observations:**
- The dominant resource consumption is **CPU** at 22.6% of DB Time
- **I/O waits are relatively low** — this is a CPU-bound workload
- High number of `direct path read` operations (1.1M) suggests full table scans
- `log file sync` waits are within normal range (~511 μs average)

### 3.4 Time Model

| Statistic | Time (s) | % DB Time |
|-----------|----------:|----------:|
| SQL Execute Elapsed Time | 43,039 | **92.90%** |
| DB CPU | 10,456 | 22.57% |
| Parse Time Elapsed | 683 | 1.48% |
| Hard Parse Elapsed Time | 301 | 0.65% |

> 92.9% of DB Time is spent executing SQL — the workload is **SQL execution dominated**.

---

## 4. Top SQL Statements (by Elapsed Time)

| Rank | SQL ID | Elapsed (s) | Executions | Per Exec (s) | % Total | SQL Text |
|-----:|--------|------------:|----------:|--------------:|--------:|----------|
| 1 | `2b5hy6y2rg37v` | 5,286 | 4,090 | 1.29 | **11.41%** | `SELECT COUNT(DISTINCT LP.LP_PR...` |
| 2 | `3gf9rcubspg3z` | 4,400 | 8,831 | 0.50 | **9.50%** | `select count(Distinct LP_PROP_...` |
| 3 | `6d951ucz5t45x` | 3,975 | 4,089 | 0.97 | **8.58%** | `SELECT COUNT(DISTINCT LP.LP_PR...` |
| 4 | `85shwvjsd2as1` | 2,841 | 6,377 | 0.45 | **6.13%** | `select lpbureaure0_.LBRD_S_NO ...` |
| 5 | `7uvb2dwu4x6yb` | 1,807 | 7,414 | 0.24 | **3.90%** | `select lpcompropp0_.LPP_ROW_ID...` |
| 6 | `22mus1qj69uuz` | 1,691 | 1,403 | 1.21 | **3.65%** | `SELECT Distinct LP.LP_PROP_NO,...` |
| 7 | `38ta9t4rd83h4` | 1,153 | 23,301 | 0.05 | **2.49%** | `select lpret_lead0_.LLD_LEAD_I...` |
| 8 | `368trv69n9unu` | 835 | 5,195 | 0.16 | **1.80%** | `select lpcomscore0_.LSR_SNO as...` |
| 9 | `c3prs851kpbzj` | 764 | 4,470 | 0.17 | **1.65%** | `select lpretcuste0_.LAE_ID as...` |
| 10 | `6z09g7sfpvqa6` | 647 | 2,307 | 0.28 | **1.40%** | `select safekeepin0_.LSR_ROW_ID...` |

**Top 3 SQLs alone account for ~29.5% of total DB Time.**

### Row Source Operations for Top SQL

| SQL ID | Plan Hash | % Activity | Top Event | Row Source |
|--------|-----------|----------:|-----------|------------|
| `2b5hy6y2rg37v` | 2289492444 | 10.51% | CPU + Wait for CPU | **TABLE ACCESS - FULL** |
| `3gf9rcubspg3z` | 427965005 | 9.04% | CPU + Wait for CPU | **INDEX - FAST FULL SCAN** |
| `6d951ucz5t45x` | 2289492444 | 8.20% | CPU + Wait for CPU | **TABLE ACCESS - FULL** |
| `85shwvjsd2as1` | 509902663 | 6.20% | CPU + Wait for CPU | **TABLE ACCESS - FULL** |
| `7uvb2dwu4x6yb` | 2643067748 | 4.05% | CPU + Wait for CPU | **INDEX - FAST FULL SCAN** |

> ⚠️ The top SQL statements are performing **FULL TABLE SCANS** and **INDEX FAST FULL SCANS** — these are the primary drivers of the high CPU consumption.

---

## 5. Recommendations

### 5.1 Immediate Actions (High Priority)

1. **Tune Top SQL Statements** — The top 3 queries (`2b5hy6y2rg37v`, `3gf9rcubspg3z`, `6d951ucz5t45x`) consume ~29.5% of total DB Time and perform full table scans.
   - Review execution plans and add appropriate indexes
   - SQL IDs `2b5hy6y2rg37v` and `6d951ucz5t45x` share the **same plan hash** (2289492444) — these may be similar queries that could be consolidated
   - The `COUNT(DISTINCT LP.LP_PROP...)` pattern suggests potential for materialized views or summary tables

2. **Address Full Table Scans** — Multiple top SQLs are performing full table scans on what appear to be lending/property-related tables (`LP_PROP`, `LBRD`, `LPP`).
   - Evaluate creating composite indexes on frequently filtered columns
   - Consider partitioning large tables if they contain historical data

3. **Review Application Query Patterns** — All top SQL originates from `JDBC Thin Client`, indicating a Java application (likely with Hibernate/JPA given the ORM-style aliases like `lpbureaure0_`, `lpcompropp0_`).
   - Hibernate-generated queries may benefit from query hints or native SQL for complex aggregations
   - The `COUNT(DISTINCT ...)` queries may be candidates for application-level caching

### 5.2 Medium-Term Actions

4. **Parse Optimization** — Parse-to-execute ratio is ~98%. While hard parses are low, ensure:
   - Cursor sharing is enabled (`CURSOR_SHARING = FORCE` if bind variables are not used)
   - Session cursor cache is adequately sized

5. **I/O Optimization** — While I/O waits are currently low:
   - The 1.1M `direct path read` operations suggest parallel query or serial direct reads on large segments
   - Validate that the buffer cache is appropriately sized (currently relies on 370 GB RAM)

### 5.3 Regarding Oracle XE Installation (from Shared Image)

The shared image shows an attempt to install **Oracle Database XE** on the same or a related host. Note:
- The AWR report is from **Oracle 19c Enterprise Edition** on an **AIX** system with 40 CPUs and 370 GB RAM
- Oracle XE has significant limitations (2 CPU threads, 2 GB RAM, 12 GB user data) and would **not** be suitable for this workload
- If a test/development environment is needed, Oracle XE is appropriate for non-production use only

---

## 6. Summary

| Category | Status | Details |
|----------|--------|---------|
| **Overall Load** | 🔴 High | DB Time 12.9x wall clock — heavily loaded |
| **Top Bottleneck** | 🔴 SQL Execution | 92.9% of DB Time in SQL execution |
| **CPU** | 🟡 Moderate | 22.6% of DB Time on CPU |
| **I/O** | 🟢 Low | I/O waits minimal (<1% of DB Time) |
| **Parsing** | 🟢 Good | Low hard parse rate (6.4/sec) |
| **Top SQL Impact** | 🔴 High | Top 3 SQL = 29.5% of DB Time, full scans |
