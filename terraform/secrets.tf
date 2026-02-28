
resource "google_secret_manager_secret" "hmac_key" {
  secret_id = "${local.name_prefix}-pii-hmac-key"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = local.default_labels

  rotation {
    rotation_period = "7776000s" # 90 days. #auto rotation
  }
}

# Initial secret version — in production, rotate this regularly
# The actual value should be set via `gcloud` or CI/CD, not in state.
# This resource creates a placeholder; replace it post-deploy.
resource "google_secret_manager_secret_version" "hmac_key_initial" {
  secret = google_secret_manager_secret.hmac_key.id

  # Generate a cryptographically random 32-byte key
  secret_data = base64encode(random_bytes.hmac_seed.base64)

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "random_bytes" "hmac_seed" {
  length = 32
}


resource "google_secret_manager_secret" "webhook_token" {
  secret_id = "${local.name_prefix}-webhook-auth-token"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = local.default_labels
}

resource "google_secret_manager_secret_version" "webhook_token_initial" {
  secret      = google_secret_manager_secret.webhook_token.id
  secret_data = random_password.webhook_token.result

  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "random_password" "webhook_token" {
  length  = 48
  special = false
}


resource "google_secret_manager_secret_iam_member" "fn_webhook_accessor" {
  secret_id = google_secret_manager_secret.webhook_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.function_sa.email}"
}
