"""
URL Shortener — Advanced CI/CD Demo

This application demonstrates:
1. Feature flags backed by Redis
2. Multiple deployment versions (blue/green)
3. Health and readiness endpoints for deployment strategies
4. Metrics for automated canary analysis
5. Version endpoint for verifying which version is deployed
"""

import os
import time
import hashlib
import socket
import json
import logging
from typing import Optional

from fastapi import FastAPI, HTTPException, Request, Header
from fastapi.responses import RedirectResponse, JSONResponse
from pydantic import BaseModel
import redis

# ─────────────────────────────────────────────────────────────
# STRUCTURED LOGGING
# ─────────────────────────────────────────────────────────────
class JSONFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps({
            "timestamp": self.formatTime(record),
            "level":     record.levelname,
            "message":   record.getMessage(),
            "service":   "url-shortener",
            "version":   os.getenv("APP_VERSION", "1.0.0"),
            "pod":       os.getenv("POD_NAME", socket.gethostname()),
            "color":     os.getenv("DEPLOYMENT_COLOR", "blue"),
        })

handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger = logging.getLogger("app")
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# ─────────────────────────────────────────────────────────────
# APP CONFIGURATION
# ─────────────────────────────────────────────────────────────
APP_VERSION         = os.getenv("APP_VERSION", "1.0.0")
DEPLOYMENT_COLOR    = os.getenv("DEPLOYMENT_COLOR", "blue")
POD_NAME            = os.getenv("POD_NAME", socket.gethostname())

# ─────────────────────────────────────────────────────────────
# REDIS CONNECTION
# ─────────────────────────────────────────────────────────────
def get_redis():
    return redis.Redis(
        host=os.getenv("REDIS_HOST", "redis"),
        port=int(os.getenv("REDIS_PORT", 6379)),
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5,
    )

r = get_redis()

# ─────────────────────────────────────────────────────────────
# FEATURE FLAGS
# ─────────────────────────────────────────────────────────────
# Feature flags are stored in Redis so they can be changed
# WITHOUT redeploying the application.
# This is the key insight: deploy code, but control features.

class FeatureFlags:
    """
    Feature flag system backed by Redis.

    Supports three types of flag values:
    1. Boolean: {"enabled": true/false}
    2. Percentage rollout: {"percentage": 25}  (25% of users get it)
    3. User allowlist: {"users": ["user1", "user2"]}

    Example usage:
    flags = FeatureFlags(redis_client)
    if flags.is_enabled("new_analytics", user_id="u_123"):
        # show new analytics
    """

    # Default values when Redis is unavailable
    # Always safe defaults (features OFF)
    DEFAULTS = {
        "analytics_enabled":      False,
        "custom_slugs_enabled":   False,
        "rate_limiting_enabled":  True,
        "new_ui_enabled":         False,
        "bulk_shorten_enabled":   False,
    }

    def __init__(self, redis_client):
        self.redis = redis_client

    def is_enabled(
        self,
        flag_name: str,
        user_id: Optional[str] = None
    ) -> bool:
        """
        Check if a feature flag is enabled.
        Supports per-user rollout via percentage or allowlist.
        """
        try:
            raw = self.redis.get(f"feature_flag:{flag_name}")

            # Flag not set in Redis → use default
            if raw is None:
                return self.DEFAULTS.get(flag_name, False)

            value = json.loads(raw)

            # Simple boolean flag
            if isinstance(value, bool):
                return value

            # Percentage rollout
            # Deterministic: same user always gets same result
            if "percentage" in value and user_id:
                # Hash user_id to a number 0-99
                # Using MD5 so it's consistent across restarts
                bucket = int(
                    hashlib.md5(
                        f"{flag_name}:{user_id}".encode()
                    ).hexdigest(), 16
                ) % 100
                return bucket < value["percentage"]

            # User allowlist
            if "users" in value and user_id:
                return user_id in value["users"]

            return value.get("enabled", False)

        except Exception as e:
            logger.warning(f"Feature flag lookup failed: {e}")
            return self.DEFAULTS.get(flag_name, False)

    def set_flag(self, flag_name: str, value) -> bool:
        """Set a feature flag value in Redis"""
        try:
            self.redis.set(
                f"feature_flag:{flag_name}",
                json.dumps(value)
            )
            logger.info(f"Feature flag set: {flag_name} = {value}")
            return True
        except Exception as e:
            logger.error(f"Failed to set flag {flag_name}: {e}")
            return False

    def get_all(self) -> dict:
        """Get all feature flags and their current values"""
        flags = {}
        for name in self.DEFAULTS:
            flags[name] = self.is_enabled(name)
        return flags


flags = FeatureFlags(r)

# ─────────────────────────────────────────────────────────────
# FASTAPI APPLICATION
# ─────────────────────────────────────────────────────────────
app = FastAPI(
    title="URL Shortener",
    description="Advanced CI/CD Demo",
    version=APP_VERSION,
)

# ─────────────────────────────────────────────────────────────
# MODELS
# ─────────────────────────────────────────────────────────────
class URLRequest(BaseModel):
    url: str
    custom_slug: Optional[str] = None  # feature-flagged feature

class FlagUpdateRequest(BaseModel):
    value: object

