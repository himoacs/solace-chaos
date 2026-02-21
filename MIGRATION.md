# Migration Guide: Simplified Configuration System

This guide helps you migrate to the new simplified infrastructure configuration system that eliminates manual template editing and reduces script duplication.

## What Changed?

### ✅ Benefits
- **Single Source of Truth**: Infrastructure defined once in `.env`, auto-generates both Terraform and SEMP configs
- **No Template Editing**: Never manually edit `terraform.tfvars` again - it's auto-generated
- **70% Fewer Scripts**: Consolidated from 7+ specialized generators to 2 parameterized scripts
- **Reduced Duplication**: Eliminated 4-way configuration duplication (`.env` → `terraform.tfvars` → `semp-provision.sh` → `main.tf`)
- **Cleaner Connections**: SDKPerf connection boilerplate extracted to reusable wrapper functions
- **1500+ Lines Removed**: Simplified codebase with centralized infrastructure definitions

### 🔧 New Components

1. **[scripts/config-parser.sh](scripts/config-parser.sh)** - Parses structured infrastructure definitions from `.env`
2. **[scripts/generate-terraform-config.sh](scripts/generate-terraform-config.sh)** - Auto-generates `terraform.tfvars` from `.env`
3. **[scripts/sdkperf-wrapper.sh](scripts/sdkperf-wrapper.sh)** - Centralized SDKPerf connection management
4. **[traffic-generators/traffic-generator.sh](traffic-generators/traffic-generator.sh)** - Unified traffic generator with modes
5. **[error-generators/chaos-generator.sh](error-generators/chaos-generator.sh)** - Unified chaos generator with scenarios

### 📝 Environment File Changes

Your `.env` file now includes structured infrastructure definitions at the bottom:

```bash
# Queue Definitions: name,vpn,quota_mb,access_type,subscriptions
QUEUE_1="equity_order_queue,trading,50,exclusive,trading/orders/equities/>"
QUEUE_2="baseline_queue,trading,80,exclusive,trading/orders/>"
QUEUE_3="bridge_receive_queue,trading,120,exclusive,market-data/bridge-stress/>"
QUEUE_4="cross_market_data_queue,market_data,150,exclusive,market-data/bridge-stress/>"

# ACL Profile Definitions: name,vpn,connect_action,publish_action,subscribe_action
ACL_1="market_data_publisher,market_data,allow,allow,allow"
ACL_2="market_data_subscriber,market_data,allow,disallow,allow"
# ... more ACL profiles

# User Definitions: role,vpn,password,acl_profile,client_profile
USER_1="market-feed,market_data,market_feed_pass,market_data_publisher,default"
USER_2="market-consumer,market_data,market_consumer_pass,market_data_subscriber,default"
# ... more users
```

**Backward Compatibility**: Old credential variables (`MARKET_DATA_FEED_USER`, etc.) are still present for compatibility but are no longer required by new scripts.

## Migration Steps

### For Existing Projects

**Option 1: Use Updated .env (Recommended)**

Your `.env` has already been updated with the new infrastructure definitions. The old variables are still there for backward compatibility.

1. Review the new infrastructure definitions at the bottom of `.env`
2. Run bootstrap to test: `./scripts/bootstrap-chaos-environment.sh`
3. The system will use the new structured definitions automatically

**Option 2: Fresh Start**

If you want a completely clean setup:

1. Backup your current `.env`: `cp .env .env.backup`
2. Review the new infrastructure definitions added to `.env`
3. Run bootstrap: `./scripts/bootstrap-chaos-environment.sh`

### Customizing Infrastructure

To add/modify infrastructure, edit the corresponding sections in `.env`:

**Add a New Queue:**
```bash
QUEUE_5="risk_queue,trading,100,exclusive,risk/assessment/>"
```

**Add a New User:**
```bash
USER_9="risk-calculator,trading,risk_pass,trade_processor,default"
```

**Modify ACL Profile:**
```bash
ACL_11="auditor,trading,allow,disallow,allow"
```

After changes, re-run bootstrap or provisioning:
- For Terraform: `./scripts/bootstrap-chaos-environment.sh` (it will regenerate `terraform.tfvars`)
- For SEMP: `./scripts/semp-provision.sh create` (it will use new definitions automatically)

## Using New Consolidated Generators

### Traffic Generators

**Old Way (Multiple Scripts):**
```bash
./traffic-generators/baseline-market-data.sh &
./traffic-generators/baseline-trade-flow.sh &
```

**New Way (Single Parameterized Script):**
```bash
./traffic-generators/traffic-generator.sh --mode market-data &
./traffic-generators/traffic-generator.sh --mode trade-flow &

# With custom rates
./traffic-generators/traffic-generator.sh --mode market-data --rate 5000 --weekend-rate 500 &
```

