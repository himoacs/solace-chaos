# Solace Chaos Testing Environment

A comprehensive chaos testing framework for Solace PubSub+ brokers, designed for capital markets scenarios with multi-VPN architecture and optimized for queue buildup testing.

## Features

- **Two-VPN Architecture**: default (existing) and trading-vpn (new)  
- **Optimized Queue Buildup**: Exclusive queues with high-rate publishers for realistic backlog testing
- **Realistic Error Generation**: Queue overflow, ACL violations, connection limits, cross-VPN bridge failures  
- **Capital Markets Focus**: Market data distribution and trade order processing scenarios
- **Continuous Operation**: Auto-restarting publishers for low-touch long-running tests
- **Weekend-Aware**: Automatically reduces activity on weekends like real markets
- **Long-Running**: Designed for continuous operation with minimal maintenance
- **Infrastructure as Code**: Complete Terraform automation with exclusive queue configuration
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
   ./scripts/master-chaos.sh
   ```

5. **Start continuous high-rate publishing** (for queue buildup):
   ```bash
   ./scripts/continuous-publisher.sh
   ```

That's it! The system will run continuously generating various error conditions and maintaining message backlog.

## Architecture

### VPNs
- **default**: Market data, integration, and risk management (uses existing VPN)
- **trading-vpn**: Order processing and settlement (newly created VPN)

### Queue Configuration
- **5 Active Queues**: Complete multi-VPN queue architecture for comprehensive testing
  - **trading-vpn**: `equity_order_queue`, `baseline_queue`, `bridge_receive_queue` 
  - **default**: `cross_market_data_queue`
- **Exclusive Access**: Prevents zombie consumers and ensures single consumer per queue
- **Optimized Quotas**: 50-150MB quotas designed for realistic backlog testing with fast queue fill capabilities
- **Non-Persistent Messages**: Optimized for high throughput (8k+ msg/sec)

### Error Scenarios
- **Queue Buildup**: Dual high-rate publishers (35k msg/sec combined, 256KB messages) overwhelm consumers for rapid realistic backlog
- **Queue Full**: Reduced quotas (50MB for equity_order_queue) that fill quickly to 85% threshold, cycles every hour
- **ACL Violations**: Restricted users trying to access forbidden topics
- **Connection Limits**: Connection storms hitting VPN limits
- **Cross-VPN Bridge**: Bridge stress testing between VPNs

### Traffic Patterns
- **High-Rate Publishing**: 35k msg/sec with dual publishers (20k + 15k) and 256KB messages for rapid queue buildup
- **Continuous Publishers**: Auto-restarting publishers for unattended operation
- **Single Consumers**: One consumer per queue to maintain backlog
- **Weekend-Aware**: Automatically reduces rates on weekends (realistic market simulation)
- **Baseline**: Continuous health validation traffic

## Monitoring

Check system status:
```bash
./scripts/status-check.sh              # Overall system status
./scripts/queue-manager.sh status      # Queue status and message counts
```

View queue details:
```bash
./scripts/queue-manager.sh status      # Shows message counts and quota usage
./scripts/queue-manager.sh clear       # Clear all queue messages (if needed)
```

View logs:
```bash
tail -f logs/master-chaos-*.log          # Master orchestrator
tail -f logs/queue-killer.log            # Queue overflow attempts
tail -f logs/acl-violator.log           # ACL violation attempts
tail -f logs/connection-bomber.log       # Connection limit tests
tail -f logs/baseline-market.log         # Baseline market data
tail -f logs/continuous-publisher.log    # High-rate continuous publisher
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
- **5 optimized queues** with exclusive access across both VPNs
- User accounts with proper ACL profiles
- Cross-VPN bridges (optional)

Queue configuration uses **exclusive access type** to prevent zombie consumers and ensure single consumer per queue for reliable backlog testing.

To modify infrastructure:
```bash
cd terraform/environments/base
terraform plan
terraform apply
```

To check current queue configuration:
```bash
grep -A 5 "access_type" terraform/environments/base/main.tf
grep -A 10 "queues" terraform/environments/base/terraform.tfvars
```

## Process Management

