-- ============================================================
-- 1. TABLES
-- ============================================================

-- 1a. Raw landing table: all incoming trade events
CREATE OR REPLACE TABLE TRADE_EVENTS_RAW (
    event_id         VARCHAR(36)      NOT NULL  COMMENT 'Unique UUID per ingest event',
    trade_ref        VARCHAR(50)      NOT NULL  COMMENT 'Business key linking versions of same trade',
    version          INTEGER          NOT NULL  COMMENT 'Version number; higher = newer amendment',
    instrument_type  VARCHAR(20)      NOT NULL  COMMENT 'BOND | FX | EQUITY | SWAP | CREDIT',
    notional         NUMBER(20, 4)    NOT NULL  COMMENT 'Trade notional amount',
    currency         CHAR(3)          NOT NULL  COMMENT 'ISO 4217 currency code',
    trade_date       DATE             NOT NULL  COMMENT 'Date the trade was executed',
    maturity_date    DATE             NOT NULL  COMMENT 'Date the trade matures',
    counterparty     VARCHAR(100)     NOT NULL,
    trader_id        VARCHAR(50)      NOT NULL,
    source_system    VARCHAR(50)               COMMENT 'Originating system identifier',
    raw_payload      VARIANT                   COMMENT 'Full original JSON payload',
    ingested_at      TIMESTAMP_NTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    is_processed     BOOLEAN          NOT NULL DEFAULT FALSE
)
COMMENT = 'All incoming trade events land here before validation';


-- 1b. Valid trade book (one row per trade_ref at latest accepted version)
CREATE OR REPLACE TABLE TRADES_VALID (
    trade_ref        VARCHAR(50)      NOT NULL,
    version          INTEGER          NOT NULL,
    instrument_type  VARCHAR(20)      NOT NULL,
    notional         NUMBER(20, 4)    NOT NULL,
    currency         CHAR(3)          NOT NULL,
    trade_date       DATE             NOT NULL,
    maturity_date    DATE             NOT NULL,
    counterparty     VARCHAR(100)     NOT NULL,
    trader_id        VARCHAR(50)      NOT NULL,
    source_system    VARCHAR(50),
    trade_status     VARCHAR(20)      NOT NULL DEFAULT 'ACTIVE'  COMMENT 'ACTIVE | EXPIRED | CANCELLED',
    created_at       TIMESTAMP_NTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    updated_at       TIMESTAMP_NTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_trades_valid PRIMARY KEY (trade_ref)
)
COMMENT = 'Current state of each trade – single source of truth';


-- 1c. Rejected trades (compliance/audit log)
CREATE OR REPLACE TABLE TRADES_REJECTED (
    rejection_id     VARCHAR(36)      NOT NULL DEFAULT UUID_STRING(),
    event_id         VARCHAR(36),
    trade_ref        VARCHAR(50)      NOT NULL,
    version          INTEGER          NOT NULL,
    instrument_type  VARCHAR(20),
    notional         NUMBER(20, 4),
    currency         CHAR(3),
    trade_date       DATE,
    maturity_date    DATE,
    counterparty     VARCHAR(100),
    trader_id        VARCHAR(50),
    rejection_code   VARCHAR(40)      NOT NULL  COMMENT 'VERSION_TOO_LOW | MATURITY_IN_PAST | DUPLICATE | BOND_NOTIONAL_TOO_LOW',
    rejection_reason VARCHAR(500)     NOT NULL,
    raw_payload      VARIANT,
    rejected_at      TIMESTAMP_NTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_rejections PRIMARY KEY (rejection_id)
)
COMMENT = 'All rejected trades – retained for compliance and audit';


-- 1d. Pipeline execution log
CREATE OR REPLACE TABLE PIPELINE_RUN_LOG (
    run_id           VARCHAR(36)      NOT NULL DEFAULT UUID_STRING(),
    run_start        TIMESTAMP_NTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    run_end          TIMESTAMP_NTZ,
    events_processed INTEGER          DEFAULT 0,
    trades_accepted  INTEGER          DEFAULT 0,
    trades_rejected  INTEGER          DEFAULT 0,
    trades_expired   INTEGER          DEFAULT 0,
    run_status       VARCHAR(20)      DEFAULT 'RUNNING'  COMMENT 'RUNNING | SUCCESS | FAILED',
    error_message    VARCHAR(2000),
    triggered_by     VARCHAR(100),
    CONSTRAINT pk_run_log PRIMARY KEY (run_id)
);


