# Solace Broker Type Auto-Detection

## Overview

The chaos testing framework now automatically detects whether it's running against a Software Event Broker or Hardware Appliance, and uses the appropriate Terraform provider.

## How It Works

### 1. **Broker Type Detection**

The system queries the Solace broker's SEMP API (`/SEMP/v2/about`) to determine the platform type:
- **Appliance**: Uses `solaceproducts/solacebrokerappliance` provider
- **Software**: Uses `solaceproducts/solacebroker` provider

Detection runs automatically when loading environment variables via `load-env.sh`.

### 2. **Configuration Options**

In [.env](.env), you can control broker type detection:

```bash
# Broker Type Detection (auto | software | appliance)
SOLACE_BROKER_TYPE=auto    # Auto-detect via SEMP (recommended)
# SOLACE_BROKER_TYPE=software  # Force software broker provider
# SOLACE_BROKER_TYPE=appliance # Force hardware appliance provider
```

### 3. **Terraform Provider Selection**

Based on detected/configured type, the framework automatically uses:

**Software Broker**:
```
terraform/environments/software/
├── main.tf          # Uses solaceproducts/solacebroker
├── variables.tf
└── backend.tf
```

**Hardware Appliance**:
```
terraform/environments/appliance/
├── main.tf          # Uses solaceproducts/solacebrokerappliance
├── variables.tf
└── backend.tf
```

## Usage

### Automatic Detection (Recommended)

1. Configure broker connection in `.env`:
   ```bash
   SOLACE_BROKER_HOST=<broker-ip>
   SOLACE_SEMP_URL=http://<broker-ip>:8080
   SOLACE_BROKER_TYPE=auto
   ```

2. Run bootstrap - detection happens automatically:
   ```bash
   ./scripts/bootstrap-chaos-environment.sh
   ```

3. System will display:
   ```
   ✅ Detected broker type: software
   ✅ Using Terraform config: terraform/environments/software
   ```

### Manual Override

If auto-detection fails or you want explicit control:

**For Software Broker**:
```bash
SOLACE_BROKER_TYPE=software
```

**For Hardware Appliance**:
```bash
SOLACE_BROKER_TYPE=appliance
```

## Requirements

- **Software Broker**: Version 10.4+
- **Hardware Appliance**: Version 10.4+
- **SEMP Access**: Admin credentials with read access to `/SEMP/v2/about`

## Switching Between Broker Types

When testing against different broker types:

1. Update `.env` with new broker connection details
2. Re-run bootstrap:
   ```bash
   ./scripts/bootstrap-chaos-environment.sh
   ```
3. System automatically detects new broker type and uses appropriate provider

## Fallback Behavior

If auto-detection fails (network issues, permissions, etc.):
- ⚠️ System defaults to `software` provider
- ⚡ Logs warning message
- ✅ Continues execution

To diagnose detection issues:
```bash
source scripts/load-env.sh
echo "Detected type: ${DETECTED_BROKER_TYPE}"
```

## Cleanup Operations

Both `terraform-cleanup.sh` and `full-cleanup.sh` automatically use the correct provider:

```bash
# Automatically detects broker type before cleanup
./scripts/terraform-cleanup.sh
```

## Troubleshooting

### Detection Always Returns 'software'

**Possible causes**:
1. SEMP endpoint not accessible
2. Invalid credentials
3. Broker version < 10.4

**Solution**: Use manual override in `.env`:
```bash
SOLACE_BROKER_TYPE=appliance
```

### Provider Version Mismatch

If you see Terraform provider errors:
```bash
cd terraform/environments/<type>
terraform init -upgrade
```

### Testing Detection

Test detection without running bootstrap:
```bash
source scripts/load-env.sh
curl -s -u "${SOLACE_ADMIN_USER}:${SOLACE_ADMIN_PASSWORD}" \
  "${SOLACE_SEMP_URL}/SEMP/v2/about" | grep platform
```

## Architecture

```
.env (SOLACE_BROKER_TYPE=auto)
         ↓
load-env.sh (detect_broker_type())
         ↓
    Query SEMP API
         ↓
   ┌──────────────┐
   │ "appliance"? │
   └──────┬───────┘
          │
    Yes ──┴── No
     │         │
     ↓         ↓
appliance/  software/
main.tf     main.tf
```

## Benefits

✅ **Zero Configuration**: Works automatically for most setups
✅ **Explicit Control**: Manual override when needed
✅ **Platform Agnostic**: Same chaos scripts work on any broker type
✅ **Graceful Fallback**: Safe defaults if detection fails
✅ **Clear Logging**: Always shows which provider is being used