### Chaos Daemon
Use the chaos daemon for managing all chaos testing components:
```bash
./scripts/chaos-daemon.sh start         # Start all components
./scripts/chaos-daemon.sh status        # Check status of all components  
./scripts/chaos-daemon.sh stop          # Stop all components
./scripts/chaos-daemon.sh restart       # Restart everything
./scripts/chaos-daemon.sh daemon &      # Run as self-healing daemon
```

### Continuous Publisher  
For unattended queue buildup testing:
```bash
./scripts/continuous-publisher.sh       # Start continuous high-rate publisher
nohup ./scripts/continuous-publisher.sh > /dev/null 2>&1 &  # Run in background
```
- **Auto-restart**: Automatically restarts after each 1M message cycle
- **High throughput**: 8000+ msg/sec for reliable queue buildup
- **Low-touch**: Designed for weeks of unattended operation

### Individual Scripts
Run specific components independently:
```bash
./scripts/master-chaos.sh               # Main orchestrator
./error-generators/queue-killer.sh      # Queue overflow testing
./error-generators/multi-vpn-acl-violator.sh  # ACL violation testing
./traffic-generators/baseline-market-data.sh  # Baseline market data
```

## Cleanup Options

Multiple cleanup scripts for different scenarios:

### Quick Cleanup (Processes Only)
```bash
./scripts/quick-cleanup.sh
```
- Stops all chaos testing processes (including continuous-publisher)
- Cleans up PID files and locks
- Preserves Terraform resources and logs
- Use when you want to restart quickly

### Consumer Cleanup
```bash
./scripts/cleanup-excess-consumers.sh   # Remove excess consumers (maintains 1 per queue)
```
- Identifies and removes excess consumers beyond the target (1 per queue)
- Maintains single consumer per queue for proper backlog testing
- Safe to run while system is operating

### Full Environment Cleanup
```bash
./scripts/full-cleanup.sh
```
- Interactive script with confirmation prompts
- Stops all processes
- Optionally backs up and cleans logs
- Optionally cleans SDKPerf extracted files
- Optionally resets .env to template
- Optionally destroys Terraform resources

### Terraform Resources Only
```bash
./scripts/terraform-cleanup.sh
```
- Focused on destroying broker resources
- Shows destruction plan before proceeding
- Backs up Terraform state files
- Multiple confirmation prompts for safety
- Use when you want to reset broker configuration

⚠️ **Cleanup Safety Notes:**
- Always check what's running with `./scripts/chaos-daemon.sh status` first
- Terraform cleanup is **destructive** - it removes all broker resources
- Full cleanup can reset your .env file to defaults
- Logs are backed up before deletion (optional)
- Use quick cleanup for routine restarts

## Logs

Structured logging in `logs/` directory:
- `master-chaos-*.log`: Main orchestrator
- `continuous-publisher.log`: High-rate publisher for queue buildup
- `baseline-*.log`: Baseline traffic (should always be healthy)
- `queue-killer.log`: Queue overflow testing
- `acl-violator.log`: ACL violation testing  
- `connection-bomber.log`: Connection limit testing
- `bridge-killer.log`: Cross-VPN bridge testing

### Log Analysis
```bash
# Monitor queue buildup progress
tail -f logs/continuous-publisher.log

# Check for errors across all logs
grep -i error logs/*.log

# Monitor message rates
grep "msgs/sec" logs/continuous-publisher.log | tail -5
```

## Stopping

### Graceful Shutdown
Stop gracefully with Ctrl+C in the master orchestrator terminal. All components will be cleanly terminated.

### Background Processes
For processes started with nohup:
```bash
./scripts/quick-cleanup.sh              # Stops all processes including background ones
# Or manually:
pkill -f continuous-publisher.sh       # Stop specific background publisher
```

### Complete System Stop
```bash
./chaos.sh stop                        # Stops master chaos and continuous publisher
./scripts/chaos-daemon.sh stop         # Alternative: stop via daemon
```

## Troubleshooting

### Environment Issues
1. **Check `.env` file configuration**: Verify broker URL and credentials
2. **Test connectivity**: Use SDKPerf test commands to verify connection
3. **Check VPN access**: Ensure users have proper permissions