# ─────────────────────────────────────────────────────────────
# HEALTH ENDPOINTS
# ─────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    """
    Liveness probe endpoint.
    Returns 200 if the app is alive.
    Returns 503 if a critical dependency (Redis) is down.

    Used by:
    - Kubernetes liveness probe (restart if fails)
    - Load balancer health checks
    - Deployment smoke tests
    - Blue-green switch validation
    """
    try:
        r.ping()
        return {
            "status":  "healthy",
            "version": APP_VERSION,
            "color":   DEPLOYMENT_COLOR,
            "pod":     POD_NAME,
            "redis":   "connected",
        }
    except redis.RedisError as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(
            status_code=503,
            detail="Redis unavailable"
        )

@app.get("/ready")
def ready():
    """
    Readiness probe endpoint.
    Returns 200 only when the app is ready to receive traffic.

    Difference from /health:
    /health = is the process alive?
    /ready  = is the process ready to serve requests?

    Use case: During startup, app may be alive but still
    loading caches or warming up connections.
    Kubernetes won't send traffic until /ready returns 200.
    """
    try:
        # Verify Redis is reachable
        r.ping()
        # Verify we can write (not just ping)
        r.set("readiness_check", "ok", ex=10)
        return {"status": "ready", "version": APP_VERSION}
    except redis.RedisError:
        raise HTTPException(
            status_code=503,
            detail="Not ready"
        )

@app.get("/version")
def version():
    """
    Version information endpoint.
    Critical for CI/CD verification:
    - After deploy: confirm correct version is serving
    - Blue-green: confirm switch worked
    - Canary: verify % of requests hit new version

    Blue-green switch verification:
    Before switch: /version returns {"color": "blue", "version": "1.0.0"}
    After switch:  /version returns {"color": "green", "version": "1.1.0"}
    """
    return {
        "version":        APP_VERSION,
        "color":          DEPLOYMENT_COLOR,
        "pod":            POD_NAME,
        "build_time":     os.getenv("BUILD_TIME", "unknown"),
        "git_commit":     os.getenv("GIT_COMMIT", "unknown"),
    }

# ─────────────────────────────────────────────────────────────
# FEATURE FLAG ENDPOINTS
# ─────────────────────────────────────────────────────────────
@app.get("/flags")
def get_flags():
    """
    Get all feature flag values.
    Used by:
    - Operations team to see current flag state
    - CI/CD pipelines to verify flag configuration
    - Monitoring to track flag changes over time
    """
    return {
        "flags":   flags.get_all(),
        "version": APP_VERSION,
    }

@app.post("/flags/{flag_name}")
def set_flag(flag_name: str, req: FlagUpdateRequest):
    """
    Set a feature flag value.
    This is the control plane for feature releases.

    Examples:
    Enable for all:   {"value": true}
    Disable for all:  {"value": false}
    10% rollout:      {"value": {"percentage": 10}}
    Specific users:   {"value": {"users": ["user1", "user2"]}}
    """
    success = flags.set_flag(flag_name, req.value)
    if not success:
        raise HTTPException(
            status_code=500,
            detail="Failed to update flag"
        )
    return {
        "flag":    flag_name,
        "value":   req.value,
        "status":  "updated",
    }

# ─────────────────────────────────────────────────────────────
# BUSINESS ENDPOINTS
# ─────────────────────────────────────────────────────────────
@app.post("/shorten")
def shorten(req: URLRequest, x_user_id: Optional[str] = Header(None)):
    """
    Shorten a URL.
    Demonstrates feature flags in business logic.
    """
    user_id = x_user_id or "anonymous"

    # Feature flag: custom slugs
    # Only available to users in the rollout
    if req.custom_slug:
        if not flags.is_enabled("custom_slugs_enabled", user_id):
            raise HTTPException(
                status_code=403,
                detail="Custom slugs not available for your account"
            )
        code = req.custom_slug
    else:
        code = hashlib.md5(
            f"{req.url}{time.time()}".encode()
        ).hexdigest()[:6]

    try:
        mapping = {
            "url":        req.url,
            "clicks":     0,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "version":    APP_VERSION,
        }

        # Feature flag: analytics
        if flags.is_enabled("analytics_enabled", user_id):
            mapping["analytics"] = json.dumps({
                "user_id":  user_id,
                "referrer": "api",
            })

        r.hset(f"url:{code}", mapping=mapping)

        logger.info(json.dumps({
            "event":   "url_shortened",
            "code":    code,
            "user_id": user_id,
        }))

        return {
            "short_code":  code,
            "short_url":   f"/r/{code}",
            "version":     APP_VERSION,
        }
    except redis.RedisError as e:
        raise HTTPException(status_code=503, detail="Storage error")

@app.get("/r/{code}")
def redirect(code: str):
    """Follow a short URL"""
    try:
        data = r.hgetall(f"url:{code}")
        if not data:
            raise HTTPException(status_code=404, detail="Not found")
        r.hincrby(f"url:{code}", "clicks", 1)
        return RedirectResponse(url=data["url"])
    except redis.RedisError:
        raise HTTPException(status_code=503, detail="Storage error")

@app.get("/stats/{code}")
def stats(code: str):
    """Get click statistics"""
    try:
        data = r.hgetall(f"url:{code}")
        if not data:
            raise HTTPException(status_code=404, detail="Not found")
        return {
            "short_code": code,
            "url":        data["url"],
            "clicks":     int(data.get("clicks", 0)),
            "created_at": data.get("created_at", "unknown"),
        }
    except redis.RedisError:
        raise HTTPException(status_code=503, detail="Storage error")

@app.get("/")
def root():
    return {
        "service":  "URL Shortener",
        "version":  APP_VERSION,
        "color":    DEPLOYMENT_COLOR,
        "docs":     "/docs",
        "flags":    "/flags",
        "health":   "/health",
        "version_info": "/version",
    }