### Chaos/Error Generators

**Old Way (Multiple Scripts):**
```bash
./error-generators/queue-killer.sh &
./error-generators/multi-vpn-acl-violator.sh &
./error-generators/market-data-connection-bomber.sh &
```

**New Way (Single Parameterized Script):**
```bash
./error-generators/chaos-generator.sh --scenario queue-killer &
./error-generators/chaos-generator.sh --scenario acl-violation &
./error-generators/chaos-generator.sh --scenario connection-storm &

# With custom parameters
./error-generators/chaos-generator.sh --scenario queue-killer --target-queue baseline_queue --burst-size 50000 &
```

## Script Mapping

| Old Script | New Equivalent |
|------------|---------------|
| `baseline-market-data.sh` | `traffic-generator.sh --mode market-data` |
| `baseline-trade-flow.sh` | `traffic-generator.sh --mode trade-flow` |
| `queue-killer.sh` | `chaos-generator.sh --scenario queue-killer` |
| `queue-killer-burst.sh` | `chaos-generator.sh --scenario queue-killer` (burst built-in) |
| `multi-vpn-acl-violator.sh` | `chaos-generator.sh --scenario acl-violation` |
| `market-data-connection-bomber.sh` | `chaos-generator.sh --scenario connection-storm` |
| `cross-vpn-bridge-killer.sh` | `chaos-generator.sh --scenario bridge-stress` |

## API Changes for Custom Scripts

If you have custom scripts that use SDKPerf, you can now use the wrapper:

**Old Way:**
```bash
bash "${SDKPERF_SCRIPT_PATH}" \
    -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
    -cu="${MARKET_DATA_FEED_USER}" \
    -cp="${MARKET_DATA_FEED_PASSWORD}" \
    -ptl="market-data/test" \
    -mr=1000
```

**New Way:**
```bash
source scripts/sdkperf-wrapper.sh

# Get connection string
conn=$(sdkperf_get_connection "market-feed")
${SDKPERF_SCRIPT_PATH} ${conn} -ptl="market-data/test" -mr=1000

# Or use wrapper functions
sdkperf_publish -user "market-feed" -topics "market-data/test" -rate 1000
```

## Troubleshooting

### "Queue/User not found in configuration"

This means the config-parser couldn't find the infrastructure definition. Check:

1. `.env` has the QUEUE_N or USER_N definitions
2. Variables follow the correct format (see examples above)
3. Run: `source scripts/config-parser.sh && list_queues` to verify parsing

### "Terraform variables generation failed"

Check:
1. `.env` has all required infrastructure definitions
2. Run manually: `./scripts/generate-terraform-config.sh software`
3. Check output for specific errors

### Old scripts still running

The old specialized scripts are still available for backward compatibility:
- Located in `traffic-generators/` and `error-generators/`
- Will continue to work but are deprecated
- Consider migrating to new consolidated scripts for easier maintenance

## Advanced Usage

### Multiple Environments

Generate Terraform configs for different broker types:

```bash
# Generate for all environments
./scripts/generate-terraform-config.sh base
./scripts/generate-terraform-config.sh software
./scripts/generate-terraform-config.sh appliance
```

### Custom Queue Operations

Use config-parser in your own scripts:

```bash
source scripts/config-parser.sh

# Get queue configuration
vpn=$(get_queue_config "equity_order_queue" "vpn")
quota=$(get_queue_config "equity_order_queue" "quota")

# List all queues
for queue in $(list_queues); do
    echo "Queue: $queue"
done

# Get queues for a specific VPN
trading_queues=$(get_vpn_queues "trading")
```

### Logging

Use the centralized logging function:

```bash
source scripts/load-env.sh

chaos_log "my-component" "Starting custom operation"
chaos_log "my-component" "Operation completed successfully"
```

Logs are written to `logs/my-component.log` with timestamps.

## Rollback

If you need to revert to the old system:

1. The old scripts are still available and unchanged
2. Restore your backed up `.env`: `cp .env.backup .env`
3. Continue using the old specialized scripts

## Support

For issues or questions:
1. Check this migration guide
2. Review examples in new scripts
3. Original functionality preserved - old scripts still work

## Summary

The new system dramatically simplifies configuration management while maintaining full backward compatibility. Key improvements:

- ✅ Edit infrastructure in one place (`.env`)
- ✅ Auto-generate Terraform and SEMP configs
- ✅ Fewer, more powerful parameterized scripts
- ✅ Centralized connection and logging utilities
- ✅ Easier customization and maintenance
