# GDPR Compliance Report

## Overview

This project processes e-commerce order data that includes personal information (PII) from EU users.  
The system is designed to follow GDPR principles by default.

The main goal is to:
- Handle personal data safely
- Only use what is needed
- Protect user privacy at every step

---

## Data Classification & PII Handling

The system separates data into two types:

**PII (personal data):**
- Email
- Full name
- Address

**Non-PII (used for analytics):**
- Order ID
- Product (SKU)
- Quantity
- Price and total
- Currency
- City / country

PII is not used directly.  
Instead, it is **pseudonymized** using HMAC-SHA256 with a secret key stored securely.

This means:
- We can still analyze data
- But we cannot easily identify users

If the key is deleted, re-identification becomes impossible.  
This supports the **right to erasure (GDPR Article 17)**.

Also, sensitive data like `payment_last4` is completely removed.

---

## Data Minimization & Retention

We only keep the data that is really needed.

- Raw data (with PII) → stored for **90 days only**
- Processed (anonymized) data → stored for **365 days**
- BigQuery data → expires after **2 years**

This ensures:
- Less risk
- Better compliance with GDPR storage rules

---

## Security Measures

### Encryption

- Data is encrypted at rest using **Cloud KMS (CMEK)**
- Keys are rotated every 90 days
- Data in transit is protected with HTTPS (TLS)

---

### Access Control

- The system uses a dedicated service account
- Only minimal permissions are granted:
  - Write to storage
  - Write to BigQuery
  - Read secrets

No admin access is given.

Webhook requests are protected using a **Bearer token**, checked securely.

---

### Network Security

- The function runs inside a private VPC
- Firewall blocks unwanted traffic
- No public IPs are exposed
- Cloud NAT handles secure outbound traffic

---

### Logging & Audit

- All actions are logged (read, write, admin)
- Logs help with monitoring and investigations
- Alerts are triggered if something unusual happens

---

## Data Subject Rights

The system supports key GDPR rights:

- **Access / Rectification**  
  We can find user data by recreating the hashed identifier

- **Erasure (Right to be forgotten)**  
  - Data is automatically deleted after 90 days  
  - Data can also be deleted manually  
  - Rotating the key makes re-identification impossible  

---

## Incident Response

- All access is tracked using audit logs
- Monitoring alerts help detect issues quickly
- The system supports the **72-hour breach notification rule**

---

## Conclusion

This system follows a strong security approach:

- Pseudonymization of personal data
- Encryption with managed keys
- Strict access control (least privilege)
- Automatic data deletion
- Full logging and monitoring

All of this ensures **privacy by design**, as required by GDPR.
