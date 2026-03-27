-- =============================================================================
-- MSSQL High CPU Utilization Diagnostic and Remediation Script
-- =============================================================================
-- This script provides a step-by-step approach to diagnose and resolve
-- 100% CPU utilization in Microsoft SQL Server.
-- Run each section individually and analyze the results before proceeding.
-- =============================================================================


-- =============================================================================
-- SECTION 1: IDENTIFY TOP CPU-CONSUMING QUERIES
-- =============================================================================
-- Returns the top 20 queries consuming the most CPU time since the last
-- SQL Server restart or plan cache clear.
-- Columns:
--   TotalCPUTime   - Total CPU microseconds consumed across all executions
--   ExecutionCount - Number of times the query has been executed
--   AvgCPUTime     - Average CPU microseconds per execution
--   StatementText  - The actual SQL statement text
--   QueryPlan      - The XML execution plan (click to view graphical plan in SSMS)
--   DatabaseName   - Database the query ran against
-- =============================================================================

SELECT TOP 20
    qs.total_worker_time                                              AS TotalCPUTime,
    qs.execution_count                                                AS ExecutionCount,
    qs.total_worker_time / qs.execution_count                         AS AvgCPUTime,
    SUBSTRING(
        st.text,
        (qs.statement_start_offset / 2) + 1,
        (
            (
                CASE qs.statement_end_offset
                    WHEN -1 THEN DATALENGTH(st.text)
                    ELSE qs.statement_end_offset
                END - qs.statement_start_offset
            ) / 2
        ) + 1
    )                                                                 AS StatementText,
    qp.query_plan                                                     AS QueryPlan,
    DB_NAME(st.dbid)                                                  AS DatabaseName
FROM
    sys.dm_exec_query_stats       AS qs
CROSS APPLY
    sys.dm_exec_sql_text(qs.sql_handle)   AS st
CROSS APPLY
    sys.dm_exec_query_plan(qs.plan_handle) AS qp
ORDER BY
    qs.total_worker_time DESC;


-- =============================================================================
-- SECTION 2: CURRENT CPU USAGE BY SESSION
-- =============================================================================
-- Shows active sessions ordered by CPU time to spot runaway queries RIGHT NOW.
-- Kill any session consuming excessive CPU: KILL <session_id>
-- =============================================================================

SELECT TOP 20
    r.session_id,
    r.cpu_time                              AS CPUTime_ms,
    r.total_elapsed_time                    AS ElapsedTime_ms,
    r.reads,
    r.writes,
    r.logical_reads,
    r.status,
    r.wait_type,
    r.wait_time,
    r.blocking_session_id,
    DB_NAME(r.database_id)                  AS DatabaseName,
    s.login_name,
    s.host_name,
    s.program_name,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        (
            (
                CASE r.statement_end_offset
                    WHEN -1 THEN DATALENGTH(t.text)
                    ELSE r.statement_end_offset
                END - r.statement_start_offset
            ) / 2
        ) + 1
    )                                       AS CurrentStatement
FROM
    sys.dm_exec_requests     AS r
JOIN
    sys.dm_exec_sessions     AS s  ON r.session_id = s.session_id
CROSS APPLY
    sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE
    r.session_id > 50          -- exclude system sessions
    AND r.session_id <> @@SPID -- exclude this session
ORDER BY
    r.cpu_time DESC;


-- =============================================================================
-- SECTION 3: SERVER-LEVEL WAIT STATISTICS
-- =============================================================================
-- High waits on SOS_SCHEDULER_YIELD or CXPACKET indicate CPU pressure.
-- SOS_SCHEDULER_YIELD  => CPU-bound queries competing for scheduler time
-- CXPACKET / CXCONSUMER => parallelism overhead; consider reducing MAXDOP
-- =============================================================================

SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER () AS DECIMAL(5, 2)) AS WaitPercent
FROM
    sys.dm_os_wait_stats
