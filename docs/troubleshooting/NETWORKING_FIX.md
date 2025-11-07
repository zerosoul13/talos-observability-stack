# Networking Fix for deploy-talos.sh

## Problem Identified

The original script was attempting to communicate with Talos nodes using their internal Docker network IPs (172.30.0.x), which are not directly accessible from the host system. This caused `talosctl` commands to timeout because the host couldn't route traffic to the Docker bridge network.

## Root Cause

When Docker containers are connected to a custom bridge network (talos-net with subnet 172.30.0.0/24), those IP addresses are only accessible:
1. From other containers on the same network
2. From within the Docker daemon itself

Your host system (WSL/Linux) does not have a network route to 172.30.0.0/24, so commands like:
```bash
talosctl --nodes 172.30.0.2 version
```
Would fail with connection timeouts.

## Solution Implemented

### 1. Port Mapping for All Nodes

**Changed:** Exposed Talos API ports (50000) from all nodes to the host

- Control Plane: `127.0.0.1:50000` → container port 50000
- Worker 1: `127.0.0.1:50001` → container port 50000
- Worker 2: `127.0.0.1:50002` → container port 50000

### 2. Updated All talosctl Commands

**Before:**
```bash
talosctl --nodes 172.30.0.2 version
talosctl --nodes 172.30.0.3 apply-config ...
```

**After:**
```bash
talosctl --nodes 127.0.0.1:50000 version
talosctl --nodes 127.0.0.1:50001 apply-config ...
```

### 3. Updated talosctl Configuration

**Changed:** Endpoint configuration to use localhost
```bash
talosctl config endpoint 127.0.0.1:50000
talosctl config node 127.0.0.1
```

## Changes Summary

### Port Variables
```bash
# OLD
TALOS_API_PORT=50000

# NEW
TALOS_API_PORT_CP=50000   # Control plane
TALOS_API_PORT_W1=50001   # Worker 1
TALOS_API_PORT_W2=50002   # Worker 2
```

### Docker Run Commands

**Control Plane:**
```bash
-p ${TALOS_API_PORT_CP}:50000
```

**Worker 1:**
```bash
-p ${TALOS_API_PORT_W1}:50000
```

**Worker 2:**
```bash
-p ${TALOS_API_PORT_W2}:50000
```

### Updated Functions

1. **start_control_plane()** - Uses `127.0.0.1:50000`
2. **apply_control_plane_config()** - Uses `127.0.0.1:50000`
3. **bootstrap_cluster()** - Uses `127.0.0.1:50000`
4. **start_worker_nodes()** - Exposes ports 50001 and 50002
5. **apply_worker_configs()** - Uses `127.0.0.1:50001` and `127.0.0.1:50002` with retry logic

## Network Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Host System                      │
│                   (127.0.0.1)                       │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │         Docker Bridge Network                │  │
│  │         (172.30.0.0/24)                      │  │
│  │                                              │  │
│  │  ┌───────────────┐  ┌───────────────┐      │  │
│  │  │  talos-cp-01  │  │talos-worker-01│      │  │
│  │  │  172.30.0.2   │  │  172.30.0.3   │      │  │
│  │  │               │  │               │      │  │
│  │  │  :50000       │  │  :50000       │      │  │
│  │  └───────┬───────┘  └───────┬───────┘      │  │
│  │          │                   │              │  │
│  └──────────┼───────────────────┼──────────────┘  │
│             │                   │                 │
│      Port Mapping          Port Mapping          │
│             │                   │                 │
│    127.0.0.1:50000      127.0.0.1:50001          │
│             │                   │                 │
└─────────────┼───────────────────┼─────────────────┘
              │                   │
              ▼                   ▼
         talosctl             talosctl
```

## Testing the Fix

### 1. Clean Up Old Deployment
```bash
make destroy-infra
docker network rm talos-net 2>/dev/null || true
```

### 2. Deploy with Fixed Script
```bash
make deploy-infra
```

### 3. Verify Connectivity
```bash
# Test control plane
talosctl --nodes 127.0.0.1:50000 version

# Test workers
talosctl --nodes 127.0.0.1:50001 version
talosctl --nodes 127.0.0.1:50002 version

# Check cluster health
talosctl health

# Verify Kubernetes
kubectl get nodes
```

## Why This Works

1. **Port Forwarding**: Docker's `-p` flag creates a port forward from the host to the container
2. **Localhost Access**: `127.0.0.1` is always accessible on the host
3. **No Route Needed**: We don't need a route to 172.30.0.0/24 because Docker handles the forwarding
4. **Production Parity**: This mirrors how you'd access Talos in a real deployment (via load balancer/ingress)

## Additional Improvements

### Retry Logic
Added retry logic for worker config application since workers may take longer to start their Talos API.

### Better Error Messages
```bash
if [ $retries -eq 0 ]; then
    log_error "Talos API did not become ready in time"
    log_info "Checking if container is running..."
    docker ps --filter name="${CONTROL_PLANE_NAME}"
    docker logs "${CONTROL_PLANE_NAME}" --tail 50
    exit 1
fi
```

### Endpoint Configuration
```bash
# Configure all endpoints for easy access
talosctl config endpoint 127.0.0.1:50000
```

## What Stays the Same

Internal Kubernetes networking still uses the internal IPs (172.30.0.x):
- Pods communicate using internal cluster networking
- Services use ClusterIP addresses
- Only management traffic (talosctl, kubectl) uses port forwarding

## Troubleshooting

### Issue: "connection refused"
**Solution:** Verify ports are mapped:
```bash
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

### Issue: "timeout"
**Solution:** Check if containers are running:
```bash
docker ps | grep talos
```

### Issue: "API not ready"
**Solution:** Check container logs:
```bash
docker logs talos-cp-01
```

## Benefits of This Approach

1. ✅ Works on any host OS (Linux, macOS, WSL)
2. ✅ No need to modify host routing tables
3. ✅ No firewall configuration needed
4. ✅ Mirrors real-world access patterns
5. ✅ Easy to debug with standard Docker tools
6. ✅ Portable across different network configurations

## References

- Talos in Docker: https://www.talos.dev/latest/talos-guides/install/docker/
- Docker Networking: https://docs.docker.com/network/bridge/
- Port Mapping: https://docs.docker.com/config/containers/container-networking/
