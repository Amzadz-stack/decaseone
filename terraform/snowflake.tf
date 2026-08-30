# ==========================================
# Trade Pipeline - All Snowflake Resources
# Mirrors Case Studies.sql sections 1-8 (22 objects)
# ==========================================

# ------------------------------------------
# 1. TABLES
# ------------------------------------------

# 1a. Raw landing table
resource "snowflake_table" "trade_events_raw" {
  database = local.fqn_database
  schema   = local.fqn_schema
  name     = "TRADE_EVENTS_RAW"
  comment  = "All incoming trade events land here before validation"

  column { name = "EVENT_ID"; type = "VARCHAR(36)"; nullable = false }
  column { name = "TRADE_REF"; type = "VARCHAR(50)"; nullable = false }
  column { name = "VERSION"; type = "NUMBER(38,0)"; nullable = false }
  column { name = "INSTRUMENT_TYPE"; type = "VARCHAR(20)"; nullable = false }
  column { name = "NOTIONAL"; type = "NUMBER(20,4)"; nullable = false }
  column { name = "CURRENCY"; type = "VARCHAR(3)"; nullable = false }
  column { name = "TRADE_DATE"; type = "DATE"; nullable = false }
  column { name = "MATURITY_DATE"; type = "DATE"; nullable = false }
  column { name = "COUNTERPARTY"; type = "VARCHAR(100)"; nullable = false }
  column { name = "TRADER_ID"; type = "VARCHAR(50)"; nullable = false }
  column { name = "SOURCE_SYSTEM"; type = "VARCHAR(50)"; nullable = true }
  column { name = "RAW_PAYLOAD"; type = "VARIANT"; nullable = true }
  column { name = "INGESTED_AT"; type = "TIMESTAMP_NTZ(9)"; nullable = false; default { constant = "CURRENT_TIMESTAMP()" } }
  column { name = "IS_PROCESSED"; type = "BOOLEAN"; nullable = false; default { constant = "FALSE" } }
}

# 1b. Valid trade book
resource "snowflake_table" "trades_valid" {
  database = local.fqn_database
  schema   = local.fqn_schema
  name     = "TRADES_VALID"
  comment  = "Current state of each trade - single source of truth"

  column { name = "TRADE_REF"; type = "VARCHAR(50)"; nullable = false }
  column { name = "VERSION"; type = "NUMBER(38,0)"; nullable = false }
  column { name = "INSTRUMENT_TYPE"; type = "VARCHAR(20)"; nullable = false }
  column { name = "NOTIONAL"; type = "NUMBER(20,4)"; nullable = false }
  column { name = "CURRENCY"; type = "VARCHAR(3)"; nullable = false }
  column { name = "TRADE_DATE"; type = "DATE"; nullable = false }
  column { name = "MATURITY_DATE"; type = "DATE"; nullable = false }
  column { name = "COUNTERPARTY"; type = "VARCHAR(100)"; nullable = false }
  column { name = "TRADER_ID"; type = "VARCHAR(50)"; nullable = false }
  column { name = "SOURCE_SYSTEM"; type = "VARCHAR(50)"; nullable = true }
  column { name = "TRADE_STATUS"; type = "VARCHAR(20)"; nullable = false; default { constant = "'ACTIVE'" } }
  column { name = "CREATED_AT"; type = "TIMESTAMP_NTZ(9)"; nullable = false; default { constant = "CURRENT_TIMESTAMP()" } }
  column { name = "UPDATED_AT"; type = "TIMESTAMP_NTZ(9)"; nullable = false; default { constant = "CURRENT_TIMESTAMP()" } }

  primary_key {
    keys = ["TRADE_REF"]
  }
}

