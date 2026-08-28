{{
    config(
        materialized='incremental'
    )
}}

SELECT
    UUID_STRING() AS rejection_id,
    event_id,
    trade_ref,
    incoming_version AS version,
    instrument_type,
    notional,
    currency,
    trade_date,
    maturity_date,
    counterparty,
    trader_id,
    processing_action AS rejection_code,
    rejection_reason,
    raw_payload,
    CURRENT_TIMESTAMP() AS rejected_at
FROM {{ ref('int_trade_classification') }}
WHERE processing_action LIKE 'REJECT%'
