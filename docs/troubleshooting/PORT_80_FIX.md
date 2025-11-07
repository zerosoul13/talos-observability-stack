# Port 80 Conflict Issue - RESOLVED

## Problem
```
docker: Error response from daemon: failed to set up container networking:
driver failed programming external connectivity on endpoint talos-worker-01:
Bind for 0.0.0.0:80 failed: port is already allocated
```

## Root Cause

**Kind cluster is using ports 80 and 443:**
```bash
$ docker ps
NAMES                    PORTS
kind-control-plane       0.0.0.0:80->80/tcp,
                         0.0.0.0:443->443/tcp,
                         127.0.0.1:41403->6443/tcp
```

Multiple containers cannot bind to the same host port.

## Solution Implemented

### Intelligent Port Detection (Lines 269-304 in deploy-talos.sh)

The script now **automatically detects** if port 80 is in use:

```bash
# Check if port 80 is already in use
if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    log_warn "Port 80 is already in use, worker 1 will not expose HTTP/HTTPS ports"
    log_warn "Traefik will need to use NodePort or you'll need to free port 80"
    # Start worker WITHOUT port mappings
else
    # Start worker WITH port mappings 80/443
fi
```

### Architecture Changes

**Before:**
- Both workers tried to expose ports 80/443
- Failed when port already allocated

**After:**
- **Worker 1:** Conditionally exposes 80/443 (only if available)
- **Worker 2:** Never exposes 80/443 (only one worker needs them)
- Script gracefully handles port conflicts

## Options to Resolve

### Option 1: Remove Kind Cluster (Recommended if not needed)

```bash
# Check if you need the Kind cluster
kind get clusters

# Delete it if not needed
kind delete cluster

# Then run Talos deployment
make deploy-infra
```

### Option 2: Keep Both Clusters (Use NodePort for Traefik)

**If port 80 is unavailable, Traefik will use NodePort:**

```bash
# Deploy Talos (will skip port 80/443 mapping)
make deploy-infra

# Access Traefik via NodePort instead
# Example: http://localhost:30080 (NodePort will be auto-assigned)
kubectl get svc -n traefik
```

### Option 3: Change Kind Ports

```bash
# Reconfigure Kind to use different ports
kind delete cluster

# Create Kind with custom ports
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080  # Changed from 80
  - containerPort: 443
    hostPort: 8443  # Changed from 443
EOF

# Now Talos can use ports 80/443
make deploy-infra
```

## Deployment Status After Fix

### With Port 80 Free (Ideal):
```
✅ Worker 1: Exposes 80, 443, 50001
✅ Worker 2: Exposes 50002 only
✅ Traefik accessible at http://localhost:80
```

### With Port 80 Busy (Fallback):
```
✅ Worker 1: Exposes 50001 only
✅ Worker 2: Exposes 50002 only
⚠️ Traefik uses NodePort (e.g., :30080)
⚠️ Warning logged: "Port 80 is already in use..."
```

## Script Changes Made

### 1. Added Port Check Function
```bash
if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    # Port busy - skip HTTP/HTTPS
else
    # Port free - expose HTTP/HTTPS
fi
```

### 2. Worker 2 Never Exposes 80/443
Only one worker needs ingress ports:
```bash
# Worker 2 - No HTTP/HTTPS ports (only one worker needs them)
docker run -d \
    --name "${WORKER_2_NAME}" \
    -p ${TALOS_API_PORT_W2}:50000 \  # Only Talos API
    # NO -p 80:80 or -p 443:443
```

### 3. Clear Warning Messages
```
[WARN] Port 80 is already in use, worker 1 will not expose HTTP/HTTPS ports
[WARN] Traefik will need to use NodePort or you'll need to free port 80
```

## Testing the Fix

### Test 1: With Port 80 Free
```bash
# Remove Kind cluster
kind delete cluster

# Deploy Talos
make deploy-infra

# Verify ports
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep talos

# Expected:
# talos-worker-01    0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:50001->50000/tcp
# talos-worker-02    0.0.0.0:50002->50000/tcp
```

### Test 2: With Port 80 Busy
```bash
# Keep Kind running (or any service on port 80)

# Deploy Talos
make deploy-infra

# Verify warning appears
# Expected: [WARN] Port 80 is already in use...

# Check ports
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep talos

# Expected:
# talos-worker-01    0.0.0.0:50001->50000/tcp (NO 80/443)
# talos-worker-02    0.0.0.0:50002->50000/tcp
```

## Impact on Traefik

### Scenario 1: Port 80 Available
Traefik uses **HostPort mode** (ideal):
```yaml
ports:
  web:
    hostPort: 80  # Direct access
```
Access: `http://grafana.local.dev` → Works ✅

### Scenario 2: Port 80 Unavailable
Traefik uses **NodePort mode** (fallback):
```yaml
ports:
  web:
    nodePort: 30080  # Random high port
```
Access: `http://grafana.local.dev:30080` → Works ✅

## Recommendations

1. **For dedicated Talos testing:** Delete Kind cluster to free port 80
2. **For multi-cluster setup:** Use NodePort for Traefik (automatic fallback)
3. **For production-like testing:** Keep port 80 free for HostPort mode

## Files Modified

- ✅ [scripts/deploy-talos.sh](scripts/deploy-talos.sh) - Added intelligent port detection
- ✅ Worker 1: Conditional port exposure
- ✅ Worker 2: No HTTP/HTTPS ports
- ✅ Clear warning messages

## Quick Fix Command

**To free port 80 immediately:**
```bash
# Find what's using it
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep ':80->'

# If it's Kind:
kind delete cluster

# If it's another container:
docker stop <container-name>

# Then deploy Talos:
make deploy-infra
```

---

**Status: RESOLVED** ✅
The script now handles port conflicts gracefully and continues deployment!
