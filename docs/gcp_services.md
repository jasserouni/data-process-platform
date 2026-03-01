# GCP Services Documentation

## Overview

This project uses Google Cloud services to process incoming e-commerce webhooks in a secure, scalable, and cost-efficient way.  
The architecture is fully serverless, which means there are no servers to manage and it automatically scales based on traffic.

The goal is simple:
- Receive webhook orders
- Validate and authenticate them
- Store raw data securely
- Pseudonymize sensitive fields
- Send clean data to analytics

---

## Services Used

### Cloud Functions v2

Cloud Functions v2 handles incoming HTTPS webhook requests.  
It processes each order by validating the payload, checking authentication, storing raw data, anonymizing sensitive fields, and writing analytics data.

**Why this service:**
- Fully serverless (no infrastructure management)
- Scales automatically
- Supports VPC networking
- Longer execution time compared to v1

---

### Cloud Storage (GCS)

Cloud Storage is used for two purposes:
- Storing raw order data (including PII)
- Storing processed/anonymized data

Lifecycle rules are used to automatically delete or move old data after 90 days.

**Why this service:**
- Durable and highly available
- Supports encryption with CMEK
- Easy lifecycle management
- Cost-effective for small payloads

---

### BigQuery

BigQuery stores anonymized order data for analytics.  
It allows fast SQL queries for reporting and business insights.

**Why this service:**
- Fully managed
- No database maintenance
- Built-in scaling
- Cost-efficient for small workloads
- Supports streaming inserts

---

### Secret Manager

Stores:
- Webhook authentication tokens
- HMAC keys

**Why this service:**
- Secure secret storage
- Version control for secrets
- IAM-based access control
- Prevents secrets from being stored in code

---

### Cloud KMS

Manages encryption keys used by storage services.

**Why this service:**
- Enables key rotation
- Allows customer-managed encryption keys (CMEK)
- Supports compliance and GDPR requirements

---

### Networking (VPC, Serverless VPC Access, Cloud NAT)

The architecture uses:
- A VPC for network isolation
- Serverless VPC Access to connect the function to the VPC
- Cloud NAT for secure outbound internet access without public IPs

**Why this setup:**
- Keeps traffic private
- Applies firewall rules
- Prevents public IP exposure
- Improves security

---

### Monitoring, Logging, and IAM

- Cloud Monitoring → dashboards and alerts  
- Cloud Logging → centralized logs and audit trails  
- IAM → fine-grained permissions (least privilege)

The Cloud Function service account:
- Can write to GCS and BigQuery
- Can read secrets
- Has no admin permis
