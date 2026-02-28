
output "function_url" {
  description = "URL of the deployed Cloud Function (order processing endpoint)"
  value       = google_cloudfunctions2_function.order_processor.url
}

output "raw_bucket_name" {
  description = "Name of the raw data storage bucket (contains PII)"
  value       = google_storage_bucket.raw_data.name
}

output "processed_bucket_name" {
  description = "Name of the processed/anonymized data bucket"
  value       = google_storage_bucket.processed_data.name
}

output "bigquery_dataset" {
  description = "BigQuery dataset ID for analytics queries"
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "bigquery_table" {
  description = "BigQuery table ID for anonymized order data"
  value       = "${google_bigquery_dataset.analytics.dataset_id}.${google_bigquery_table.anonymized_orders.table_id}"
}

output "function_service_account" {
  description = "Email of the Cloud Function service account"
  value       = google_service_account.function_sa.email
}

output "vpc_network" {
  description = "VPC network name"
  value       = google_compute_network.pipeline_vpc.name
}

output "kms_key" {
  description = "KMS key used for encryption at rest"
  value       = google_kms_crypto_key.storage_key.id
}