-- ============================================================
-- 2. INTERNAL STAGE & FILE FORMAT
-- ============================================================
CREATE STAGE IF NOT EXISTS TRADE_INGEST_STAGE
    FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE)
    COMMENT = 'Upload trade JSON files here for COPY INTO';

CREATE OR REPLACE FILE FORMAT TRADE_JSON_FF
    TYPE = 'JSON'
    STRIP_OUTER_ARRAY = TRUE
    DATE_FORMAT = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT = 'YYYY-MM-DDTHH24:MI:SS';


-- ============================================================
-- 3. STREAM (CDC on raw table – drives the validation task)
-- ============================================================
CREATE OR REPLACE STREAM TRADE_EVENTS_STREAM
    ON TABLE TRADE_EVENTS_RAW
    APPEND_ONLY = TRUE
    COMMENT = 'Captures new inserts into TRADE_EVENTS_RAW';


-- ============================================================
-- 4. STORED PROCEDURE: PROCESS_TRADE_EVENTS
--    Business rules:
--      R1  Reject if incoming version < existing version
--      R2  Replace (UPSERT) if incoming version == existing version
--      R3  Reject if maturity_date < today
--      R4  Mark EXPIRED if maturity_date has passed (on accept + daily sweep)
--      R5  (custom) Reject BOND trades with notional < 1,000
-- ============================================================
CREATE OR REPLACE PROCEDURE PROCESS_TRADE_EVENTS(P_TRIGGERED_BY VARCHAR DEFAULT 'TASK')
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_run_id    VARCHAR;
    v_accepted  INTEGER DEFAULT 0;
    v_rejected  INTEGER DEFAULT 0;
    v_expired   INTEGER DEFAULT 0;
    v_processed INTEGER DEFAULT 0;
    v_error     VARCHAR DEFAULT NULL;
