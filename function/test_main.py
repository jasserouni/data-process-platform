
import hashlib
import hmac as hmac_lib
import json
import os
import unittest
from unittest.mock import MagicMock, patch

# Set env vars before importing main
os.environ.update({
    "PROJECT_ID": "test-project",
    "RAW_BUCKET": "test-raw-bucket",
    "PROCESSED_BUCKET": "test-processed-bucket",
    "BQ_DATASET": "test_dataset",
    "BQ_TABLE": "test_table",
    "HMAC_SECRET_ID": "test-hmac-key",
    "WEBHOOK_TOKEN_SECRET": "test-webhook-token",
    "LOG_LEVEL": "WARNING",
})

import main  # noqa: E402

SAMPLE_ORDER = {
    "order_id": "ORD-2024-001",
    "timestamp": "2024-12-04T10:30:00Z",
    "customer": {
        "email": "customer@example.com",
        "name": "Jane Doe",
        "address": "123 Main St, Berlin, Germany",
    },
    "items": [{"sku": "PROD-001", "quantity": 2, "price": 29.99}],
    "total": 59.98,
    "payment_last4": "4242",
    "currency": "EUR",
}

TEST_HMAC_KEY = b"test-secret-hmac-key-for-unit-tests"
TEST_WEBHOOK_TOKEN = "test-webhook-token-value"


def _make_request(method="POST", json_body=None, auth_token=None):
    """Build a mock Flask request object."""
    req = MagicMock()
    req.method = method
    req.remote_addr = "127.0.0.1"
    req.get_json.return_value = json_body
    if auth_token:
        req.headers = {"Authorization": f"Bearer {auth_token}"}
    else:
        req.headers = {}
    return req


def _expected_hash(value: str) -> str:
    return hmac_lib.new(TEST_HMAC_KEY, value.lower().strip().encode("utf-8"), hashlib.sha256).hexdigest()



# Test cases

class TestValidation(unittest.TestCase):
    """Tests for validate_order()."""

    def test_valid_order_passes(self):
        main.validate_order(SAMPLE_ORDER)  # should not raise

    def test_missing_top_level_field(self):
        bad = {k: v for k, v in SAMPLE_ORDER.items() if k != "order_id"}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)

    def test_invalid_order_id_format(self):
        bad = {**SAMPLE_ORDER, "order_id": "INVALID-123"}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)

    def test_invalid_timestamp(self):
        bad = {**SAMPLE_ORDER, "timestamp": "not-a-date"}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)

    def test_missing_customer_field(self):
        bad = {**SAMPLE_ORDER, "customer": {"email": "a@b.com", "name": "X"}}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)

    def test_invalid_email(self):
        bad = {**SAMPLE_ORDER, "customer": {**SAMPLE_ORDER["customer"], "email": "not-an-email"}}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)

    def test_empty_items(self):
        bad = {**SAMPLE_ORDER, "items": []}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)

    def test_invalid_item_quantity(self):
        bad = {**SAMPLE_ORDER, "items": [{"sku": "X", "quantity": -1, "price": 10}]}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)

    def test_invalid_item_price(self):
        bad = {**SAMPLE_ORDER, "items": [{"sku": "X", "quantity": 1, "price": -5}]}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)

    def test_negative_total(self):
        bad = {**SAMPLE_ORDER, "total": -10}
        with self.assertRaises(main.ValidationError):
            main.validate_order(bad)


class TestPseudonymization(unittest.TestCase):
    """Tests for PII hashing logic."""

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_deterministic_hash(self, _):
        h1 = main.pseudonymize("customer@example.com")
        h2 = main.pseudonymize("customer@example.com")
        self.assertEqual(h1, h2)

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_case_insensitive(self, _):
        h1 = main.pseudonymize("Jane@Example.COM")
        h2 = main.pseudonymize("jane@example.com")
        self.assertEqual(h1, h2)

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_different_inputs_different_hashes(self, _):
        h1 = main.pseudonymize("user1@example.com")
        h2 = main.pseudonymize("user2@example.com")
        self.assertNotEqual(h1, h2)

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_hash_matches_expected(self, _):
        result = main.pseudonymize("customer@example.com")
        self.assertEqual(result, _expected_hash("customer@example.com"))

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_whitespace_trimmed(self, _):
        h1 = main.pseudonymize("  jane@example.com  ")
        h2 = main.pseudonymize("jane@example.com")
        self.assertEqual(h1, h2)


class TestLocationExtraction(unittest.TestCase):
    """Tests for address parsing."""

    def test_three_part_address(self):
        city, country = main.extract_location("123 Main St, Berlin, Germany")
        self.assertEqual(city, "Berlin")
        self.assertEqual(country, "Germany")

    def test_two_part_address(self):
        city, country = main.extract_location("Berlin, Germany")
        self.assertEqual(city, "Berlin")
        self.assertEqual(country, "Germany")

    def test_single_part_address(self):
        city, country = main.extract_location("Germany")
        self.assertEqual(city, "")
        self.assertEqual(country, "")

    def test_four_part_address(self):
        city, country = main.extract_location("Apt 5, 10 Main St, Munich, Germany")
        self.assertEqual(city, "Munich")
        self.assertEqual(country, "Germany")