# 1c. Rejected trades (compliance audit log)
resource "snowflake_table" "trades_rejected" {
  database = local.fqn_database
  schema   = local.fqn_schema
  name     = "TRADES_REJECTED"
  comment  = "All rejected trades - retained for compliance and audit"

  column { name = "REJECTION_ID"; type = "VARCHAR(36)"; nullable = false; default { constant = "UUID_STRING()" } }
  column { name = "EVENT_ID"; type = "VARCHAR(36)"; nullable = true }
  column { name = "TRADE_REF"; type = "VARCHAR(50)"; nullable = false }
  column { name = "VERSION"; type = "NUMBER(38,0)"; nullable = false }
  column { name = "INSTRUMENT_TYPE"; type = "VARCHAR(20)"; nullable = false }
  column { name = "NOTIONAL"; type = "NUMBER(20,4)"; nullable = true }
  column { name = "CURRENCY"; type = "VARCHAR(3)"; nullable = true }
  column { name = "TRADE_DATE"; type = "DATE"; nullable = true }
  column { name = "MATURITY_DATE"; type = "DATE"; nullable = true }
  column { name = "COUNTERPARTY"; type = "VARCHAR(100)"; nullable = true }
  column { name = "TRADER_ID"; type = "VARCHAR(50)"; nullable = true }
  column { name = "REJECTION_CODE"; type = "VARCHAR(40)"; nullable = false }
  column { name = "REJECTION_REASON"; type = "VARCHAR(500)"; nullable = false }
  column { name = "RAW_PAYLOAD"; type = "VARIANT"; nullable = true }
  column { name = "REJECTED_AT"; type = "TIMESTAMP_NTZ(9)"; nullable = false; default { constant = "CURRENT_TIMESTAMP()" } }

  primary_key {
    keys = ["REJECTION_ID"]
  }
}

# 1d. Pipeline execution log
resource "snowflake_table" "pipeline_run_log" {
  database = local.fqn_database
  schema   = local.fqn_schema
  name     = "PIPELINE_RUN_LOG"
  comment  = "Execution metrics per pipeline run"

  column { name = "RUN_ID"; type = "VARCHAR(36)"; nullable = false; default { constant = "UUID_STRING()" } }
  column { name = "RUN_START"; type = "TIMESTAMP_NTZ(9)"; nullable = false; default { constant = "CURRENT_TIMESTAMP()" } }
  column { name = "RUN_END"; type = "TIMESTAMP_NTZ(9)"; nullable = true }
  column { name = "EVENTS_PROCESSED"; type = "NUMBER(38,0)"; nullable = false; default { constant = "0" } }
  column { name = "TRADES_ACCEPTED"; type = "NUMBER(38,0)"; nullable = false; default { constant = "0" } }
  column { name = "TRADES_REJECTED"; type = "NUMBER(38,0)"; nullable = false; default { constant = "0" } }
  column { name = "TRADES_EXPIRED"; type = "NUMBER(38,0)"; nullable = false; default { constant = "0" } }
  column { name = "RUN_STATUS"; type = "VARCHAR(20)"; nullable = false; default { constant = "'RUNNING'" } }
  column { name = "ERROR_MESSAGE"; type = "VARCHAR(2000)"; nullable = true }
  column { name = "TRIGGERED_BY"; type = "VARCHAR(100)"; nullable = true }

  primary_key {
    keys = ["RUN_ID"]
  }
}

# ------------------------------------------
# 2. INTERNAL STAGE & FILE FORMAT
# ------------------------------------------

resource "snowflake_stage" "trade_ingest_stage" {
  database = local.fqn_database
  schema   = local.fqn_schema
  name     = "TRADE_INGEST_STAGE"
  comment  = "Upload trade JSON files here for COPY INTO"
}

resource "snowflake_file_format" "trade_json_ff" {
  database            = local.fqn_database
  schema              = local.fqn_schema
  name                = "TRADE_JSON_FF"
  format_type         = "JSON"
  strip_outer_array   = true
  date_format         = "YYYY-MM-DD"
  timestamp_format    = "YYYY-MM-DDHH24:MI:SS"
}

