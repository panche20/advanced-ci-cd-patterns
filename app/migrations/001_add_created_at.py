"""
Migration 001: Add created_at field to all URLs

This demonstrates the EXPAND phase of expand-contract:
- Adds a new field to existing records
- Backward compatible: old code ignores the new field
- New code uses the new field when present

Run this BEFORE deploying code that requires created_at.
Deploy order:
  1. Run this migration (adds field to existing records)
  2. Deploy new code (uses field if present, graceful fallback)
  No downtime required.
"""

import redis
import os
import time
import sys

def run_migration():
    r = redis.Redis(
        host=os.getenv("REDIS_HOST", "localhost"),
        port=int(os.getenv("REDIS_PORT", 6379)),
        decode_responses=True,
    )

    MIGRATION_KEY = "migrations:applied"
    MIGRATION_NAME = "001_add_created_at"

    # Check if already applied (idempotent)
    if r.sismember(MIGRATION_KEY, MIGRATION_NAME):
        print(f"Migration {MIGRATION_NAME} already applied, skipping.")
        return True

    print(f"Running migration: {MIGRATION_NAME}")

    # Scan all URL records and add created_at if missing
    cursor = 0
    migrated = 0
    skipped = 0

    while True:
        cursor, keys = r.scan(
            cursor,
            match="url:*",
            count=100
        )

        for key in keys:
            # Only add if field is missing
            if not r.hexists(key, "created_at"):
                # Use a past timestamp to indicate legacy record
                r.hset(key, "created_at", "2024-01-01T00:00:00Z")
                migrated += 1
            else:
                skipped += 1

        if cursor == 0:
            break

    # Record that migration was applied
    r.sadd(MIGRATION_KEY, MIGRATION_NAME)

    print(f"Migration complete:")
    print(f"  Migrated: {migrated} records")
    print(f"  Skipped:  {skipped} records (already had field)")
    return True

if __name__ == "__main__":
    success = run_migration()
    sys.exit(0 if success else 1)
