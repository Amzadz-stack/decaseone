# ==========================================
# Trade Pipeline - Terraform Outputs
# ==========================================

output "database" {
  description = "Target database"
  value       = local.fqn_database
}

output "schema" {
  description = "Target schema"
  value       = local.fqn_schema
}

output "tables" {
  description = "Pipeline tables created"
  value = {
    trade_events_raw = snowflake_table.trade_events_raw.name
    trades_valid     = snowflake_table.trades_valid.name
    trades_rejected  = snowflake_table.trades_rejected.name
    pipeline_run_log = snowflake_table.pipeline_run_log.name
  }
}

output "stream" {
  description = "CDC stream name"
  value       = snowflake_stream.trade_events_stream.name
}

output "stage" {
  description = "Internal stage name"
  value       = snowflake_stage.trade_ingest_stage.name
}

output "procedures" {
  description = "Stored procedures created"
  value = {
    process_trade_events   = snowflake_procedure.process_trade_events.name
    load_trades_from_stage = snowflake_procedure.load_trades_from_stage.name
    expire_stale_trades    = snowflake_procedure.expire_stale_trades.name
  }
}

output "tasks" {
  description = "Pipeline tasks created"
  value = {
    load_from_stage = snowflake_task.load_from_stage.name
    process_trades  = snowflake_task.process_trades.name
    expire_trades   = snowflake_task.expire_trades.name
  }
}

output "alerts" {
  description = "Monitoring alerts created"
  value = {
    pipeline_failure    = snowflake_alert.pipeline_failure.name
    high_rejection_rate = snowflake_alert.high_rejection_rate.name
    pipeline_stalled    = snowflake_alert.pipeline_stalled.name
  }
}

output "views" {
  description = "Monitoring views created"
  value = {
    trade_book_summary = snowflake_view.trade_book_summary.name
    rejection_summary  = snowflake_view.rejection_summary.name
    pipeline_health    = snowflake_view.pipeline_health.name
  }
}