# ------------------------------------------
# 3. STREAM (CDC on raw table)
# ------------------------------------------

resource "snowflake_stream" "trade_events_stream" {
  database    = local.fqn_database
  schema      = local.fqn_schema
  name        = "TRADE_EVENTS_STREAM"
  on_table    = "${local.fqn_database}.${local.fqn_schema}.${snowflake_table.trade_events_raw.name}"
  append_only = true
  comment     = "Captures new inserts into TRADE_EVENTS_RAW"
}

# ------------------------------------------
# 4. STORED PROCEDURES
# ------------------------------------------

resource "snowflake_procedure" "process_trade_events" {
  database            = local.fqn_database
  schema              = local.fqn_schema
  name                = "PROCESS_TRADE_EVENTS"
  language            = "SQL"
  return_type         = "VARIANT"
  execute_as          = "CALLER"
  null_input_behavior = "CALLED ON NULL INPUT"

  arguments {
    name = "P_TRIGGERED_BY"
    type = "VARCHAR"
  }

  statement = <<-EOT
    DECLARE
        v_run_id VARCHAR;
        v_accepted INTEGER DEFAULT 0;
        v_rejected INTEGER DEFAULT 0;
        v_expired INTEGER DEFAULT 0;
        v_processed INTEGER DEFAULT 0;
        v_error VARCHAR DEFAULT NULL;
    BEGIN
        v_run_id := UUID_STRING();

        INSERT INTO PIPELINE_RUN_LOG (run_id, run_status, triggered_by)
        VALUES (:v_run_id, 'RUNNING', :P_TRIGGERED_BY);

        CREATE OR REPLACE TEMPORARY TABLE TMP_PENDING AS
        SELECT 
            event_id, trade_ref, version, instrument_type, notional,
            currency, trade_date, maturity_date, counterparty, trader_id,
            source_system, raw_payload, ingested_at
        FROM TRADE_EVENTS_STREAM
        WHERE METADATA$ACTION = 'INSERT';

        v_processed := (SELECT COUNT(*) FROM TMP_PENDING);

        -- Intra-batch deduplication: keep highest version per trade_ref
        CREATE OR REPLACE TEMPORARY TABLE TMP_RANKED AS
        SELECT 
            *,
            ROW_NUMBER() OVER (PARTITION BY trade_ref ORDER BY version DESC, ingested_at DESC) AS rn,
            MAX(version) OVER (PARTITION BY trade_ref) AS batch_max_version
        FROM TMP_PENDING;

        -- Classify winners against business rules + existing TRADES_VALID
        CREATE OR REPLACE TEMPORARY TABLE TMP_CLASSIFIED AS
        SELECT 
            e.event_id, e.trade_ref,
            e.VERSION AS incoming_version,
            COALESCE(t.version, -1) AS current_version,
            e.instrument_type, e.notional, e.currency,
            e.trade_date, e.maturity_date, e.counterparty,
            e.trader_id, e.source_system, e.raw_payload, e.ingested_at,
            CASE 
                WHEN e.maturity_date < CURRENT_DATE() THEN 'REJECT_MATURITY_IN_PAST'
                WHEN e.instrument_type = 'BOND' AND e.notional < 1000 THEN 'REJECT_BOND_NOTIONAL_TOO_LOW'
                WHEN t.trade_ref IS NOT NULL AND e.version < t.version THEN 'REJECT_VERSION_TOO_LOW'
                WHEN t.trade_ref IS NOT NULL AND e.version = t.version THEN 'ACCEPT_REPLACE'
                ELSE 'ACCEPT'
            END AS processing_action,
            CASE 
                WHEN e.maturity_date <= CURRENT_DATE() THEN 'EXPIRED'
                ELSE 'ACTIVE'
            END AS computed_status
        FROM TMP_RANKED e
        LEFT JOIN TRADES_VALID t ON e.trade_ref = t.trade_ref
        WHERE e.rn = 1;

        MERGE INTO TRADES_VALID t
        USING (SELECT * FROM TMP_CLASSIFIED WHERE processing_action IN ('ACCEPT', 'ACCEPT_REPLACE')) s
        ON t.trade_ref = s.trade_ref
        WHEN MATCHED THEN UPDATE SET
            t.version = s.incoming_version, t.instrument_type = s.instrument_type,
            t.notional = s.notional, t.currency = s.currency,
            t.trade_date = s.trade_date, t.maturity_date = s.maturity_date,
            t.counterparty = s.counterparty, t.trader_id = s.trader_id,
            t.source_system = s.source_system, t.trade_status = s.computed_status,
            t.updated_at = CURRENT_TIMESTAMP()
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

        INSERT INTO TRADES_REJECTED (
            rejection_id, event_id, trade_ref, version,
            instrument_type, notional, currency, trade_date, maturity_date,
            counterparty, trader_id, rejection_code, rejection_reason, raw_payload, rejected_at
        )
        SELECT UUID_STRING(), event_id, trade_ref, incoming_version,
            instrument_type, notional, currency, trade_date, maturity_date,
            counterparty, trader_id, processing_action,
            CASE 
                WHEN processing_action = 'REJECT_VERSION_TOO_LOW' THEN 'Version ' || incoming_version || ' < current ' || current_version || ' for ' || trade_ref
                WHEN processing_action = 'REJECT_MATURITY_IN_PAST' THEN 'Maturity ' || maturity_date || ' is before today (' || CURRENT_DATE() || ')'
                WHEN processing_action = 'REJECT_BOND_NOTIONAL_TOO_LOW' THEN 'BOND notional ' || notional || ' < minimum 1000'
                ELSE 'Rejected: ' || processing_action
            END, raw_payload, CURRENT_TIMESTAMP()
        FROM TMP_CLASSIFIED WHERE processing_action LIKE 'REJECT%'
        UNION ALL
        SELECT UUID_STRING(), event_id, trade_ref, version,
            instrument_type, notional, currency, trade_date, maturity_date,
            counterparty, trader_id, 'REJECT_VERSION_TOO_LOW',
            'Version ' || version || ' < batch max ' || batch_max_version || ' for ' || trade_ref,
            raw_payload, CURRENT_TIMESTAMP()
        FROM TMP_RANKED WHERE rn > 1 AND version < batch_max_version;

        v_rejected := SQLROWCOUNT;

        UPDATE TRADES_VALID
        SET trade_status = 'EXPIRED', updated_at = CURRENT_TIMESTAMP()
        WHERE maturity_date < CURRENT_DATE() AND trade_status = 'ACTIVE';

        v_expired := SQLROWCOUNT;

        UPDATE TRADE_EVENTS_RAW
        SET is_processed = TRUE
        WHERE event_id IN (SELECT event_id FROM TMP_PENDING);

        UPDATE PIPELINE_RUN_LOG
        SET run_end = CURRENT_TIMESTAMP(),
            events_processed = :v_processed, trades_accepted = :v_accepted,
            trades_rejected = :v_rejected, trades_expired = :v_expired,
            run_status = 'SUCCESS'
        WHERE run_id = :v_run_id;

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
  EOT
}

