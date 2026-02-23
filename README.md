# Solace Chaos Testing Environment

A comprehensive chaos testing framework for Solace PubSub+ brokers, designed for capital markets scenarios with multi-VPN architecture and optimized for realistic load testing.

## Features

- **Two-VPN Architecture**: market_data and trading with cross-VPN bridge
- **SEMP API Provisioning**: Direct API-based infrastructure setup (no Terraform required)
- **Unified Orchestrator**: Single run-chaos.sh manages all components
- **Realistic Traffic Patterns**: Market data feeds and trade flow simulation
- **Error Generation**: Queue overflow, ACL violations, connection storms, bridge stress
- **Capital Markets Focus**: Market data distribution and trade order processing scenarios
- **Auto-Restart**: Self-healing components with automatic restarts
- **Weekend-Aware**: Automatically reduces activity on weekends like real markets
- **VMR Compatible**: Works with free Solace PubSub+ Standard (with guidance for production brokers)

## Quick Start

1. **Download SDKPerf**:
   - Visit https://docs.solace.com/API/SDKPerf/Command-Line-Options.htm
   - Download `sdkperf-jcsmp-8.4.19.7.zip` (or latest version)
   - Place the ZIP file in `sdkperf-tools/` directory
   - Run bootstrap script to auto-extract: `./scripts/bootstrap-chaos-environment.sh`

2. **Configure environment**:
   ```bash
   cd solace-chaos
   cp .env.template .env
   # Edit .env with your Solace broker connection details:
   # - SOLACE_BROKER_HOST (default: localhost)
   # - SOLACE_BROKER_PORT (default: 55554)  
   # - SOLACE_SEMP_HOST (default: localhost)
   # - SOLACE_SEMP_PORT (default: 8080)
   ```

3. **Provision infrastructure** (VPNs, queues, users, bridges):
   ```bash
   ./scripts/semp-provision.sh create
   ```

4. **Start chaos testing**:
   ```bash
   bash run-chaos.sh &
   ```

That's it! The system will run continuously generating realistic traffic and various error conditions.

## Architecture

### Components
**Orchestrator**: `run-chaos.sh`
- Single unified orchestrator managing all components
- Health monitoring with automatic restarts
- Graceful shutdown handling
- Centralized logging

**Traffic Generators**: (2 modes via `traffic-generator.sh`)
- **market-data**: Publishes and subscribes to stock quotes on market_data VPN (2K msg/sec, 256 bytes)
- **trade-flow**: Sends orders to trading VPN queues with drain consumers

**Chaos Generators**: (4 scenarios via `chaos-generator.sh`)
- **queue-killer**: Floods queues to test overflow behavior
- **acl-violation**: Attempts unauthorized topic access (~1 per hour)
- **connection-storm**: Creates rapid connection/disconnection cycles
- **bridge-stress**: High-volume bridge stress testing (5K msg/sec, 10KB messages)

### VPNs
- **market_data**: Market data feeds, bridge source
- **trading**: Order processing, bridge destination

### Queue Configuration
- **4 Queues** across both VPNs:
  - **trading**: `equity_order_queue` (50 MB), `baseline_queue` (80 MB), `bridge_receive_queue` (120 MB)
  - **market_data**: `cross_market_data_queue` (150 MB)
- **Exclusive Access**: Single consumer per queue
- **Cross-VPN Bridge**: Forwards bridge-stress traffic from market_data to trading

### SDKPerf Configuration
**Important**: This chaos framework uses **direct messaging** (topic publishing with `-ptl`) which works with all client profiles including the default profile.
# Check orchestrator and component status
tail -f logs/chaos-orchestrator.log

# Check Java SDKPerf processes  
ps aux | grep "java.*sdkperf" | grep -v grep

# Check connected clients on broker
curl -s -u admin:admin 'http://localhost:8080/SEMP/v2/monitor/msgVpns/market_data/clients'

