
resource "google_service_account" "function_sa" {
  account_id   = "${local.name_prefix}-fn-sa"
  display_name = "Data Pipeline Cloud Function Service Account"
  description  = "Least-privilege SA for the order processing Cloud Function"
}


resource "google_storage_bucket_iam_member" "fn_raw_writer" {
  bucket = google_storage_bucket.raw_data.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_storage_bucket_iam_member" "fn_processed_writer" {
  bucket = google_storage_bucket.processed_data.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_bigquery_dataset_iam_member" "fn_bq_writer" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.function_sa.email}"
}


resource "google_project_iam_member" "fn_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "fn_hmac_accessor" {
  secret_id = google_secret_manager_secret.hmac_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_kms_crypto_key_iam_member" "fn_cmek_user" {
  crypto_key_id = google_kms_crypto_key.storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "fn_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.order_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.function_sa.email}"
}
