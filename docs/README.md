# Documentation

This directory contains all documentation for the Talos Local Development Platform.

## Core Documentation

- **[Architecture.md](Architecture.md)** - System architecture, component interactions, and design decisions
- **[Observability-Stack.md](Observability-Stack.md)** - Detailed guide to the monitoring and logging setup
- **[TRAEFIK_IMPLEMENTATION.md](TRAEFIK_IMPLEMENTATION.md)** - Traefik ingress controller configuration and usage
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Project implementation notes and technical decisions
- **[ProductRoadmap.md](ProductRoadmap.md)** - Planned features and future enhancements

## Troubleshooting Guides

See the [troubleshooting/](troubleshooting/) directory for historical issues and their solutions:

- **[FINAL_SOLUTION.md](troubleshooting/FINAL_SOLUTION.md)** - Complete solution to initial deployment issues
- **[NETWORKING_FIX.md](troubleshooting/NETWORKING_FIX.md)** - Network configuration fixes
- **[PORT_80_FIX.md](troubleshooting/PORT_80_FIX.md)** - Port binding resolution
- **[MAKEFILE_FIX.md](troubleshooting/MAKEFILE_FIX.md)** - Makefile improvements
- **[SHARED_FILESYSTEMS_FIX.md](troubleshooting/SHARED_FILESYSTEMS_FIX.md)** - Storage provisioner fixes
- **[REAL_ISSUE_EXPLAINED.md](troubleshooting/REAL_ISSUE_EXPLAINED.md)** - Root cause analysis
- **[ISSUE_RESOLVED.md](troubleshooting/ISSUE_RESOLVED.md)** - Final issue resolution

## Quick Links

- [Main README](../README.md) - Project overview and quick start
- [Infrastructure Configs](../infrastructure/) - Kubernetes manifests and configurations
- [Deployment Scripts](../scripts/) - Automation scripts
- [Examples](../examples/) - Sample applications

## Getting Help

If you encounter issues:

1. Check the [Troubleshooting section](../README.md#troubleshooting) in the main README
2. Review relevant troubleshooting guides in [troubleshooting/](troubleshooting/)
3. Check pod logs: `kubectl logs -n <namespace> <pod-name>`
4. Verify cluster status: `make status`

## Contributing

Documentation improvements are welcome! Please ensure:
- Examples are tested and working
- Links are valid and relative
- Code snippets are properly formatted
- Commands include expected output where helpful
