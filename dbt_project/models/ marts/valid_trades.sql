{{
    config(
        materialized='incremental',
        unique_key='trade_ref'
    )
}}

WITH classified AS (
    SELECT * FROM {{ ref('int_trade_classification') }}
    WHERE processing_action IN ('ACCEPT', 'ACCEPT_REPLACE')
)

SELECT 
    trade_ref,
    incoming_version AS version,
    instrument_type,
    notional,
    currency,
    trade_date,
    maturity_date,
    counterparty,
    trader_id,
    source_system,
    computed_status AS trade_status,
    CURRENT_TIMESTAMP() AS created_at,
    CURRENT_TIMESTAMP() AS updated_at
FROM classified
QUALIFY ROW_NUMBER() OVER (PARTITION BY trade_ref ORDER BY incoming_version DESC, ingested_at DESC) = 1