resource "snowflake_procedure" "load_trades_from_stage" {
  database            = local.fqn_database
  schema              = local.fqn_schema
  name                = "LOAD_TRADES_FROM_STAGE"
  language            = "SQL"
  return_type         = "VARCHAR"
  execute_as          = "CALLER"
  null_input_behavior = "CALLED ON NULL INPUT"

  statement = <<-EOT
    BEGIN
        COPY INTO TRADE_EVENTS_RAW (
            event_id, trade_ref, version, instrument_type, notional,
            currency, trade_date, maturity_date, counterparty, trader_id,
            source_system, raw_payload, ingested_at
        )
        FROM (
            SELECT 
                UUID_STRING(),
                $1:trade_ref::VARCHAR, $1:version::INTEGER, $1:instrument_type::VARCHAR,
                $1:notional::NUMBER(20,4), $1:currency::VARCHAR,
                $1:trade_date::DATE, $1:maturity_date::DATE,
                $1:counterparty::VARCHAR, $1:trader_id::VARCHAR,
                $1:source_system::VARCHAR, $1, CURRENT_TIMESTAMP()
            FROM @TRADE_INGEST_STAGE
        )
        FILE_FORMAT = (FORMAT_NAME = 'TRADE_JSON_FF')
        ON_ERROR = 'CONTINUE';

        RETURN 'Loaded ' || SQLROWCOUNT || ' events from stage';
    END;
  EOT
}