### Queue Issues  
1. **No queue buildup**: 
   - Check if continuous-publisher is running: `ps aux | grep continuous-publisher`
   - Verify publisher rate: `tail -f logs/continuous-publisher.log`
   - Check consumer count: `./scripts/queue-manager.sh status`
2. **Multiple consumers**: Run `./scripts/cleanup-excess-consumers.sh`
3. **Queue access denied**: Verify exclusive queue configuration in terraform

### Infrastructure Issues
1. **Terraform state**: Check `terraform/environments/base/terraform.tfstate`
2. **Queue configuration**: `grep access_type terraform/environments/base/main.tf`
3. **Provider issues**: Check Solace provider configuration

### Performance Issues
1. **Low message rates**: Verify non-persistent message configuration
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

### Core Operations  
| Script | Purpose | Usage |
|--------|---------|-------|
| `chaos.sh` | Master control script | `./chaos.sh [start\|stop]` |
| `scripts/master-chaos.sh` | Main chaos orchestrator | `./scripts/master-chaos.sh` |
| `scripts/continuous-publisher.sh` | High-rate queue buildup | `./scripts/continuous-publisher.sh` |
| `scripts/chaos-daemon.sh` | Process management daemon | `./scripts/chaos-daemon.sh [start\|stop\|status\|restart\|daemon]` |

### Monitoring & Status
| Script | Purpose | Usage |
|--------|---------|-------|  
| `scripts/status-check.sh` | System status overview | `./scripts/status-check.sh` |
| `scripts/queue-manager.sh` | Queue monitoring & management | `./scripts/queue-manager.sh [status\|clear]` |

### Error Generators
| Script | Purpose | Usage |
|--------|---------|-------|
| `error-generators/queue-killer.sh` | Queue overflow testing | `./error-generators/queue-killer.sh` |
| `error-generators/multi-vpn-acl-violator.sh` | ACL violation testing | `./error-generators/multi-vpn-acl-violator.sh` |
| `error-generators/market-data-connection-bomber.sh` | Connection limit testing | `./error-generators/market-data-connection-bomber.sh` |
| `error-generators/cross-vpn-bridge-killer.sh` | Bridge stress testing | `./error-generators/cross-vpn-bridge-killer.sh` |

### Traffic Generators
| Script | Purpose | Usage |
|--------|---------|-------|
| `traffic-generators/baseline-market-data.sh` | Baseline market data | `./traffic-generators/baseline-market-data.sh` |
| `traffic-generators/baseline-trade-flow.sh` | Baseline trade flow | `./traffic-generators/baseline-trade-flow.sh` |

### Cleanup & Maintenance
| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/quick-cleanup.sh` | Stop processes only | `./scripts/quick-cleanup.sh` |
| `scripts/full-cleanup.sh` | Interactive complete cleanup | `./scripts/full-cleanup.sh` |
| `scripts/terraform-cleanup.sh` | Terraform resources only | `./scripts/terraform-cleanup.sh` |
| `scripts/cleanup-excess-consumers.sh` | Remove excess consumers | `./scripts/cleanup-excess-consumers.sh` |
| `scripts/kill-all-sdkperf.sh` | Kill all SDKPerf processes | `./scripts/kill-all-sdkperf.sh` |

### Common Workflows

#### Start Everything
```bash
# Method 1: Simple start
./chaos.sh start

# Method 2: Component control  
./scripts/chaos-daemon.sh start
./scripts/continuous-publisher.sh &
```

#### Monitor Queue Buildup
```bash
# Check queue status
./scripts/queue-manager.sh status

# Watch continuous publisher
tail -f logs/continuous-publisher.log

# System overview
./scripts/status-check.sh
```

#### Troubleshoot Issues
```bash
# Check running processes
./scripts/chaos-daemon.sh status

# Clean excess consumers  
./scripts/cleanup-excess-consumers.sh

# Check logs for errors
grep -i error logs/*.log
```

#### Clean Stop
```bash
# Stop everything gracefully
./chaos.sh stop

# Or via daemon
./scripts/chaos-daemon.sh stop

# Quick process cleanup
./scripts/quick-cleanup.sh
```