class TestAnonymizeOrder(unittest.TestCase):
    """Tests for the full anonymization transformation."""

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_pii_fields_are_hashed(self, _):
        result = main.anonymize_order(SAMPLE_ORDER)

        self.assertEqual(result["customer_id_hash"], _expected_hash("customer@example.com"))
        self.assertEqual(result["customer_name_hash"], _expected_hash("jane doe"))

        # Original PII must NOT be in the output
        result_str = json.dumps(result)
        self.assertNotIn("customer@example.com", result_str)
        self.assertNotIn("Jane Doe", result_str)
        self.assertNotIn("123 Main St", result_str)

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_non_pii_preserved(self, _):
        result = main.anonymize_order(SAMPLE_ORDER)
        self.assertEqual(result["order_id"], "ORD-2024-001")
        self.assertEqual(result["total"], 59.98)
        self.assertEqual(result["currency"], "EUR")
        self.assertEqual(len(result["items"]), 1)

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_payment_last4_excluded(self, _):
        """Ensure payment_last4 is not in the anonymized output."""
        result = main.anonymize_order(SAMPLE_ORDER)
        self.assertNotIn("payment_last4", result)
        self.assertNotIn("4242", json.dumps(result))

    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    def test_location_extracted(self, _):
        result = main.anonymize_order(SAMPLE_ORDER)
        self.assertEqual(result["customer_city"], "Berlin")
        self.assertEqual(result["customer_country"], "Germany")


class TestHTTPHandling(unittest.TestCase):
    """Tests for the Cloud Function HTTP entry point."""

    @patch.object(main, "get_webhook_token", return_value=TEST_WEBHOOK_TOKEN)
    def test_get_method_rejected(self, _):
        req = _make_request(method="GET", auth_token=TEST_WEBHOOK_TOKEN)
        body, status, _ = main.process_order(req)
        self.assertEqual(status, 405)

    @patch.object(main, "get_webhook_token", return_value=TEST_WEBHOOK_TOKEN)
    def test_missing_auth_returns_401(self, _):
        req = _make_request(json_body=SAMPLE_ORDER)
        body, status, _ = main.process_order(req)
        self.assertEqual(status, 401)

    @patch.object(main, "get_webhook_token", return_value=TEST_WEBHOOK_TOKEN)
    def test_wrong_token_returns_401(self, _):
        req = _make_request(json_body=SAMPLE_ORDER, auth_token="wrong-token")
        body, status, _ = main.process_order(req)
        self.assertEqual(status, 401)

    @patch.object(main, "get_webhook_token", return_value=TEST_WEBHOOK_TOKEN)
    def test_invalid_json_returns_400(self, _):
        req = _make_request(auth_token=TEST_WEBHOOK_TOKEN)
        req.get_json.side_effect = ValueError("bad json")
        body, status, _ = main.process_order(req)
        self.assertEqual(status, 400)

    @patch.object(main, "get_webhook_token", return_value=TEST_WEBHOOK_TOKEN)
    def test_validation_error_returns_422(self, _):
        bad_order = {"order_id": "BAD"}  # incomplete
        req = _make_request(json_body=bad_order, auth_token=TEST_WEBHOOK_TOKEN)
        body, status, _ = main.process_order(req)
        self.assertEqual(status, 422)

    @patch.object(main, "get_webhook_token", return_value=TEST_WEBHOOK_TOKEN)
    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    @patch.object(main, "store_raw_data", return_value="raw/path.json")
    @patch.object(main, "store_processed_data", return_value="processed/path.json")
    @patch.object(main, "write_to_bigquery")
    def test_successful_processing(self, mock_bq, mock_proc, mock_raw, _, __):
        req = _make_request(json_body=SAMPLE_ORDER, auth_token=TEST_WEBHOOK_TOKEN)
        body, status, _ = main.process_order(req)

        self.assertEqual(status, 200)
        response = json.loads(body)
        self.assertEqual(response["status"], "success")
        self.assertEqual(response["order_id"], "ORD-2024-001")

        mock_raw.assert_called_once()
        mock_proc.assert_called_once()
        mock_bq.assert_called_once()

    @patch.object(main, "get_webhook_token", return_value=TEST_WEBHOOK_TOKEN)
    @patch.object(main, "get_hmac_key", return_value=TEST_HMAC_KEY)
    @patch.object(main, "store_raw_data", side_effect=RuntimeError("GCS down"))
    def test_processing_error_returns_500(self, _, __, ___):
        req = _make_request(json_body=SAMPLE_ORDER, auth_token=TEST_WEBHOOK_TOKEN)
        body, status, _ = main.process_order(req)
        self.assertEqual(status, 500)

    def test_options_returns_204(self):
        req = _make_request(method="OPTIONS")
        body, status, headers = main.process_order(req)
        self.assertEqual(status, 204)


if __name__ == "__main__":
    unittest.main()
