#!/bin/bash
# Run database migrations as a Kubernetes Job
# This runs BEFORE the new application version starts
#
# Why a Job instead of an init container?
# Jobs are visible in kubectl get jobs
# Jobs keep logs after completion
# Jobs can be triggered independently
# Jobs retry on failure
#
# Alternative: init container in the Deployment
# Init containers run before the main container starts
# Good for simple, fast migrations

NAMESPACE="url-shortener"
REDIS_HOST="redis.url-shortener.svc.cluster.local"

echo "Running database migrations..."

kubectl run migration-job \
  --image=python:3.11-slim \
  --restart=Never \
  -n "$NAMESPACE" \
  --env="REDIS_HOST=$REDIS_HOST" \
  --env="REDIS_PORT=6379" \
  --command -- \
  sh -c "
    pip install redis --quiet
    python3 -c \"
import redis, os, sys
r = redis.Redis(
    host=os.getenv('REDIS_HOST', 'localhost'),
    decode_responses=True
)
MIGRATION = '001_add_created_at'
if r.sismember('migrations:applied', MIGRATION):
    print('Already applied')
    sys.exit(0)
cursor = 0
count = 0
while True:
    cursor, keys = r.scan(cursor, match='url:*', count=100)
    for key in keys:
        if not r.hexists(key, 'created_at'):
            r.hset(key, 'created_at', '2024-01-01T00:00:00Z')
            count += 1
    if cursor == 0:
        break
r.sadd('migrations:applied', MIGRATION)
print(f'Migrated {count} records')
\"
  " 2>/dev/null

# Wait for migration to complete
kubectl wait \
  --for=condition=Complete \
  pod/migration-job \
  -n "$NAMESPACE" \
  --timeout=120s 2>/dev/null || \
kubectl logs migration-job -n "$NAMESPACE" 2>/dev/null

# Clean up
kubectl delete pod migration-job \
  -n "$NAMESPACE" \
  --ignore-not-found

echo "✅ Migrations complete"
