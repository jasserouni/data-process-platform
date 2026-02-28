resource "google_bigquery_dataset" "analytics" {
  dataset_id  = "${replace(local.name_prefix, "-", "_")}_order_analytics"
  description = "Anonymized e-commerce order analytics data"
  location    = var.region

  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.storage_key.id
  }

  default_partition_expiration_ms = var.bigquery_partition_expiration_ms

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  access {
    role          = "WRITER"
    user_by_email = google_service_account.function_sa.email
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }

  labels = local.default_labels
}

resource "google_bigquery_table" "anonymized_orders" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "anonymized_orders"

  description = "Anonymized e-commerce order data with hashed PII fields"

  deletion_protection = false # Set to true in production

  time_partitioning {
    type          = "DAY"
    field         = "order_timestamp"
    expiration_ms = var.bigquery_partition_expiration_ms
  }

  clustering = ["currency"]

  schema = jsonencode([
    {
      name        = "order_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique order identifier"
    },
    {
      name        = "order_timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Time the order was placed"
    },
    {
      name        = "customer_id_hash"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "SHA-256 hash of customer email (pseudonymized)"
    },
    {
      name        = "customer_name_hash"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "SHA-256 hash of customer name (pseudonymized)"
    },
    {
      name        = "customer_city"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "City extracted from address (non-PII for regional analytics)"
    },
    {
      name        = "customer_country"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Country extracted from address (non-PII for regional analytics)"
    },
    {
      name = "items"
      type = "RECORD"
      mode = "REPEATED"
      fields = [
        {
          name = "sku"
          type = "STRING"
          mode = "REQUIRED"
        },
        {
          name = "quantity"
          type = "INTEGER"
          mode = "REQUIRED"
        },
        {
          name = "price"
          type = "FLOAT"
          mode = "REQUIRED"
        }
      ]
    },
    {
      name        = "total"
      type        = "FLOAT"
      mode        = "REQUIRED"
      description = "Order total amount"
    },
    {
      name        = "currency"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Payment currency"
    },
    {
      name        = "processed_at"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the record was processed by the pipeline"
    }
  ])

  labels = local.default_labels
}