# Check queue statistics
curl -s -u admin:admin 'http://localhost:8080/SEMP/v2/monitor/msgVpns/trading/queues'
```

View component logs:
```bash
tail -f logs/chaos-orchestrator.log      # Main orchestrator
tail -f logs/market-data-traffic.log     # Market data SDKPerf output
tail -f logs/trade-flow-traffic.log      # Trade flow SDKPerf output
tail -f logs/queue-killer-chaos.log      # Queue killer chaos generator
tail -f logs/acl-violation-chaos.log     # ACL violation attempts
tail -f logs/connection-storm-chaos.log  # Connection storm tests
tail -f logs/bridge-stress-chaos.log     # Bridge stress testing
``` using declarative definitions:

**Infrastructure Definitions**:
- `VPN_*`: Message VPN configurations
- `QUEUE_*`: Queue names, VPNs, quotas, access types, subscriptions
- `USER_*`: Client usernames with roles, VPNs, passwords, ACL/client profiles
- `ACL_*`: ACL profile rules (connect, publish, subscribe permissions)

**Runtime Settings**:
- Broker connection details (host, ports)
- SEMP API credentials  
- Traffic rates (weekday vs weekend)
- Restart intervals

**Example Queue Definition**:
```bash
# Format: "name,vpn,quota_mb,access_type,subscriptions"
QUEUE_1="equity_order_queue,trading,50,exclusive,trading/orders/equities/>"
```

**Example User Definition**:
```bash
# Format: "role,vpn,password,acl_profile,client_profile"
USER_1="market-feed,market_data,market_feed_pass,market_data_publisher,default"
```

## Infrastructure Management

### SEMP Provisioning

All infrastructure is managed via SEMP API v2:
Unified Orchestrator
The main orchestrator manages all components:

**Start chaos testing**:
```bash
bash run-chaos.sh &
```

**Check status**:
```bash
# Check orchestrator log
tail -f logs/chaos-orchestrator.log

