
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/../function"
  output_path = "${path.module}/.build/function-source.zip"
  excludes    = ["__pycache__", "*.pyc", "test_*.py", ".pytest_cache", "venv"]
}

resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-cf-source"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  labels = local.default_labels
}

resource "google_storage_bucket_object" "function_archive" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

resource "google_cloudfunctions2_function" "order_processor" {
  name        = "${local.name_prefix}-order-processor"
  location    = var.region
  description = "Processes incoming order webhooks, anonymizes PII, stores data"

  build_config {
    runtime     = "python312"
    entry_point = "process_order"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_archive.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.function_sa.email


    vpc_connector                 = google_vpc_access_connector.pipeline_connector.id
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"

    environment_variables = {
      PROJECT_ID            = var.project_id
      RAW_BUCKET            = google_storage_bucket.raw_data.name
      PROCESSED_BUCKET      = google_storage_bucket.processed_data.name
      BQ_DATASET            = google_bigquery_dataset.analytics.dataset_id
      BQ_TABLE              = google_bigquery_table.anonymized_orders.table_id
      HMAC_SECRET_ID        = google_secret_manager_secret.hmac_key.secret_id
      WEBHOOK_TOKEN_SECRET  = google_secret_manager_secret.webhook_token.secret_id
      LOG_LEVEL             = var.environment == "prod" ? "WARNING" : "DEBUG"
    }

    ingress_settings = "ALLOW_ALL" # for Webhook needs to be reachable
  }

  labels = local.default_labels
}

resource "google_project_iam_audit_config" "data_access" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }

  audit_log_config {
    log_type = "ADMIN_READ"
  }
}
