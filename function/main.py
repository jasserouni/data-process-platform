
import datetime
import hashlib
import hmac
import json
import logging
import os
import re
import uuid

import functions_framework
from google.cloud import bigquery, secretmanager, storage

PROJECT_ID = os.environ.get("PROJECT_ID", "")
RAW_BUCKET = os.environ.get("RAW_BUCKET", "")
PROCESSED_BUCKET = os.environ.get("PROCESSED_BUCKET", "")
BQ_DATASET = os.environ.get("BQ_DATASET", "")
BQ_TABLE = os.environ.get("BQ_TABLE", "")
HMAC_SECRET_ID = os.environ.get("HMAC_SECRET_ID", "")
WEBHOOK_TOKEN_SECRET = os.environ.get("WEBHOOK_TOKEN_SECRET", "")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")

logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO))
logger = logging.getLogger("order_processor")

#initialization

_storage_client = None
_bq_client = None
_sm_client = None
_hmac_key = None
_webhook_token = None


def get_storage_client():
    global _storage_client
    if _storage_client is None:
        _storage_client = storage.Client(project=PROJECT_ID)
    return _storage_client


def get_bq_client():
    global _bq_client
    if _bq_client is None:
        _bq_client = bigquery.Client(project=PROJECT_ID)
    return _bq_client


def get_secret(secret_id: str) -> str:
    #get it from secret manager
    global _sm_client
    if _sm_client is None:
        _sm_client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = _sm_client.access_secret_version(request={"name": name})
    return response.payload.data.decode("utf-8")


def get_hmac_key() -> bytes:
    """Return the cached HMAC key (fetched once per cold start)."""
    global _hmac_key
    if _hmac_key is None:
        _hmac_key = get_secret(HMAC_SECRET_ID).encode("utf-8")
    return _hmac_key


def get_webhook_token() -> str:
    """Return the cached webhook authentication token."""
    global _webhook_token
    if _webhook_token is None:
        _webhook_token = get_secret(WEBHOOK_TOKEN_SECRET)
    return _webhook_token

REQUIRED_FIELDS = {"order_id", "timestamp", "customer", "items", "total", "currency"}
REQUIRED_CUSTOMER_FIELDS = {"email", "name", "address"}
REQUIRED_ITEM_FIELDS = {"sku", "quantity", "price"}

ORDER_ID_PATTERN = re.compile(r"^ORD-\d{4}-\d{3,}$")
EMAIL_PATTERN = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class ValidationError(Exception):

    def validate_order(data: dict) -> None:

        missing = REQUIRED_FIELDS - data.keys()
        if missing:
            raise ValidationError(f"Missing required fields: {missing}")

        if not ORDER_ID_PATTERN.match(data["order_id"]):
            raise ValidationError(f"Invalid order_id format: {data['order_id']}")

        try:
            datetime.datetime.fromisoformat(data["timestamp"].replace("Z", "+00:00"))
        except (ValueError, AttributeError) as exc:
            raise ValidationError(f"Invalid timestamp: {exc}")

        customer = data["customer"]
        if not isinstance(customer, dict):
            raise ValidationError("'customer' must be an object")
        missing_cust = REQUIRED_CUSTOMER_FIELDS - customer.keys()
        if missing_cust:
            raise ValidationError(f"Missing customer fields: {missing_cust}")
        if not EMAIL_PATTERN.match(customer["email"]):
            raise ValidationError(f"Invalid email format: {customer['email']}")


        items = data["items"]
        if not isinstance(items, list) or len(items) == 0:
            raise ValidationError("'items' must be a non-empty array")
        for i, item in enumerate(items):
            missing_item = REQUIRED_ITEM_FIELDS - item.keys()
            if missing_item:
                raise ValidationError(f"Item {i} missing fields: {missing_item}")
            if not isinstance(item["quantity"], int) or item["quantity"] <= 0:
                raise ValidationError(f"Item {i} has invalid quantity")
            if not isinstance(item["price"], (int, float)) or item["price"] < 0:
                raise ValidationError(f"Item {i} has invalid price")


        if not isinstance(data["total"], (int, float)) or data["total"] < 0:
            raise ValidationError("Invalid total amount")


    def pseudonymize(value: str) -> str:
        return hmac.new(get_hmac_key(), value.lower().strip().encode("utf-8"), hashlib.sha256).hexdigest()


