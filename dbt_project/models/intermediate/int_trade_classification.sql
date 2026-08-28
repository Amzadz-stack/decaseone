-- Intermediate model: joins staged events with the current trade book
-- to apply all five business rules and assign a processing_action.
-- Materialized as EPHEMERAL so no extra table is written.

{{
    config(
        materialized = 'ephemeral'
    )
}}

WITH staged AS (
    SELECT * FROM {{ ref('stg_raw_trades') }}
),

current_book AS (
    -- Snapshot of the existing trade book for version comparisons
    SELECT trade_ref, version AS current_version
    FROM {{ source('final', 'trades') }}
),

classified AS (
    SELECT 
        s.event_id,
        s.trade_ref,
        s.version AS incoming_version,
        COALESCE(b.current_version, -1) AS current_version,
        s.instrument_type,
        s.notional,
        s.currency,
        s.trade_date,
        s.maturity_date,
        s.counterparty,
        s.trader_id,
        s.source_system,
        s.raw_payload,
        s.ingested_at,
        s.processing_date,

        -- Business rule classification
        CASE 
            -- R3: maturity date strictly before today -> reject immediately[span_6](start_span)[span_6](end_span)
            WHEN s.maturity_date < s.processing_date 
                THEN 'REJECT_MATURITY_IN_PAST'

            -- R5 (custom): BOND trades below minimum notional -> reject[span_7](start_span)[span_7](end_span)
            WHEN s.instrument_type = 'BOND' 
             AND s.notional < var('min_bond_notional', 1000) 
                THEN 'REJECT_BOND_NOTIONAL_TOO_LOW'

            -- R1: incoming version is lower than what is already stored[span_8](start_span)[span_8](end_span)
            WHEN b.trade_ref IS NOT NULL 
             AND s.version < b.current_version 
                THEN 'REJECT_VERSION_TOO_LOW'

            -- R2: same version as stored -> overwrite (idempotent replace)[span_9](start_span)[span_9](end_span)
            WHEN b.trade_ref IS NOT NULL 
             AND s.version = b.current_version 
                THEN 'ACCEPT_REPLACE'

            -- All other cases: new trade or legitimate version upgrade
            ELSE 'ACCEPT'
        END AS processing_action,

        -- R4: pre-compute expiry status for accepted trades[span_10](start_span)[span_10](end_span)
        CASE 
            WHEN s.maturity_date <= s.processing_date THEN 'EXPIRED'
            ELSE 'ACTIVE'
        END AS computed_status,

        -- Human-readable rejection reason (used by rejected_trades model)
        CASE 
            WHEN s.maturity_date < s.processing_date 
                THEN 'Maturity date ' || s.maturity_date::VARCHAR || ' is before today (' || s.processing_date::VARCHAR || ')'
            WHEN s.instrument_type = 'BOND' 
             AND s.notional < var('min_bond_notional', 1000) 
                THEN 'BOND notional ' || s.notional::VARCHAR || ' is below minimum of ' || var('min_bond_notional', 1000)
            WHEN b.trade_ref IS NOT NULL 
             AND s.version < b.current_version 
                THEN 'Incoming version ' || s.version::VARCHAR || ' < current version ' || b.current_version::VARCHAR
            ELSE NULL
        END AS rejection_reason

    FROM staged s
    LEFT JOIN current_book b ON s.trade_ref = b.trade_ref
)

SELECT * FROM classified
