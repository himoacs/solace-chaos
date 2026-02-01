# Solace Chaos Testing Environment

A comprehensive chaos testing framework for Solace PubSub+ brokers, designed for capital markets scenarios with multi-VPN architecture.

## Features

- **Two-VPN Architecture**: default (existing) and trading-vpn (new)
- **Realistic Error Generation**: Queue overflow, ACL violations, connection limits, cross-VPN bridge failures  
- **Capital Markets Focus**: Market data distribution and trade order processing scenarios
- **Weekend-Aware**: Automatically reduces activity on weekends like real markets
- **Long-Running**: Designed to run for weeks with minimal maintenance
- **Infrastructure as Code**: Complete Terraform automation
- **Single Command Setup**: One script sets up everything

## Quick Start

1. **Download SDKPerf**:
   - Visit https://docs.solace.com/API/SDKPerf/Command-Line-Options.htm
   - Download `sdkperf-jcsmp-X.X.X.X.zip` 
   - Place the ZIP file in `sdkperf-tools/` directory

2. **Clone and configure**:
   ```bash
   cd solace-chaos
   cp .env.template .env
   # Edit .env with your Solace broker details
   ```

3. **Bootstrap everything**:
   ```bash
   ./bootstrap-chaos-environment.sh
   ```

4. **Start chaos testing**:
   ```bash
   ./master-chaos.sh
   ```

That's it! The system will run continuously generating various error conditions.

## Architecture

### VPNs
- **default**: Market data, integration, and risk management (uses existing VPN)
- **trading-vpn**: Order processing and settlement (newly created VPN)

### Error Scenarios
- **Queue Full**: Small queues (5MB) that fill quickly
- **ACL Violations**: Restricted users trying to access forbidden topics
- **Connection Limits**: Connection storms hitting VPN limits
- **Cross-VPN Bridge**: Bridge stress testing between VPNs

### Traffic Patterns
- **Weekday**: High activity (1000+ msgs/sec)
- **Weekend**: Minimal activity (10 msgs/sec)
- **Continuous**: Baseline traffic always flowing for health validation

## Monitoring

Check system status:
```bash
./scripts/status-check.sh
```

View logs:
```bash
tail -f logs/master-chaos-*.log          # Master orchestrator
tail -f logs/queue-killer.log            # Queue overflow attempts
tail -f logs/acl-violator.log           # ACL violation attempts
tail -f logs/connection-bomber.log       # Connection limit tests
tail -f logs/baseline-market.log         # Baseline market data
```

## Configuration

All configuration is in `.env` file:
- Broker connection details
- User credentials for each VPN
- Rate limits and quotas
- Weekend vs weekday behavior

## Infrastructure

Terraform manages:
- VPN creation and configuration
- Queue setup with appropriate quotas
- User accounts with proper ACL profiles
- Cross-VPN bridges (optional)

To modify infrastructure:
```bash
cd terraform/environments/base
terraform plan
terraform apply
```

## Process Management

Use the chaos daemon for process management:
```bash
# Start all components
./chaos-daemon.sh start

# Check status
./chaos-daemon.sh status

# Stop all components
./chaos-daemon.sh stop

# Restart everything
./chaos-daemon.sh restart

# Run as self-healing daemon
./chaos-daemon.sh daemon &
```

## Cleanup Options

Multiple cleanup scripts for different scenarios:

### Quick Cleanup (Processes Only)
```bash
./quick-cleanup.sh
```
- Stops all chaos testing processes
- Cleans up PID files and locks
- Preserves Terraform resources and logs
- Use when you want to restart quickly

### Full Environment Cleanup
```bash
./full-cleanup.sh
```
- Interactive script with confirmation prompts
- Stops all processes
- Optionally backs up and cleans logs
- Optionally cleans SDKPerf extracted files
- Optionally resets .env to template
- Optionally destroys Terraform resources

### Terraform Resources Only
```bash
./terraform-cleanup.sh
```
- Focused on destroying broker resources
- Shows destruction plan before proceeding
- Backs up Terraform state files
- Multiple confirmation prompts for safety
- Use when you want to reset broker configuration

⚠️ **Cleanup Safety Notes:**
- Always check what's running with `./chaos-daemon.sh status` first
- Terraform cleanup is **destructive** - it removes all broker resources
- Full cleanup can reset your .env file to defaults
- Logs are backed up before deletion (optional)
- Use quick cleanup for routine restarts

## Logs

Structured logging in `logs/` directory:
- `master-chaos-*.log`: Main orchestrator
- `baseline-*.log`: Baseline traffic (should always be healthy)
- `queue-killer.log`: Queue overflow testing
- `acl-violator.log`: ACL violation testing  
- `connection-bomber.log`: Connection limit testing
- `bridge-killer.log`: Cross-VPN bridge testing

## Stopping

Stop gracefully with Ctrl+C in the master orchestrator terminal. All components will be cleanly terminated.

## Troubleshooting

1. **Environment issues**: Check `.env` file configuration
2. **Connectivity issues**: Verify broker URL and credentials
3. **Infrastructure issues**: Check Terraform state and logs
4. **Component failures**: Check individual component logs

The system is designed to be self-healing - failed components automatically restart.

## Capital Markets Scenarios

The framework simulates realistic capital markets patterns:
- Market data feeds (NYSE, NASDAQ quotes and trades)
- Order processing workflows (equity orders, settlements)
- Risk management calculations
- Cross-market integration scenarios
- Weekend quiet periods vs weekday high activity

Perfect for testing monitoring and alerting systems in financial services environments.