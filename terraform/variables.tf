
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resource deployment"
  type        = string
  default     = "europe-west3" #GDPR-friendly EU region
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "raw_data_retention_days" {
  description = "Number of days to retain raw (PII-containing) data before automatic deletion"
  type        = number
  default     = 90 # 90-day retention for raw PII data per GDPR minimisation
}

variable "processed_data_retention_days" {
  description = "Number of days to retain processed/anonymized data"
  type        = number
  default     = 365
}

variable "bigquery_partition_expiration_ms" {
  description = "Expiration time for BigQuery table partitions in milliseconds (default: 2 years)"
  type        = number
  default     = 63072000000 # 2 years in ms
}

variable "connector_cidr" {
  description = "CIDR range for Serverless VPC Access connector"
  type        = string
  default     = "10.8.0.0/28"
}

variable "alert_email" {
  description = "Email address for monitoring alert notifications"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

locals {
  default_labels = merge(var.labels, {
    project     = "yepoda-data-pipeline"
    environment = var.environment
    managed_by  = "terraform"
  })
  
  name_prefix = "yepoda-${var.environment}"
}
