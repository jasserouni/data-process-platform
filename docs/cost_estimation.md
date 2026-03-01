# Cost Estimation

## Assumptions

- Region: europe-west3 (Frankfurt)
- ~10,000 orders per month
- Average payload: ~500 bytes
- Development-level environment
- Serverless architecture (scale-to-zero)

---

## Estimated Monthly Cost

### Cloud Functions

- Very low invocation cost
- Minimal compute usage (256MB, ~500ms per request)
- Mostly free due to GCP free tier

**Estimated cost:** ~ $0.01 / month

---

### Cloud Storage

- Stores small amounts of raw and processed data
- Main cost comes from operations (writes), not storage size

**Estimated cost:** ~ $0.10 / month

---

### BigQuery

- Small data volume
- Few queries per month
- Mostly within free tier limits

**Estimated cost:** ~ $0.01 / month

---

### Cloud KMS

- Includes key usage and encryption operations

**Estimated cost:** ~ $0.12 / month

---

### Secret Manager

- Costs based on secret access operations

**Estimated cost:** ~ $0.03 / month

---

### Networking (Main Cost)

Includes:
- Serverless VPC Connector
- Cloud NAT

These run continuously, even with low traffic.

**Estimated cost:** ~ $12 / month

---

## Total Monthly Cost

| Service | Cost |
|--------|------|
| Cloud Functions | $0.01 |
| Cloud Storage | $0.10 |
| BigQuery | $0.01 |
| Cloud KMS | $0.12 |
| Secret Manager | $0.03 |
| Networking | $12.00 |
| **Total** | **~ $12–13 / month** |

---

## Key Insight

Most of the cost comes from networking, not compute or storage.

---

## Cost Optimization

- Remove VPC connector in dev → cost drops below $1/month
- Use free tiers (already covers most services)
- Apply storage lifecycle rules for older data
- Keep serverless design to avoid idle costs

---

## Scaling Scenario

At **1 million orders/month**:

- Estimated total cost: ~ $45–50 / month

Why it scales well:
- Serverless compute grows with usage
- Storage increases gradually
- BigQuery remains cost-efficient

The architecture scales linearly without sudden cost increases.
