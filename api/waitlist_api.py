#!/usr/bin/env python3
"""
TerraPerf Waitlist API
Simple backend for collecting email signups.
- Local: Stores in JSON file
- Production: Uses DynamoDB
"""

import json
import os
import re
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, field_validator

# Configuration
IS_LOCAL = os.getenv("AWS_LAMBDA_FUNCTION_NAME") is None
DATA_DIR = Path(__file__).parent / "data"
WAITLIST_FILE = DATA_DIR / "waitlist.json"

app = FastAPI(title="TerraPerf Waitlist API", version="1.0.0")

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:8080",
        "http://localhost:8083",
        "http://127.0.0.1:8080",
        "http://127.0.0.1:8083",
        "https://terraperf.com",
        "https://www.terraperf.com",
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


class WaitlistEntry(BaseModel):
    email: EmailStr
    consent: bool
    consent_timestamp: str
    source: Optional[str] = "landing_page"

    @field_validator("consent")
    @classmethod
    def consent_must_be_true(cls, v):
        if not v:
            raise ValueError("Consent must be given to join the waitlist")
        return v


class WaitlistResponse(BaseModel):
    success: bool
    message: str
    id: Optional[str] = None


def load_waitlist() -> list:
    """Load waitlist from JSON file (local mode only)."""
    if not IS_LOCAL:
        return []

    if not WAITLIST_FILE.exists():
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        WAITLIST_FILE.write_text("[]")
        return []

    try:
        return json.loads(WAITLIST_FILE.read_text())
    except json.JSONDecodeError:
        return []


def save_waitlist(entries: list) -> None:
    """Save waitlist to JSON file (local mode only)."""
    if not IS_LOCAL:
        return

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    WAITLIST_FILE.write_text(json.dumps(entries, indent=2))


def email_exists(email: str, entries: list) -> bool:
    """Check if email already exists in waitlist."""
    return any(e.get("email", "").lower() == email.lower() for e in entries)


def get_client_ip(request: Request) -> str:
    """Get client IP address from request."""
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


@app.get("/")
async def root():
    """Health check endpoint."""
    return {"status": "ok", "service": "terraperf-waitlist"}


@app.get("/waitlist")
async def get_waitlist_stats():
    """Get waitlist statistics (for admin use)."""
    entries = load_waitlist()
    return {
        "total_subscribers": len(entries),
        "is_local": IS_LOCAL
    }


@app.post("/waitlist", response_model=WaitlistResponse)
async def subscribe(entry: WaitlistEntry, request: Request):
    """Add email to the waitlist."""

    # Normalize email
    email = entry.email.lower().strip()

    if IS_LOCAL:
        # Local mode: Store in JSON file
        entries = load_waitlist()

        if email_exists(email, entries):
            raise HTTPException(
                status_code=400,
                detail="This email is already on the waitlist."
            )

        new_entry = {
            "id": str(uuid.uuid4()),
            "email": email,
            "consent": entry.consent,
            "consent_timestamp": entry.consent_timestamp,
            "source": entry.source,
            "ip_address": get_client_ip(request),
            "created_at": datetime.utcnow().isoformat() + "Z"
        }

        entries.append(new_entry)
        save_waitlist(entries)

        print(f"[Waitlist] New signup: {email}")

        return WaitlistResponse(
            success=True,
            message="You've been added to our waiting list!",
            id=new_entry["id"]
        )

    else:
        # Production mode: Use DynamoDB
        import boto3
        from botocore.exceptions import ClientError

        dynamodb = boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION", "eu-west-1"))
        table = dynamodb.Table(os.getenv("WAITLIST_TABLE", "terraperf-waitlist-prod"))

        # Check if email exists
        try:
            response = table.get_item(Key={"email": email})
            if "Item" in response:
                raise HTTPException(
                    status_code=400,
                    detail="This email is already on the waitlist."
                )
        except ClientError as e:
            if e.response["Error"]["Code"] != "ResourceNotFoundException":
                raise HTTPException(status_code=500, detail="Database error")

        # Add new entry
        entry_id = str(uuid.uuid4())
        try:
            table.put_item(Item={
                "id": entry_id,
                "email": email,
                "consent": entry.consent,
                "consent_timestamp": entry.consent_timestamp,
                "source": entry.source,
                "ip_address": get_client_ip(request),
                "created_at": datetime.utcnow().isoformat() + "Z"
            })
        except ClientError as e:
            raise HTTPException(status_code=500, detail="Failed to save to database")

        return WaitlistResponse(
            success=True,
            message="You've been added to our waiting list!",
            id=entry_id
        )


@app.delete("/waitlist/{email}")
async def unsubscribe(email: str):
    """Remove email from the waitlist (for GDPR compliance)."""
    email = email.lower().strip()

    if IS_LOCAL:
        entries = load_waitlist()
        original_count = len(entries)
        entries = [e for e in entries if e.get("email", "").lower() != email]

        if len(entries) == original_count:
            raise HTTPException(status_code=404, detail="Email not found")

        save_waitlist(entries)
        return {"success": True, "message": "Email removed from waitlist"}

    else:
        import boto3
        from botocore.exceptions import ClientError

        dynamodb = boto3.resource("dynamodb", region_name=os.getenv("AWS_REGION", "eu-west-1"))
        table = dynamodb.Table(os.getenv("WAITLIST_TABLE", "terraperf-waitlist-prod"))

        try:
            table.delete_item(Key={"email": email})
            return {"success": True, "message": "Email removed from waitlist"}
        except ClientError:
            raise HTTPException(status_code=500, detail="Failed to remove from database")


if __name__ == "__main__":
    import uvicorn
    print("Starting TerraPerf Waitlist API on http://localhost:8001")
    uvicorn.run(app, host="0.0.0.0", port=8001)
