# Data Process Platform

A secure, GDPR-compliant data pipeline on Google Cloud Platform that processes e-commerce order data, pseudonymizes PII, and produces analytics-ready datasets.

## Architecture

![Architecture Diagram](docs/architecture.png)


### Data Flow

1. **Ingestion** — An HTTPS POST from the e-commerce webhook arrives at the Cloud Function endpoint with a Bearer token.
2. **Validation** — The function validates the order schema (required fields, types, format constraints).
3. **Raw Storage** — The original payload (including PII) is stored in the **raw data bucket** with a 90-day lifecycle policy.
4. **Pseudonymization** — PII fields (`email`, `name`, `address`) are hashed with HMAC-SHA256 using a key from Secret Manager. Only city/country are retained for regional analytics.
5. **Processed Storage** — The anonymized record is stored in the **processed data bucket** (365-day retention, Nearline after 90 days).
6. **Analytics** — The anonymized record is written to a BigQuery partitioned table for analytics queries.

## Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/install) (`gcloud`)
- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- Python 3.12+
- A GCP project with billing enabled

---

## Setup & Deployment

### 1. Clone the repository

```bash
git clone https://github.com/jasserouni/data-process-platform.git
cd data-process-platform
```

### 2. Configure Terraform variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GCP project ID, region, and email
```

### 3. Create the Terraform state bucket

```bash
gsutil mb -l europe-west3 gs://yepoda-terraform-state
gsutil versioning set on gs://yepoda-terraform-state
```

### 4. Deploy infrastructure

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 5. Test the endpoint

```bash
# Get the function URL
FUNCTION_URL=$(terraform output -raw function_url)

# Get the webhook token from Secret Manager
WEBHOOK_TOKEN=$(gcloud secrets versions access latest \
  --secret="yepoda-dev-webhook-auth-token" \
  --project="<your-project-id>")

# Send a test order
curl -X POST "${FUNCTION_URL}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${WEBHOOK_TOKEN}" \
  -d '{
    "order_id": "ORD-2024-001",
    "timestamp": "2024-12-04T10:30:00Z",
    "customer": {
      "email": "customer@example.com",
      "name": "Jane Doe",
      "address": "123 Main St, Berlin, Germany"
    },
    "items": [{"sku": "PROD-001", "quantity": 2, "price": 29.99}],
    "total": 59.98,
    "payment_last4": "4242",
    "currency": "EUR"
  }'
```

### 6. Verify data in BigQuery

```sql
SELECT order_id, customer_id_hash, customer_city, total, currency
FROM `<project>.yepoda_dev_order_analytics.anonymized_orders`
ORDER BY processed_at DESC
LIMIT 10;
```

---

## Running Tests Locally

```bash
cd function
pip install -r requirements.txt
pip install pytest pytest-cov
pytest test_main.py -v --cov=main --cov-report=term-missing
```

---

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs on every push and PR.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | WIF provider resource name |
| `GCP_SERVICE_ACCOUNT` | Deployment service account email |
| `INFRACOST_API_KEY` | Infracost API key (optional, for cost estimates) |

---

## Cleanup

```bash
cd terraform
terraform destroy
gsutil rm -r gs://yepoda-terraform-state
```

---