resource "snowflake_procedure" "expire_stale_trades" {
  database            = local.fqn_database
  schema              = local.fqn_schema
  name                = "EXPIRE_STALE_TRADES"
  language            = "SQL"
  return_type         = "VARCHAR"
  execute_as          = "CALLER"
  null_input_behavior = "CALLED ON NULL INPUT"

  statement = <<-EOT
    DECLARE
        v_count INTEGER;
    BEGIN
        UPDATE TRADES_VALID
        SET trade_status = 'EXPIRED', updated_at = CURRENT_TIMESTAMP()
        WHERE maturity_date < CURRENT_DATE() AND trade_status = 'ACTIVE';
        v_count := SQLROWCOUNT;
        RETURN 'Marked ' || v_count || ' trades as EXPIRED';
    END;
  EOT
}

# ------------------------------------------
# 5. TASKS (DAG Orchestration)
# ------------------------------------------

resource "snowflake_task" "load_from_stage" {
  database      = local.fqn_database
  schema        = local.fqn_schema
  name          = "TASK_LOAD_FROM_STAGE"
  warehouse     = local.fqn_warehouse
  schedule      = "5 MINUTES"
  enabled       = true
  sql_statement = "CALL LOAD_TRADES_FROM_STAGE()"
  depends_on    = [snowflake_procedure.load_trades_from_stage]
}

resource "snowflake_task" "process_trades" {
  database      = local.fqn_database
  schema        = local.fqn_schema
  name          = "TASK_PROCESS_TRADES"
  warehouse     = local.fqn_warehouse
  enabled       = true
  after         = [snowflake_task.load_from_stage.name]
  when          = "SYSTEM$STREAM_HAS_DATA('${local.fqn_database}.${local.fqn_schema}.TRADE_EVENTS_STREAM')"
  sql_statement = "CALL PROCESS_TRADE_EVENTS('TASK')"
  depends_on    = [
    snowflake_procedure.process_trade_events,
    snowflake_stream.trade_events_stream
  ]
}

resource "snowflake_task" "expire_trades" {
  database      = local.fqn_database
  schema        = local.fqn_schema
  name          = "TASK_EXPIRE_TRADES"
  warehouse     = local.fqn_warehouse
  schedule      = "USING CRON 0 0 * * * UTC"
  enabled       = true
  sql_statement = "CALL EXPIRE_STALE_TRADES()"
  depends_on    = [snowflake_procedure.expire_stale_trades]
}

# ------------------------------------------
# 6. ALERTS
# ------------------------------------------

resource "snowflake_alert" "pipeline_failure" {
  database  = local.fqn_database
  schema    = local.fqn_schema
  name      = "ALERT_PIPELINE_FAILURE"
  warehouse = local.fqn_warehouse
  schedule  = "10 MINUTES"
  enabled   = true
  condition = "SELECT 1 FROM PIPELINE_RUN_LOG WHERE run_status = 'FAILED' AND run_end >= DATEADD('minute', -10, CURRENT_TIMESTAMP())"
  action    = "CALL SYSTEM$SEND_EMAIL('${var.notification_integration_name}', '${var.alert_email_recipients}', '[ALERT] Trade Pipeline FAILED', 'A pipeline run failed in the last 10 minutes. Check PIPELINE_RUN_LOG for details.')"
}