BEGIN
    v_run_id := UUID_STRING();

    INSERT INTO PIPELINE_RUN_LOG (run_id, run_status, triggered_by)
    VALUES (:v_run_id, 'RUNNING', :P_TRIGGERED_BY);

    -- Snapshot unprocessed events from stream
    CREATE OR REPLACE TEMPORARY TABLE TMP_PENDING AS
    SELECT
        event_id, trade_ref, version, instrument_type, notional,
        currency, trade_date, maturity_date, counterparty, trader_id,
        source_system, raw_payload, ingested_at
    FROM TRADE_EVENTS_STREAM
    WHERE METADATA$ACTION = 'INSERT';

    v_processed := (SELECT COUNT(*) FROM TMP_PENDING);

    -- Intra-batch deduplication: keep only the highest-version event per trade_ref
    CREATE OR REPLACE TEMPORARY TABLE TMP_RANKED AS
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY trade_ref ORDER BY version DESC, ingested_at DESC) AS rn,
        MAX(version) OVER (PARTITION BY trade_ref) AS batch_max_version
    FROM TMP_PENDING;

    -- Classify winning events (rn=1) against business rules and existing TRADES_VALID
    CREATE OR REPLACE TEMPORARY TABLE TMP_CLASSIFIED AS
    SELECT
        e.event_id,
        e.trade_ref,
        e.version                              AS incoming_version,
        COALESCE(t.version, -1)                AS current_version,
        e.instrument_type,
        e.notional,
        e.currency,
        e.trade_date,
        e.maturity_date,
        e.counterparty,
        e.trader_id,
        e.source_system,
        e.raw_payload,
        e.ingested_at,
        CASE
            WHEN e.maturity_date < CURRENT_DATE()
                THEN 'REJECT_MATURITY_IN_PAST'
            WHEN e.instrument_type = 'BOND' AND e.notional < 1000
                THEN 'REJECT_BOND_NOTIONAL_TOO_LOW'
            WHEN t.trade_ref IS NOT NULL AND e.version < t.version
                THEN 'REJECT_VERSION_TOO_LOW'
            WHEN t.trade_ref IS NOT NULL AND e.version = t.version
                THEN 'ACCEPT_REPLACE'
            ELSE 'ACCEPT'
        END AS processing_action,
        CASE
            WHEN e.maturity_date <= CURRENT_DATE() THEN 'EXPIRED'
            ELSE 'ACTIVE'
        END AS computed_status
    FROM TMP_RANKED e
    LEFT JOIN TRADES_VALID t ON e.trade_ref = t.trade_ref
    WHERE e.rn = 1;

    -- MERGE accepted trades into TRADES_VALID
    MERGE INTO TRADES_VALID t
    USING (
        SELECT * FROM TMP_CLASSIFIED
        WHERE processing_action IN ('ACCEPT', 'ACCEPT_REPLACE')
    ) s
    ON t.trade_ref = s.trade_ref
    WHEN MATCHED THEN UPDATE SET
        t.version         = s.incoming_version,
        t.instrument_type = s.instrument_type,
        t.notional        = s.notional,
        t.currency        = s.currency,
        t.trade_date      = s.trade_date,
        t.maturity_date   = s.maturity_date,
        t.counterparty    = s.counterparty,
        t.trader_id       = s.trader_id,
        t.source_system   = s.source_system,
        t.trade_status    = s.computed_status,
        t.updated_at      = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (
        trade_ref, version, instrument_type, notional, currency,
        trade_date, maturity_date, counterparty, trader_id,
        source_system, trade_status, created_at, updated_at
    ) VALUES (
        s.trade_ref, s.incoming_version, s.instrument_type, s.notional,
        s.currency, s.trade_date, s.maturity_date, s.counterparty,
        s.trader_id, s.source_system, s.computed_status,
        CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
    );

    v_accepted := SQLROWCOUNT;

    -- Log rejections: classification rejects + intra-batch version losers
    INSERT INTO TRADES_REJECTED (
        rejection_id, event_id, trade_ref, version,
        instrument_type, notional, currency, trade_date, maturity_date,
        counterparty, trader_id, rejection_code, rejection_reason, raw_payload, rejected_at
    )
    -- Classification-based rejections
    SELECT
        UUID_STRING(), event_id, trade_ref, incoming_version,
        instrument_type, notional, currency, trade_date, maturity_date,
        counterparty, trader_id, processing_action,
        CASE processing_action
            WHEN 'REJECT_VERSION_TOO_LOW'
                THEN 'Version ' || incoming_version || ' < current ' || current_version || ' for ' || trade_ref
            WHEN 'REJECT_MATURITY_IN_PAST'
                THEN 'Maturity ' || maturity_date || ' is before today (' || CURRENT_DATE() || ')'
            WHEN 'REJECT_BOND_NOTIONAL_TOO_LOW'
                THEN 'BOND notional ' || notional || ' < minimum 1000'
            ELSE 'Rejected: ' || processing_action
        END,
        raw_payload,
        CURRENT_TIMESTAMP()
    FROM TMP_CLASSIFIED
    WHERE processing_action LIKE 'REJECT%'
    UNION ALL
    -- Intra-batch losers with lower version than the batch winner
    SELECT
        UUID_STRING(), event_id, trade_ref, version,
        instrument_type, notional, currency, trade_date, maturity_date,
        counterparty, trader_id, 'REJECT_VERSION_TOO_LOW',
        'Version ' || version || ' < batch max ' || batch_max_version || ' for ' || trade_ref,
        raw_payload,
        CURRENT_TIMESTAMP()
    FROM TMP_RANKED
    WHERE rn > 1 AND version < batch_max_version;

    v_rejected := SQLROWCOUNT;

    -- R4: Daily sweep – expire mature trades still marked ACTIVE
    UPDATE TRADES_VALID
    SET    trade_status = 'EXPIRED', updated_at = CURRENT_TIMESTAMP()
    WHERE  maturity_date < CURRENT_DATE() AND trade_status = 'ACTIVE';

    v_expired := SQLROWCOUNT;

    -- Mark raw events as processed
    UPDATE TRADE_EVENTS_RAW
    SET    is_processed = TRUE
    WHERE  event_id IN (SELECT event_id FROM TMP_PENDING);

    -- Close run log
    UPDATE PIPELINE_RUN_LOG
    SET    run_end = CURRENT_TIMESTAMP(),
           events_processed = :v_processed,
           trades_accepted  = :v_accepted,
           trades_rejected  = :v_rejected,
           trades_expired   = :v_expired,
           run_status       = 'SUCCESS'
    WHERE  run_id = :v_run_id;

    RETURN OBJECT_CONSTRUCT(
        'run_id', :v_run_id, 'status', 'SUCCESS',
        'events_processed', :v_processed, 'accepted', :v_accepted,
        'rejected', :v_rejected, 'expired', :v_expired
    );

