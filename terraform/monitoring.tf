
resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email != "" ? 1 : 0
  display_name = "Pipeline Alert Email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

locals {
  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
}


resource "google_monitoring_alert_policy" "function_errors" {
  display_name = "${local.name_prefix} - High Function Error Rate"
  combiner     = "OR"

  conditions {
    display_name = "Error rate > 5%"

    condition_threshold {
      filter     = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class != \"2xx\""
      duration   = "300s"
      comparison = "COMPARISON_GT"

      threshold_value = 5

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "The order processing function error rate has exceeded 5%. Check Cloud Logging for details."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "function_latency" {
  display_name = "${local.name_prefix} - High Function Latency"
  combiner     = "OR"

  conditions {
    display_name = "p99 latency > 30s"

    condition_threshold {
      filter     = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_latencies\""
      duration   = "300s"
      comparison = "COMPARISON_GT"

      threshold_value = 30000 # 30 seconds in ms

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_99"
        cross_series_reducer = "REDUCE_MAX"
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_logging_metric" "bq_insert_errors" {
  name   = "${local.name_prefix}-bq-insert-errors"
  filter = "resource.type=\"cloud_run_revision\" AND textPayload=~\"BigQuery insert failed\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "bq_insert_failures" {
  display_name = "${local.name_prefix} - BigQuery Insert Failures"
  combiner     = "OR"

  conditions {
    display_name = "BQ insert errors detected"

    condition_threshold {
      filter     = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.bq_insert_errors.name}\""
      duration   = "0s"
      comparison = "COMPARISON_GT"

      threshold_value = 0

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = local.notification_channels
}

resource "google_monitoring_dashboard" "pipeline_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Yepoda Data Pipeline - ${var.environment}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Request Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_count\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 6
          width  = 6
          height = 4
          widget = {
            title = "Function Latency (p50/p95/p99)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_run_revision\" AND metric.type = \"run.googleapis.com/request_latencies\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_PERCENTILE_99"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "GCS Objects Written"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"gcs_bucket\" AND metric.type = \"storage.googleapis.com/api/request_count\" AND metric.labels.method = \"storage.objects.create\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "BigQuery Insert Errors"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type = \"logging.googleapis.com/user/${google_logging_metric.bq_insert_errors.name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
}
