# Run Chaos - Single Command Orchestrator

This script runs all chaos testing components continuously until manually stopped.

## Quick Start

```bash
# Start everything (runs in foreground)
./run-chaos.sh

# Or run in background
./run-chaos.sh &

# Or use nohup for server deployment
nohup ./run-chaos.sh > logs/orchestrator.out 2>&1 &
```

## What It Does

The orchestrator automatically starts and manages:

### Traffic Generators (Continuous)
- **Market Data Feed** - Publishes to `market-data/equities/quotes/*` topics
- **Trade Flow** - Publishes to `trading/orders/*` topics and consumes from queues

### Chaos/Error Generators (Continuous)
- **Queue Killer** - Fills `equity_order_queue` with burst traffic, then drains slowly
- **ACL Violation** - Tests ACL profile restrictions with unauthorized access attempts
- **Connection Storm** - Creates connection limit stress with multiple concurrent connections
- **Bridge Stress** - Stresses cross-VPN bridges (only if `ENABLE_CROSS_VPN_BRIDGE=true`)

### Health Monitoring
- Checks component health every 5 minutes (configurable via `HEALTH_CHECK_INTERVAL` in .env)
- Automatically restarts failed components
- Tracks restart counts for each component
- Logs all activity to `logs/chaos-orchestrator.log`

## Features

✅ **Continuous Operation** - All SDKPerf instances use `-mn=999999999999999999` for indefinite runtime  
✅ **Auto-Recovery** - Failed components automatically restart  
✅ **Health Monitoring** - Regular health checks with restart tracking  
✅ **Centralized Logging** - All activity logged to single orchestrator log  
✅ **Graceful Shutdown** - Properly stops all components on SIGTERM/SIGINT  
✅ **Server Ready** - Works with nohup, systemd, or cron scheduling  

## Server Deployment

### Option 1: nohup (Simple)

```bash
# Start in background
nohup ./run-chaos.sh > logs/orchestrator.out 2>&1 &

# Save PID for later
echo $! > logs/pids/orchestrator.pid

# Stop later
kill $(cat logs/pids/orchestrator.pid)
```

### Option 2: systemd Service (Recommended)

Create `/etc/systemd/system/solace-chaos.service`:

```ini
[Unit]
Description=Solace Chaos Testing Orchestrator
After=network.target

[Service]
Type=simple
User=your_user
WorkingDirectory=/path/to/solace-chaos
ExecStart=/path/to/solace-chaos/run-chaos.sh
Restart=on-failure
RestartSec=10
StandardOutput=append:/path/to/solace-chaos/logs/orchestrator.out
StandardError=append:/path/to/solace-chaos/logs/orchestrator.err

[Install]
WantedBy=multi-user.target
```

Then:
```bash
sudo systemctl daemon-reload
sudo systemctl enable solace-chaos
sudo systemctl start solace-chaos
sudo systemctl status solace-chaos
```

### Option 3: Cron (Scheduled Start)

Add to crontab for automatic startup on reboot:
```bash
@reboot cd /path/to/solace-chaos && ./run-chaos.sh >> logs/cron.log 2>&1
```

## Stopping the Orchestrator

### If running in foreground:
```bash
Ctrl+C
```

### If running in background:
```bash
# Find the PID
ps aux | grep run-chaos.sh

# Stop gracefully
kill <PID>

# Or force stop
pkill -f run-chaos.sh
```

### Stop all related processes:
```bash
./scripts/quick-cleanup.sh
```

## Monitoring

### View orchestrator logs:
```bash
tail -f logs/chaos-orchestrator.log
```

### View component logs:
```bash
tail -f logs/traffic-market-data.log
tail -f logs/chaos-queue-killer.log
```

### Check status:
```bash
./scripts/status-check.sh
```

### Monitor queue status:
```bash
./scripts/queue-manager.sh status
```

## Configuration

All configuration is in `.env`. Key variables:

```bash
# Health check frequency (seconds)
HEALTH_CHECK_INTERVAL=300

# Traffic rates
WEEKDAY_MARKET_DATA_RATE=2000
WEEKEND_MARKET_DATA_RATE=50

# Chaos parameters
QUEUE_KILLER_CYCLE_INTERVAL=3600
BRIDGE_ATTACK_DURATION=600
```

## Logs

All logs are in the `logs/` directory:

- `chaos-orchestrator.log` - Main orchestrator activity
- `traffic-market-data.log` - Market data generator
- `traffic-trade-flow.log` - Trade flow generator
- `chaos-queue-killer.log` - Queue killer activity
- `chaos-acl-violation.log` - ACL violation tests
- `chaos-connection-storm.log` - Connection storm activity
- `chaos-bridge-stress.log` - Bridge stress activity

### Automatic Log Rotation

**All log files are automatically trimmed** to prevent unbounded growth:

- **Check Frequency**: Every 10 health checks (~50 minutes with default settings)
- **Max Size**: 50MB per log file (configurable via `LOG_MAX_SIZE_MB` in `.env`)
- **Retention**: Keeps last 5000 lines per file when trimming
- **Scope**: Trims ALL `.log` files in `logs/` directory

Example configuration in `.env`:
```bash
LOG_MAX_SIZE_MB=50          # Trim when log exceeds this size
HEALTH_CHECK_INTERVAL=300   # How often to check (also affects trim frequency)
```

With default settings:
- Health checks every 5 minutes
- Log trim checks every 10 health checks = every ~50 minutes
- Each log file capped at 50MB
- Old content automatically purged, keeping recent 5000 lines

**You don't need to manually manage logs** - the orchestrator handles it automatically.

## Troubleshooting

### Components keep restarting
Check component-specific logs in `logs/chaos-*.log` or `logs/traffic-*.log` for errors.

### SDKPerf not found
Run bootstrap first:
```bash
./scripts/bootstrap-chaos-environment.sh
```

### Want to disable specific generators
Edit `run-chaos.sh` and comment out the unwanted `start_*_generator` lines in the `startup()` function.

## Advanced Usage

### Custom Health Check Interval

Set in `.env`:
```bash
HEALTH_CHECK_INTERVAL=600  # 10 minutes
```

### Disable Specific Generators

Edit `run-chaos.sh` startup section:
```bash
# Comment out unwanted generators
# start_chaos_generator "connection-storm"
```

### Add Custom Generators

Add to the `startup()` function:
```bash
start_chaos_generator "queue-killer" "--target-queue baseline_queue --burst-size 50000"
```

## Comparison with Old Workflow

| Old | New |
|-----|-----|
| Start 7+ individual scripts | Run single `./run-chaos.sh` |
| Manual monitoring required | Automatic health checks |
| Manual restart on failure | Auto-restart with tracking |
| Scattered logs | Centralized orchestrator log |
| Complex server deployment | Simple nohup/systemd |

---

**Ready to run!** Just execute `./run-chaos.sh` and everything starts automatically.
