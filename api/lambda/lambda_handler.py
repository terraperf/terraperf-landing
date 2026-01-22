"""
TerraPerf Waitlist Lambda Handler
Handles email signup for the waiting list.
"""

import json
import os
import re
import uuid
from datetime import datetime

import boto3
from botocore.exceptions import ClientError

# Configuration
WAITLIST_TABLE = os.environ.get("WAITLIST_TABLE", "terraperf-landing-waitlist-prod")
CORS_ORIGINS = os.environ.get("CORS_ORIGINS", "https://terraperf.com,https://www.terraperf.com").split(",")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(WAITLIST_TABLE)

# Email validation regex
EMAIL_REGEX = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")


def get_cors_headers(origin: str = None) -> dict:
    """Get CORS headers for response."""
    allowed_origin = CORS_ORIGINS[0]  # Default
    if origin and origin in CORS_ORIGINS:
        allowed_origin = origin

    return {
        "Access-Control-Allow-Origin": allowed_origin,
        "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
        "Content-Type": "application/json"
    }


def response(status_code: int, body: dict, origin: str = None) -> dict:
    """Create API Gateway response."""
    return {
        "statusCode": status_code,
        "headers": get_cors_headers(origin),
        "body": json.dumps(body)
    }


def get_client_ip(event: dict) -> str:
    """Extract client IP from event."""
    request_context = event.get("requestContext", {})
    http = request_context.get("http", {})
    return http.get("sourceIp", "unknown")


def validate_email(email: str) -> bool:
    """Validate email format."""
    if not email or len(email) > 254:
        return False
    return EMAIL_REGEX.match(email) is not None


def handle_get_stats(event: dict) -> dict:
    """GET /waitlist - Return waitlist statistics."""
    origin = event.get("headers", {}).get("origin")

    try:
        result = table.scan(Select="COUNT")
        return response(200, {
            "total_subscribers": result.get("Count", 0),
            "status": "ok"
        }, origin)
    except ClientError as e:
        print(f"DynamoDB error: {e}")
        return response(500, {"detail": "Database error"}, origin)


def handle_subscribe(event: dict) -> dict:
    """POST /waitlist - Add email to waitlist."""
    origin = event.get("headers", {}).get("origin")

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return response(400, {"detail": "Invalid JSON body"}, origin)

    email = body.get("email", "").lower().strip()
    consent = body.get("consent", False)
    consent_timestamp = body.get("consent_timestamp", datetime.utcnow().isoformat() + "Z")
    source = body.get("source", "landing_page")

    # Validate email
    if not validate_email(email):
        return response(400, {"detail": "Invalid email address"}, origin)

    # Validate consent
    if not consent:
        return response(400, {"detail": "Consent must be given to join the waitlist"}, origin)

    # Check if email already exists
    try:
        existing = table.get_item(Key={"email": email})
        if "Item" in existing:
            return response(400, {"detail": "This email is already on the waitlist."}, origin)
    except ClientError as e:
        print(f"DynamoDB get error: {e}")
        return response(500, {"detail": "Database error"}, origin)

    # Add new entry
    entry_id = str(uuid.uuid4())
    client_ip = get_client_ip(event)

    try:
        table.put_item(Item={
            "email": email,
            "id": entry_id,
            "consent": consent,
            "consent_timestamp": consent_timestamp,
            "source": source,
            "ip_address": client_ip,
            "created_at": datetime.utcnow().isoformat() + "Z"
        })
    except ClientError as e:
        print(f"DynamoDB put error: {e}")
        return response(500, {"detail": "Failed to save to database"}, origin)

    print(f"[Waitlist] New signup: {email}")

    return response(200, {
        "success": True,
        "message": "You've been added to our waiting list!",
        "id": entry_id
    }, origin)


def handle_unsubscribe(event: dict, email: str) -> dict:
    """DELETE /waitlist/{email} - Remove email from waitlist."""
    origin = event.get("headers", {}).get("origin")
    email = email.lower().strip()

    if not validate_email(email):
        return response(400, {"detail": "Invalid email address"}, origin)

    try:
        # Check if exists first
        existing = table.get_item(Key={"email": email})
        if "Item" not in existing:
            return response(404, {"detail": "Email not found"}, origin)

        table.delete_item(Key={"email": email})
        print(f"[Waitlist] Unsubscribed: {email}")

        return response(200, {
            "success": True,
            "message": "Email removed from waitlist"
        }, origin)
    except ClientError as e:
        print(f"DynamoDB delete error: {e}")
        return response(500, {"detail": "Failed to remove from database"}, origin)


def handle_health(event: dict) -> dict:
    """GET / - Health check."""
    origin = event.get("headers", {}).get("origin")
    return response(200, {
        "status": "ok",
        "service": "terraperf-waitlist"
    }, origin)


def handler(event, context):
    """Lambda handler for API Gateway HTTP API."""
    print(f"Event: {json.dumps(event)}")

    request_context = event.get("requestContext", {})
    http = request_context.get("http", {})
    method = http.get("method", "GET")
    path = http.get("path", "/")

    # Route requests
    if path == "/" and method == "GET":
        return handle_health(event)

    elif path == "/waitlist" and method == "GET":
        return handle_get_stats(event)

    elif path == "/waitlist" and method == "POST":
        return handle_subscribe(event)

    elif path.startswith("/waitlist/") and method == "DELETE":
        email = path.replace("/waitlist/", "")
        return handle_unsubscribe(event, email)

    else:
        origin = event.get("headers", {}).get("origin")
        return response(404, {"detail": "Not found"}, origin)