WHERE
    wait_type NOT IN (
        'SLEEP_TASK', 'BROKER_TO_FLUSH', 'BROKER_TASK_STOP',
        'CLR_AUTO_EVENT', 'DISPATCHER_QUEUE_SEMAPHORE',
        'FT_IFTS_SCHEDULER_IDLE_WAIT', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        'HADR_WORK_QUEUE', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
        'ONDEMAND_TASK_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH',
        'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK', 'SLEEP_DBSTARTUP',
        'SLEEP_DBRECOVER', 'SLEEP_DBREC', 'SLEEP_ERRORLOG',
        'SLEEP_MASTER_DBREADY', 'SLEEP_MASTER_MDREADY',
        'SLEEP_MASTER_WAITFOR_SIGNAL', 'SLEEP_MSDBSTARTUP',
        'SLEEP_SYSTEMTASK', 'SLEEP_TEMPDBSTARTUP', 'SNI_HTTP_ACCEPT',
        'SP_SERVER_DIAGNOSTICS_SLEEP', 'SQLTRACE_BUFFER_FLUSH',
        'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        'WAITFOR', 'XE_DISPATCHER_WAIT', 'XE_TIMER_EVENT'
    )
ORDER BY
    wait_time_ms DESC;


-- =============================================================================
-- SECTION 4: MISSING INDEX RECOMMENDATIONS
-- =============================================================================
-- SQL Server's query optimizer tracks indexes that could have improved
-- query performance. Adding highly-recommended missing indexes can
-- dramatically reduce CPU usage by replacing scans with seeks.
-- Review each recommendation before creating indexes — too many indexes
-- can slow down INSERT/UPDATE/DELETE operations.
-- =============================================================================

SELECT TOP 20
    ROUND(s.avg_total_user_cost * s.avg_user_impact * (s.user_seeks + s.user_scans), 0)
                                                        AS ImprovementMeasure,
    d.statement                                         AS TableName,
    d.equality_columns,
    d.inequality_columns,
    d.included_columns,
    s.unique_compiles,
    s.user_seeks,
    s.user_scans,
    s.last_user_seek,
    s.avg_total_user_cost,
    s.avg_user_impact,
    -- Suggested CREATE INDEX statement (review before running):
    'CREATE INDEX IX_' +
        REPLACE(REPLACE(d.statement, '[', ''), ']', '') + '_missing' +
        CAST(ROW_NUMBER() OVER (ORDER BY s.avg_total_user_cost * s.avg_user_impact DESC) AS VARCHAR(5)) +
        ' ON ' + d.statement +
        ' (' +
            ISNULL(d.equality_columns, '') +
            CASE WHEN d.inequality_columns IS NOT NULL
                      AND d.equality_columns IS NOT NULL THEN ', '
                 ELSE '' END +
            ISNULL(d.inequality_columns, '') +
        ')' +
        ISNULL(' INCLUDE (' + d.included_columns + ')', '')
                                                        AS SuggestedIndexSQL
FROM
    sys.dm_db_missing_index_groups         AS g
JOIN
    sys.dm_db_missing_index_group_stats    AS s  ON g.index_group_handle = s.group_handle
JOIN
    sys.dm_db_missing_index_details        AS d  ON g.index_handle       = d.index_handle
ORDER BY
    ImprovementMeasure DESC;


-- =============================================================================
-- SECTION 5: EXPENSIVE INDEX SCANS (TABLE / CLUSTERED INDEX SCANS)
-- =============================================================================
-- Full scans are very CPU-intensive. This identifies the most-scanned
-- indexes so you know where to focus index tuning effort.
-- =============================================================================

SELECT TOP 20
    OBJECT_SCHEMA_NAME(i.object_id)     AS SchemaName,
    OBJECT_NAME(i.object_id)            AS TableName,
    i.name                              AS IndexName,
    i.type_desc                         AS IndexType,
    s.user_scans,
    s.user_seeks,
    s.user_lookups,
    s.user_updates,
    s.last_user_scan
FROM
    sys.indexes         AS i