EXCEPTION
    WHEN OTHER THEN
        v_error := SQLERRM;
        UPDATE PIPELINE_RUN_LOG
        SET run_end = CURRENT_TIMESTAMP(), run_status = 'FAILED', error_message = :v_error
        WHERE run_id = :v_run_id;
        RAISE;
END;
$$;


-- ============================================================
-- 5. HELPER PROCEDURES
-- ============================================================

-- Load from stage into raw table
CREATE OR REPLACE PROCEDURE LOAD_TRADES_FROM_STAGE()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    COPY INTO TRADE_EVENTS_RAW (
        event_id, trade_ref, version, instrument_type, notional,
        currency, trade_date, maturity_date, counterparty, trader_id,
        source_system, raw_payload, ingested_at
    )
    FROM (
        SELECT
            UUID_STRING(),
            $1:trade_ref::VARCHAR,
            $1:version::INTEGER,
            $1:instrument_type::VARCHAR,
            $1:notional::NUMBER(20,4),
            $1:currency::VARCHAR,
            $1:trade_date::DATE,
            $1:maturity_date::DATE,
            $1:counterparty::VARCHAR,
            $1:trader_id::VARCHAR,
            $1:source_system::VARCHAR,
            $1,
            CURRENT_TIMESTAMP()
        FROM @TRADE_INGEST_STAGE
    )
    FILE_FORMAT = (FORMAT_NAME = 'TRADE_JSON_FF')
    ON_ERROR = 'CONTINUE';

    RETURN 'Loaded ' || SQLROWCOUNT || ' events from stage';
END;
$$;

-- Standalone daily expiry sweep
CREATE OR REPLACE PROCEDURE EXPIRE_STALE_TRADES()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE v_count INTEGER;
BEGIN
    UPDATE TRADES_VALID
    SET trade_status = 'EXPIRED', updated_at = CURRENT_TIMESTAMP()
    WHERE maturity_date < CURRENT_DATE() AND trade_status = 'ACTIVE';
    v_count := SQLROWCOUNT;
    RETURN 'Marked ' || :v_count || ' trades as EXPIRED';
END;
$$;


-- ============================================================
-- 6. TASK DAG (Orchestration)
-- ============================================================

-- Root: load files from stage every 5 minutes
CREATE OR REPLACE TASK TASK_LOAD_FROM_STAGE
    WAREHOUSE = DATA_TESTING_WH_XSMALL
    SCHEDULE  = '5 MINUTES'
AS
    CALL LOAD_TRADES_FROM_STAGE();

-- Child: process events (only when stream has data)
CREATE OR REPLACE TASK TASK_PROCESS_TRADES
    WAREHOUSE = DATA_TESTING_WH_XSMALL
    AFTER     TASK_LOAD_FROM_STAGE
    WHEN      SYSTEM$STREAM_HAS_DATA('TRADE_EVENTS_STREAM')
AS
    CALL PROCESS_TRADE_EVENTS('TASK');

-- Daily: expire stale trades at midnight UTC
CREATE OR REPLACE TASK TASK_EXPIRE_TRADES
    WAREHOUSE = DATA_TESTING_WH_XSMALL
    SCHEDULE  = 'USING CRON 0 0 * * * UTC'
AS
    CALL EXPIRE_STALE_TRADES();

-- Activate (children first, root last)
ALTER TASK TASK_EXPIRE_TRADES    RESUME;
ALTER TASK TASK_PROCESS_TRADES   RESUME;
ALTER TASK TASK_LOAD_FROM_STAGE  RESUME;


-- ============================================================
-- 7. ALERTS (requires notification integration – see comment)
-- ============================================================
-- NOTE: Run as ACCOUNTADMIN first:
--   CREATE OR REPLACE NOTIFICATION INTEGRATION TRADE_PIPELINE_EMAIL_NI
--       TYPE = EMAIL ENABLED = TRUE;
--   GRANT USAGE ON INTEGRATION TRADE_PIPELINE_EMAIL_NI
--       TO ROLE US_SNOW_LLE_DEVELOPERS_RW_LG;

