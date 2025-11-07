# Talos Configuration Files

This directory contains Talos Linux configuration files for the Kubernetes cluster.

## Generated Files

After running `make deploy-infra`, the following files will be generated:

- **controlplane.yaml** - Configuration for the control plane node
- **worker.yaml** - Configuration for worker nodes
- **talosconfig** - Talos CLI configuration (also copied to ~/.talos/config)

## Manual Configuration

If you need to customize the Talos configuration:

1. Generate base configs:
   ```bash
   talosctl gen config talos-local https://127.0.0.1:6443 \
     --kubernetes-version 1.31.1 \
     --output-types controlplane,worker,talosconfig
   ```

2. Edit the generated YAML files as needed

3. Apply custom configs:
   ```bash
   # Control plane
   talosctl apply-config --nodes 127.0.0.1 --file controlplane.yaml --insecure

   # Workers
   talosctl apply-config --nodes 172.20.0.3 --file worker.yaml --insecure
   talosctl apply-config --nodes 172.20.0.4 --file worker.yaml --insecure
   ```

## Storage Provisioner

The **local-path-provisioner.yaml** file provides dynamic persistent volume provisioning using local storage on worker nodes.

Features:
- Automatic PV provisioning for PVCs
- Storage location: /opt/local-path-provisioner on each node
- ReclaimPolicy: Delete (volumes removed when PVC is deleted)
- Default storage class

Apply manually if needed:
```bash
kubectl apply -f local-path-provisioner.yaml
```

## Talos Configuration Reference

Key settings in generated configs:

### Control Plane
- Kubernetes control plane components
- etcd configuration
- API server settings
- CNI: Flannel (default)

### Workers
- Kubelet configuration
- Container runtime settings
- Pod CIDR: 10.244.0.0/16

### Network
- Service CIDR: 10.96.0.0/12
- Pod CIDR: 10.244.0.0/16
- CNI Plugin: Flannel

## Troubleshooting

### View applied configuration
```bash
talosctl --nodes 127.0.0.1 get machineconfig
```

### Reset node configuration
```bash
talosctl --nodes 127.0.0.1 reset
```

### Update configuration
```bash
talosctl --nodes 127.0.0.1 apply-config --file controlplane.yaml
```

## Security Notes

For local development:
- Talos API secured with client certificates
- Certificates stored in talosconfig
- No SSH access (API-only management)
- RBAC enabled by default

In production, additionally:
- Use trusted certificate authorities
- Implement network policies
- Enable audit logging
- Restrict API access