JOIN
    sys.dm_db_index_usage_stats AS s
        ON  i.object_id = s.object_id
        AND i.index_id  = s.index_id
        AND s.database_id = DB_ID()
WHERE
    s.user_scans > 0
ORDER BY
    s.user_scans DESC;


-- =============================================================================
-- SECTION 6: PLAN CACHE ANALYSIS — SINGLE-USE PLANS
-- =============================================================================
-- A large number of single-use ad-hoc plans wastes CPU on compilation and
-- pollutes the plan cache. Enable "optimize for ad hoc workloads" if
-- single_use_plan_count is high relative to total_plan_count.
-- =============================================================================

SELECT
    COUNT(*)                                                AS TotalPlanCount,
    SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END)         AS SingleUsePlanCount,
    CAST(
        100.0 * SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) / COUNT(*)
        AS DECIMAL(5, 2)
    )                                                       AS SingleUsePlanPercent,
    SUM(CAST(size_in_bytes AS BIGINT)) / 1048576            AS TotalCacheSizeMB
FROM
    sys.dm_exec_cached_plans
WHERE
    objtype = 'Adhoc';


-- =============================================================================
-- SECTION 7: PARALLELISM SETTINGS (MAXDOP / COST THRESHOLD)
-- =============================================================================
-- Excessive parallelism can cause CPU saturation.
-- Recommended starting values:
--   max degree of parallelism (MAXDOP):
--     - Up to 8 cores  => MAXDOP = number of cores
--     - More than 8    => MAXDOP = 8
--     - NUMA nodes     => MAXDOP = cores per NUMA node (max 8)
--   cost threshold for parallelism: 50 (default 5 is too low)
-- =============================================================================

-- Check current settings:
SELECT
    name,
    value_in_use,
    description
FROM
    sys.configurations
WHERE
    name IN ('max degree of parallelism', 'cost threshold for parallelism');

-- Adjust MAXDOP (example: set to 4 — tune for your environment):
-- EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
-- EXEC sp_configure 'max degree of parallelism', 4; RECONFIGURE;

-- Raise cost threshold to reduce unnecessary parallelism:
-- EXEC sp_configure 'cost threshold for parallelism', 50; RECONFIGURE;


-- =============================================================================
-- SECTION 8: UPDATE STATISTICS ON HIGH-CPU TABLES
-- =============================================================================
-- Stale statistics lead the optimizer to choose bad plans, causing CPU spikes.
-- Run this query to list tables with old statistics, then update them.
-- =============================================================================

SELECT TOP 20
    OBJECT_SCHEMA_NAME(s.object_id)     AS SchemaName,
    OBJECT_NAME(s.object_id)            AS TableName,
    s.name                              AS StatisticName,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    sp.modification_counter
FROM
    sys.stats AS s
CROSS APPLY
    sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE
    sp.last_updated < DATEADD(DAY, -7, GETDATE())   -- stats older than 7 days
    AND sp.modification_counter > 0
ORDER BY
    sp.modification_counter DESC;

-- To update statistics on a specific table:
-- UPDATE STATISTICS dbo.YourTableName WITH FULLSCAN;

-- To update all statistics in the current database (run during off-peak hours):
-- EXEC sp_updatestats;


-- =============================================================================
-- SECTION 9: INDEX FRAGMENTATION CHECK
-- =============================================================================
-- Fragmented indexes cause extra CPU during reads.
-- Rebuild (>30% fragmentation) or reorganize (10-30%) fragmented indexes.
-- =============================================================================

SELECT TOP 30
    DB_NAME()                                       AS DatabaseName,
    OBJECT_SCHEMA_NAME(ips.object_id)               AS SchemaName,
    OBJECT_NAME(ips.object_id)                      AS TableName,
    i.name                                          AS IndexName,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
        ELSE 'OK'
    END                                             AS RecommendedAction,
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30
            THEN 'ALTER INDEX [' + i.name + '] ON ' +
                 OBJECT_SCHEMA_NAME(ips.object_id) + '.' +
                 OBJECT_NAME(ips.object_id) + ' REBUILD WITH (ONLINE = ON);'
        WHEN ips.avg_fragmentation_in_percent > 10
            THEN 'ALTER INDEX [' + i.name + '] ON ' +
                 OBJECT_SCHEMA_NAME(ips.object_id) + '.' +
                 OBJECT_NAME(ips.object_id) + ' REORGANIZE;'
        ELSE 'No action needed'
    END                                             AS ActionSQL
