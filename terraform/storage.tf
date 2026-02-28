
resource "google_kms_key_ring" "pipeline_keyring" {
  name     = "${local.name_prefix}-pipeline-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "storage_key" {
  name            = "${local.name_prefix}-storage-key"
  key_ring        = google_kms_key_ring.pipeline_keyring.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

data "google_storage_project_service_account" "gcs_account" {
}

resource "google_kms_crypto_key_iam_member" "gcs_cmek" {
  crypto_key_id = google_kms_crypto_key.storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

resource "google_storage_bucket" "raw_data" {
  name     = "${local.name_prefix}-raw-order-data"
  location = var.region

  storage_class = "STANDARD"

  # Security: Prevent accidental public exposure
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # GDPR: Auto-delete raw PII data after retention period
  lifecycle_rule {
    condition {
      age = var.raw_data_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Clean up old versions after 30 days
  lifecycle_rule {
    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Encryption at rest with CMEK
  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_key.id
  }

  # Soft-delete for recovery (14 days)
  soft_delete_policy {
    retention_duration_seconds = 1209600 # 14 days
  }

  labels = local.default_labels

  depends_on = [google_kms_crypto_key_iam_member.gcs_cmek]
}

resource "google_storage_bucket" "processed_data" {
  name     = "${local.name_prefix}-processed-order-data"
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.processed_data_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Transition to Nearline after 90 days for cost savings
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_key.id
  }

  soft_delete_policy {
    retention_duration_seconds = 1209600
  }

  labels = local.default_labels

  depends_on = [google_kms_crypto_key_iam_member.gcs_cmek]
}