resource "snowflake_alert" "high_rejection_rate" {
  database  = local.fqn_database
  schema    = local.fqn_schema
  name      = "ALERT_HIGH_REJECTION_RATE"
  warehouse = local.fqn_warehouse
  schedule  = "60 MINUTES"
  enabled   = true
  condition = "SELECT 1 FROM (SELECT RATIO_TO_REPORT(trades_rejected) OVER () AS rate FROM PIPELINE_RUN_LOG WHERE run_start >= DATEADD('hour', -1, CURRENT_TIMESTAMP())) WHERE rate > 0.30"
  action    = "CALL SYSTEM$SEND_EMAIL('${var.notification_integration_name}', '${var.alert_email_recipients}', '[ALERT] High Trade Rejection Rate (>30%)', 'More than 30% of trades were rejected in the last hour. Check TRADES_REJECTED for details.')"
}

resource "snowflake_alert" "pipeline_stalled" {
  database  = local.fqn_database
  schema    = local.fqn_schema
  name      = "ALERT_PIPELINE_STALLED"
  warehouse = local.fqn_warehouse
  schedule  = "30 MINUTES"
  enabled   = true
  condition = "SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM PIPELINE_RUN_LOG WHERE run_status = 'SUCCESS' AND run_start >= DATEADD('minute', -30, CURRENT_TIMESTAMP()))"
  action    = "CALL SYSTEM$SEND_EMAIL('${var.notification_integration_name}', '${var.alert_email_recipients}', '[ALERT] Pipeline Stalled - No Run in 30 Min', 'No successful pipeline run in the last 30 minutes. Check task status.')"
}

# ------------------------------------------
# 7. MONITORING VIEWS
# ------------------------------------------

resource "snowflake_view" "trade_book_summary" {
  database  = local.fqn_database
  schema    = local.fqn_schema
  name      = "V_TRADE_BOOK_SUMMARY"
  statement = <<-EOT
    SELECT 
        trade_status, instrument_type, currency,
        COUNT(*) AS trade_count,
        SUM(notional) AS total_notional,
        MIN(maturity_date) AS earliest_maturity,
        MAX(maturity_date) AS latest_maturity
    FROM ${local.fqn_database}.${local.fqn_schema}.TRADES_VALID
    GROUP BY trade_status, instrument_type, currency
  EOT
  depends_on = [snowflake_table.trades_valid]
}

resource "snowflake_view" "rejection_summary" {
  database  = local.fqn_database
  schema    = local.fqn_schema
  name      = "V_REJECTION_SUMMARY"
  statement = <<-EOT
    SELECT 
        DATE_TRUNC('hour', rejected_at) AS rejection_hour,
        rejection_code,
        COUNT(*) AS rejection_count
    FROM ${local.fqn_database}.${local.fqn_schema}.TRADES_REJECTED
    GROUP BY 1, 2
    ORDER BY 1 DESC
  EOT
  depends_on = [snowflake_table.trades_rejected]
}

resource "snowflake_view" "pipeline_health" {
  database  = local.fqn_database
  schema    = local.fqn_schema
  name      = "V_PIPELINE_HEALTH"
  statement = <<-EOT
    SELECT 
        run_id, run_start, run_end,
        DATEDIFF('second', run_start, COALESCE(run_end, CURRENT_TIMESTAMP())) AS duration_secs,
        events_processed, trades_accepted, trades_rejected, trades_expired,
        run_status, error_message
    FROM ${local.fqn_database}.${local.fqn_schema}.PIPELINE_RUN_LOG
    WHERE run_start >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
    ORDER BY run_start DESC
  EOT
  depends_on = [snowflake_table.pipeline_run_log]
}