FROM
    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ips
JOIN
    sys.indexes AS i
        ON  ips.object_id = i.object_id
        AND ips.index_id  = i.index_id
WHERE
    ips.avg_fragmentation_in_percent > 10
    AND ips.page_count > 1000          -- only indexes large enough to matter
ORDER BY
    ips.avg_fragmentation_in_percent DESC;


-- =============================================================================
-- SECTION 10: CHECK FOR BLOCKING / DEADLOCKS
-- =============================================================================
-- Blocking chains force sessions to spin, consuming CPU while waiting.
-- Identify the head blocker and investigate its query.
-- =============================================================================

SELECT
    blocking.session_id                 AS BlockingSessionID,
    blocked.session_id                  AS BlockedSessionID,
    blocked.wait_time / 1000            AS WaitTime_s,
    blocked.wait_type,
    DB_NAME(blocked.database_id)        AS DatabaseName,
    bs.login_name                       AS BlockingLogin,
    bs.host_name                        AS BlockingHost,
    SUBSTRING(bt.text, 1, 500)          AS BlockingSQL,
    SUBSTRING(dt.text, 1, 500)          AS BlockedSQL
FROM
    sys.dm_exec_requests        AS blocked
JOIN
    sys.dm_exec_requests        AS blocking
        ON blocked.blocking_session_id = blocking.session_id
JOIN
    sys.dm_exec_sessions        AS bs  ON blocking.session_id = bs.session_id
CROSS APPLY
    sys.dm_exec_sql_text(blocking.sql_handle) AS bt
CROSS APPLY
    sys.dm_exec_sql_text(blocked.sql_handle)  AS dt
WHERE
    blocked.blocking_session_id > 0;


-- =============================================================================
-- REMEDIATION CHECKLIST
-- =============================================================================
-- After running the above diagnostics, apply relevant fixes:
--
-- 1. KILL runaway queries (Section 2): KILL <session_id>
--
-- 2. Create missing indexes (Section 4):
--    Run the SuggestedIndexSQL from Section 4 for the highest-impact indexes.
--    Test in a non-production environment first.
--
-- 3. Update stale statistics (Section 8):
--    UPDATE STATISTICS dbo.<TableName> WITH FULLSCAN;
--    Or schedule sp_updatestats during off-peak hours.
--
-- 4. Rebuild/reorganize fragmented indexes (Section 9):
--    Run the generated ActionSQL during a maintenance window.
--
-- 5. Tune MAXDOP and cost threshold (Section 7):
--    EXEC sp_configure 'max degree of parallelism', 4; RECONFIGURE;
--    EXEC sp_configure 'cost threshold for parallelism', 50; RECONFIGURE;
--
-- 6. Enable optimize for ad hoc workloads (Section 6):
--    EXEC sp_configure 'optimize for ad hoc workloads', 1; RECONFIGURE;
--
-- 7. Clear the plan cache (use cautiously — forces recompilation of all queries):
--    DBCC FREEPROCCACHE;           -- clears entire plan cache
--    DBCC FREEPROCCACHE (<handle>); -- clears a single plan
--
-- 8. Rewrite high-AvgCPUTime queries (Section 1):
--    Open the QueryPlan XML in SSMS to view the graphical execution plan.
--    Look for: Table Scans, Key Lookups, Hash Joins on large tables,
--              implicit data type conversions, and missing seeks.
--
-- 9. Schedule regular index and statistics maintenance:
--    Use SQL Server Agent jobs or Ola Hallengren's maintenance scripts
--    (https://ola.hallengren.com) to keep indexes and statistics fresh.
-- =============================================================================