# Check all running components
ps aux | grep -E "(traffic-generator|chaos-generator|sdkperf)" | grep -v grep
```

**Stop everything**:
```bash
pkill -9 -f "run-chaos"; pkill -9 -f "traffic-generator"; pkill -9 -f "chaos-generator"; pkill -9 sdkperf
```

### Component Architecture

**Orchestrator** (`run-chaos.sh`):
- Launches 2 traffic generators + 4 chaos generators
- Monitors health every 60 seconds
- Auto-restarts failed components
- Handles graceful shutdown


### Stop Processes
Kill all running chaos components:
```bash
pkill -9 -f "run-chaos"
pkill -9 -f "traffic-generator"  
pkill -9 -f "chaos-generator"
pkill -9 sdkperf
```

### Delete Infrastructure
Remove all broker resources (VPNs, queues, users, bridges):
```bash
./scripts/semp-provision.sh delete
```

Interactive deletion with confirmation prompts.

### Clean Logs
```bash
rm logs/*.log
rm logs/pids/*.pid
```

### Full Reset
```bash
# Stop processes
pkill -9 -f "run-chaos"; pkill -9 -f "traffic-generator"; pkill -9 -f "chaos-generator"; pkill -9 sdkperf

# Delete infrastructure  
./scripts/semp-provision.sh delete

# Clean logs
rm logs/*.log logs/pids/*.pid

# Start fresh
./scripts/semp-provision.sh create
bash run-chaos.sh &
```

## Process Management

### Unified Orchestrator (run-chaos.sh)
The main orchestrator manages all chaos testing components with built-in health monitoring:

```bash
# Start all chaos testing components
bash run-chaos.sh &

# Or use the convenience wrapper
./chaos.sh start

# Stop all components
./chaos.sh stop

# Check status
./scripts/status-check.sh
```

**Features:**
- **Auto-restart**: Automatically restarts failed components
- **Health monitoring**: Continuous health checks with auto-recovery
- **Weekend-aware**: Reduces activity on weekends like real markets
- **Unified logging**: All components log to `logs/` directory
- **Signal handling**: Graceful shutdown on SIGTERM/SIGINT

### Individual Components
For advanced testing, run components independently:

```bash
# Traffic generators
./traffic-generators/traffic-generator.sh --mode market-data
./traffic-generators/traffic-generator.sh --mode trade-flow

# Error generators
./error-generators/chaos-generator.sh --scenario queue-killer
./error-generators/chaos-generator.sh --scenario acl-violation
./error-generators/chaos-generator.sh --scenario connection-storm
./error-generators/chaos-generator.sh --scenario bridge-stress
```

## Cleanup Options

Multiple cleanup scripts for different scenarios:

### Quick Cleanup (Processes Only)
```bash
./scripts/quick-cleanup.sh
```
- Stops all chaos testing processes
- Cleans up PID files and locks
- Preserves broker resources and logs
- Use when you want to restart quickly

### Consumer Cleanup
```bash
./scripts/cleanup-excess-consumers.sh   # Remove excess consumers (maintains 1 per queue)
```
- Identifies and removes excess consumers beyond the target (1 per queue)
- Maintains single consumer per queue for proper backlog testing
- Safe to run while system is operating
- **Auto-cleanup**: Master orchestrator runs this automatically every ~5 minutes

### Full Environment Cleanup
```bash
./scripts/full-cleanup.sh
```
- Interactive script with confirmation prompts
- Stops all processes
- Optionally backs up and cleans logs
- Optionally cleans SDKPerf extracted files
- Optionally resets .env to template
- Optionally destroys SEMP-provisioned broker resources

### SEMP Resources Only
```bash
./scripts/semp-provision.sh destroy
```
- Focused on destroying broker resources (VPNs, queues, users, bridges)
- Shows what will be deleted before proceeding
- Multiple confirmation prompts for safety
- Use when you want to reset broker configuration

⚠️ **Cleanup Safety Notes:**
- Always check what's running with `./scripts/status-check.sh` first
- Resource cleanup is **destructive** - it removes all broker configuration
- Full cleanup can reset your .env file to defaults
- Logs are backed up before deletion (optional)
- Use quick cleanup for routine restarts

## Logs

Structured logging in `logs/` directory:
- `run-chaos-*.log`: Main orchestrator
- `traffic-*.log`: Traffic generator logs (market-data, trade-flow)
- `chaos-*.log`: Error generator scenarios
- `semp-provision.log`: SEMP API provisioning operations
- `acl-violator.log`: ACL violation testing  
- `connection-bomber.log`: Connection limit testing
- `bridge-killer.log`: Cross-VPN bridge testing

### Log Analysis
```bash
# Monitor traffic generators
tail -f logs/traffic-market-data.log
tail -f logs/traffic-trade-flow.log

# Check for errors across all logs
grep -i error logs/*.log

# Monitor message rates
grep "rate" logs/traffic-*.log | tail -10
```

## Stopping

### Graceful Shutdown
Stop gracefully with Ctrl+C in the master orchestrator terminal. All components will be cleanly terminated.

### Background Processes
For processes started in background:
```bash
./scripts/quick-cleanup.sh              # Stops all processes including background ones
# Or manually:
pkill -f "run-chaos.sh"                # Stop orchestrator
pkill -f "traffic-generator.sh"        # Stop traffic generators
pkill -f "chaos-generator.sh"          # Stop chaos generators
```

### Complete System Stop
```bash
./chaos.sh stop                        # Stops all chaos components
```

## Troubleshooting

### Environment Issues
1. **Check `.env` file configuration**: Verify broker URL and credentials
2. **Test connectivity**: Use SDKPerf test commands to verify connection
3. **Check VPN access**: Ensure users have proper permissions

### Queue Issues  
1. **No queue buildup**: 
   - Check if traffic generators are running: `ps aux | grep traffic-generator`
   - Verify publisher rate: `tail -f logs/traffic-*.log`
   - Check chaos generators: `ps aux | grep chaos-generator`
2. **Multiple consumers**: Run `./scripts/cleanup-excess-consumers.sh`
3. **Queue access denied**: Verify queue permissions via SEMP

### Infrastructure Issues
1. **SEMP provisioning**: Check `logs/semp-provision.log` for errors
2. **Broker connectivity**: Verify SEMP_HOST and SEMP_PORT in `.env`
3. **Authorization errors**: Check user permissions and authorization level

### Performance Issues
1. **Low message rates**: Check traffic generator configuration
2. **Publisher failures**: Check SDKPerf logs for connection issues  
3. **Throughput limits**: Solace Standard Edition has 10K msg/sec limit

### Component Failures
Check individual component logs in `logs/` directory. The system is designed to be self-healing - failed components automatically restart.

## Capital Markets Scenarios

The framework simulates realistic capital markets patterns:
- **Market data feeds**: NYSE, NASDAQ quotes and trades
- **Trade order processing**: Equity orders with exclusive queue access  
- **Risk management**: Real-time risk calculations and limits
- **Queue buildup simulation**: Realistic backlog scenarios for stress testing
- **Cross-market integration**: Multi-VPN architecture scenarios
- **Weekend quiet periods**: Reduced activity vs weekday high activity

### Queue Buildup Testing
Perfect for testing monitoring and alerting systems:
- **Realistic backlog**: 4000+ messages queued at 100% quota usage
- **Sustained load**: Continuous high-rate publishing (8k+ msg/sec)
- **Single consumer bottleneck**: Simulates real-world processing constraints
- **Exclusive queues**: Prevents consumer scaling, maintains backlog

Perfect for testing monitoring and alerting systems in financial services environments.

## Complete Scripts Reference

### Bootstrap & Setup
| Script | Purpose | Usage |
|--------|---------|-------|
| `bootstrap-chaos-environment.sh` | Complete environment setup | `./bootstrap-chaos-environment.sh` |
| `scripts/load-env.sh` | Load environment variables | `source scripts/load-env.sh` |
| `scripts/semp-provision.sh` | SEMP API provisioning | `./scripts/semp-provision.sh [create\|destroy]` |

### Core Operations  
| Script | Purpose | Usage |
|--------|---------|-------|
| `chaos.sh` | Master control wrapper | `./chaos.sh [start\|stop]` |
| `run-chaos.sh` | Main chaos orchestrator | `bash run-chaos.sh &` |

### Monitoring & Status
| Script | Purpose | Usage |
|--------|---------|-------|  
| `scripts/status-check.sh` | System status overview | `./scripts/status-check.sh` |
| `scripts/queue-manager.sh` | Queue monitoring & management | `./scripts/queue-manager.sh [status\|clear]` |

### Error Generators (Unified)
| Script | Purpose | Usage |
|--------|---------|-------|
| `error-generators/chaos-generator.sh` | All chaos scenarios | `./error-generators/chaos-generator.sh --scenario [queue-killer\|acl-violation\|connection-storm\|bridge-stress]` |

### Traffic Generators (Unified)
| Script | Purpose | Usage |
|--------|---------|-------|
| `traffic-generators/traffic-generator.sh` | All traffic patterns | `./traffic-generators/traffic-generator.sh --mode [market-data\|trade-flow]` |

### Cleanup & Maintenance
| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/quick-cleanup.sh` | Stop processes only | `./scripts/quick-cleanup.sh` |
| `scripts/full-cleanup.sh` | Interactive complete cleanup | `./scripts/full-cleanup.sh` |
| `scripts/cleanup-excess-consumers.sh` | Remove excess consumers | `./scripts/cleanup-excess-consumers.sh` |
| `scripts/kill-all-sdkperf.sh` | Kill all SDKPerf processes | `./scripts/kill-all-sdkperf.sh` |

### Utility Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/semp-lib.sh` | SEMP API library functions | Source in other scripts |
| `scripts/config-parser.sh` | Configuration parsing utilities | Source in other scripts |
| `scripts/sdkperf-wrapper.sh` | SDKPerf management wrapper | Internal use |

### Common Workflows

#### Start Everything
```bash
# Method 1: Simple start
./chaos.sh start

# Method 2: Direct orchestrator
bash run-chaos.sh &
```

#### Monitor System
```bash
# Check queue status
./scripts/queue-manager.sh status

# Watch orchestrator logs
tail -f logs/run-chaos-*.log

# System overview
./scripts/status-check.sh

# Monitor specific traffic
tail -f logs/traffic-market-data.log
tail -f logs/traffic-trade-flow.log
```

#### Troubleshoot Issues
```bash
# Check running processes
ps aux | grep -E "(run-chaos|traffic-generator|chaos-generator)"

# Clean excess consumers  
./scripts/cleanup-excess-consumers.sh

# Check logs for errors
grep -i error logs/*.log
```

#### Clean Stop
```bash
# Stop everything gracefully
./chaos.sh stop

# Quick process cleanup
./scripts/quick-cleanup.sh
```