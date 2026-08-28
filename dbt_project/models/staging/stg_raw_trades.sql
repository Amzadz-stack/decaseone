{{ config(materialized='view') }}

SELECT
    event_id,
    trade_ref,
    version,
    instrument_type,
    notional,
    currency,
    trade_date,
    maturity_date,
    counterparty,
    trader_id,
    source_system,
    raw_payload,
    ingested_at,
    CURRENT_DATE() AS processing_date
FROM {{ source('raw', 'trade_events') }}
WHERE is_processed = FALSE