def extract_location(address: str) -> tuple[str, str]:

    #Extract city and country from a comma-separated address string.
    #Returns (city, country). These are considered non-PII for analytics.

    parts = [p.strip() for p in address.split(",")]
    if len(parts) >= 3:
        return parts[-2], parts[-1]
    if len(parts) == 2:
        return parts[0], parts[1]
    return ("", "")


def anonymize_order(data: dict) -> dict:

    customer = data["customer"]
    city, country = extract_location(customer["address"])

    return {
        "order_id": data["order_id"],
        "order_timestamp": data["timestamp"],
        "customer_id_hash": pseudonymize(customer["email"]),
        "customer_name_hash": pseudonymize(customer["name"]),
        "customer_city": city,
        "customer_country": country,
        "items": [
            {"sku": item["sku"], "quantity": item["quantity"], "price": item["price"]}
            for item in data["items"]
        ],
        "total": data["total"],
        "currency": data["currency"],
        "processed_at": datetime.datetime.utcnow().isoformat() + "Z",
    }

def store_raw_data(data: dict, order_id: str) -> str:

    client = get_storage_client()
    bucket = client.bucket(RAW_BUCKET)

    # Organise by date for easy lifecycle management
    today = datetime.date.today().isoformat()
    blob_name = f"orders/{today}/{order_id}.json"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(json.dumps(data, indent=2), content_type="application/json")

    logger.info("Stored raw order %s → gs://%s/%s", order_id, RAW_BUCKET, blob_name)
    return blob_name


def store_processed_data(record: dict, order_id: str) -> str:

    client = get_storage_client()
    bucket = client.bucket(PROCESSED_BUCKET)

    today = datetime.date.today().isoformat()
    blob_name = f"anonymized/{today}/{order_id}.json"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(json.dumps(record, indent=2), content_type="application/json")

    logger.info("Stored processed order %s → gs://%s/%s", order_id, PROCESSED_BUCKET, blob_name)
    return blob_name


def write_to_bigquery(record: dict) -> None:

    client = get_bq_client()
    table_ref = f"{PROJECT_ID}.{BQ_DATASET}.{BQ_TABLE}"

    errors = client.insert_rows_json(table_ref, [record])
    if errors:
        logger.error("BigQuery insert failed for order %s: %s", record["order_id"], errors)
        raise RuntimeError(f"BigQuery insert failed: {errors}")

    logger.info("Wrote order %s to BigQuery table %s", record["order_id"], table_ref)


def verify_webhook_auth(request) -> bool:

    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return False

    token = auth_header[7:]
    expected = get_webhook_token()
    return hmac.compare_digest(token, expected)


@functions_framework.http
def process_order(request):
    
    # --- Method check ---
    if request.method == "OPTIONS":
        return ("", 204, {"Allow": "POST, OPTIONS"})

    if request.method != "POST":
        return (json.dumps({"error": "Method not allowed"}), 405, {"Content-Type": "application/json"})

    # --- Authentication ---
    if not verify_webhook_auth(request):
        logger.warning("Unauthorized request from %s", request.remote_addr)
        return (json.dumps({"error": "Unauthorized"}), 401, {"Content-Type": "application/json"})

    # --- Parse body ---
    try:
        data = request.get_json(force=True)
    except Exception:
        logger.warning("Failed to parse request body")
        return (json.dumps({"error": "Invalid JSON body"}), 400, {"Content-Type": "application/json"})

    if not data:
        return (json.dumps({"error": "Empty request body"}), 400, {"Content-Type": "application/json"})

    # --- Validate ---
    try:
        validate_order(data)
    except ValidationError as exc:
        logger.warning("Validation failed: %s", exc)
        return (json.dumps({"error": f"Validation error: {exc}"}), 422, {"Content-Type": "application/json"})

    # --- Process ---
    order_id = data["order_id"]
    request_id = str(uuid.uuid4())
    logger.info("Processing order %s (request_id=%s)", order_id, request_id)

    try:
        raw_path = store_raw_data(data, order_id)

        anonymized = anonymize_order(data)

        processed_path = store_processed_data(anonymized, order_id)

        write_to_bigquery(anonymized)

    except Exception as exc:
        logger.exception("Failed to process order %s: %s", order_id, exc)
        return (
            json.dumps({"error": "Internal processing error", "request_id": request_id}),
            500,
            {"Content-Type": "application/json"},
        )

    logger.info("Successfully processed order %s", order_id)
    return (
        json.dumps({
            "status": "success",
            "order_id": order_id,
            "request_id": request_id,
            "raw_path": raw_path,
            "processed_path": processed_path,
        }),
        200,
        {"Content-Type": "application/json"},
    )