-- Alert: pipeline failure in last 10 min
CREATE OR REPLACE ALERT ALERT_PIPELINE_FAILURE
    WAREHOUSE = DATA_TESTING_WH_XSMALL
    SCHEDULE  = '10 MINUTES'
    IF (EXISTS (                              ---fix this one 
        SELECT 1 FROM PIPELINE_RUN_LOG
        WHERE run_status = 'FAILED' AND run_start >= DATEADD('minute', -10, CURRENT_TIMESTAMP())
    ))
    THEN
        CALL SYSTEM$SEND_EMAIL(
            'TRADE_PIPELINE_EMAIL_NI',
            'abc@test.com',
            '[ALERT] Trade Pipeline Failure',
            (SELECT LISTAGG('RunID: ' || run_id || ' Error: ' || COALESCE(error_message,'N/A'), CHR(10))
             FROM PIPELINE_RUN_LOG
             WHERE run_status = 'FAILED' AND run_start >= DATEADD('minute', -10, CURRENT_TIMESTAMP()))
        );

-- Alert: >30% rejection rate in last hour
CREATE OR REPLACE ALERT ALERT_HIGH_REJECTION_RATE
    WAREHOUSE = DATA_TESTING_WH_XSMALL
    SCHEDULE  = '1 HOUR'
    IF (EXISTS (
        SELECT 1 FROM (
            SELECT SUM(trades_rejected) / NULLIF(SUM(events_processed), 0) AS rate
            FROM PIPELINE_RUN_LOG
            WHERE run_start >= DATEADD('hour', -1, CURRENT_TIMESTAMP()) AND run_status = 'SUCCESS'
        ) WHERE rate > 0.30
    ))
    THEN
        CALL SYSTEM$SEND_EMAIL(
            'TRADE_PIPELINE_EMAIL_NI',
            'abc@test.com',
            '[ALERT] High Trade Rejection Rate (>30%)',
            'More than 30% of trades were rejected in the last hour. Check TRADES_REJECTED for details.'
        );

-- Alert: no successful run in 30 min
CREATE OR REPLACE ALERT ALERT_PIPELINE_STALLED
    WAREHOUSE = DATA_TESTING_WH_XSMALL
    SCHEDULE  = '30 MINUTES'
    IF (EXISTS (
        SELECT 1
        WHERE NOT EXISTS (
            SELECT 1 FROM PIPELINE_RUN_LOG
            WHERE run_status = 'SUCCESS' AND run_start >= DATEADD('minute', -30, CURRENT_TIMESTAMP())
        )
    ))
    THEN
        CALL SYSTEM$SEND_EMAIL(
            'TRADE_PIPELINE_EMAIL_NI',
            'ops-team@yourcompany.com',
            '[ALERT] Pipeline Stalled – No Run in 30 Min',
            'No successful pipeline run in the last 30 minutes. Check task status.'
        );

ALTER ALERT ALERT_PIPELINE_FAILURE     RESUME;
ALTER ALERT ALERT_HIGH_REJECTION_RATE  RESUME;
ALTER ALERT ALERT_PIPELINE_STALLED     RESUME;


-- ============================================================
-- 8. MONITORING VIEWS
-- ============================================================

CREATE OR REPLACE VIEW V_TRADE_BOOK_SUMMARY AS
SELECT
    trade_status, instrument_type, currency,
    COUNT(*)          AS trade_count,
    SUM(notional)     AS total_notional,
    MIN(maturity_date) AS earliest_maturity,
    MAX(maturity_date) AS latest_maturity
FROM TRADES_VALID
GROUP BY trade_status, instrument_type, currency;

CREATE OR REPLACE VIEW V_REJECTION_SUMMARY AS
SELECT
    DATE_TRUNC('hour', rejected_at) AS rejection_hour,
    rejection_code,
    COUNT(*)                        AS rejection_count
FROM TRADES_REJECTED
GROUP BY 1, 2
ORDER BY 1 DESC;

CREATE OR REPLACE VIEW V_PIPELINE_HEALTH AS
SELECT
    run_id, run_start, run_end,
    DATEDIFF('second', run_start, COALESCE(run_end, CURRENT_TIMESTAMP())) AS duration_secs,
    events_processed, trades_accepted, trades_rejected, trades_expired,
    run_status, error_message
FROM PIPELINE_RUN_LOG
WHERE run_start >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY run_start DESC;
