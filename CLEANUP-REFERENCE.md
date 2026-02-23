# Cleanup Scripts Reference

## Overview
Three different cleanup scripts for different scenarios:

## 📋 Cleanup Scripts Summary

| Script | Speed | Scope | Safety | Use Case |
|--------|-------|-------|--------|----------|
| `quick-cleanup.sh` | ⚡ Fast | Processes only | 🟢 Safe | Routine restarts |
| `full-cleanup.sh` | 🐌 Interactive | Everything | 🟡 Prompted | Complete reset |
| `semp-provision.sh destroy` | ⚡ Fast | SEMP resources only | 🔴 Destructive | Infrastructure reset |

---

## 🚀 Quick Cleanup
```bash
./scripts/quick-cleanup.sh
```
**What it does:**
- ✅ Stops all chaos processes  
- ✅ Removes PID files and locks
- ✅ Preserves all configuration and logs
- ✅ Preserves broker infrastructure

**Use when:** You want to restart quickly without losing anything

---

## 🔧 Full Cleanup (Interactive)
```bash
./scripts/full-cleanup.sh
```
**What it does:**
- ✅ Stops all chaos processes
- 🟡 Optionally backs up and cleans logs
- 🟡 Optionally cleans SDKPerf extracted files
- 🟡 Optionally resets .env to template defaults
- 🟡 Optionally destroys SEMP-provisioned broker resources

**Features:**
- Interactive prompts for each action
- Automatic backups before deletion
- Multiple safety confirmations
- Comprehensive environment reset

**Use when:** You want complete control over what gets cleaned

---

## 💥 SEMP Infrastructure Cleanup
```bash
./scripts/semp-provision.sh destroy
```
**What it does:**
- 🔴 **DESTROYS ALL SEMP-PROVISIONED RESOURCES**
- Shows what will be deleted before proceeding
- Multiple confirmation prompts
- Preserves local files and processes

**⚠️ DESTROYS:**
- All VPNs (except default)
- All queues and their messages
- All user accounts (except admin)
- All ACL profiles
- All client profiles
- All bridges
- All queue subscriptions

**Use when:** You want to reset broker infrastructure only

---

## 🔄 Typical Workflows

### Quick Restart
```bash
./scripts/quick-cleanup.sh
bash run-chaos.sh &
# Or use wrapper
./chaos.sh start
```

### Complete Environment Reset
```bash
./scripts/full-cleanup.sh
# Follow prompts for what you want to clean
./scripts/bootstrap-chaos-environment.sh  # If you cleaned everything
```

### Infrastructure Reset Only
```bash
./scripts/semp-provision.sh destroy
./scripts/semp-provision.sh create
bash run-chaos.sh &
```

### Partial Reset (Keep Processes Running)
```bash
./scripts/semp-provision.sh destroy
./scripts/semp-provision.sh create
# Processes continue running with new infrastructure
```

---

## 🛡️ Safety Features

All cleanup scripts include:
- ✅ Automatic backups with timestamps
- ✅ Clear logging of all actions
- ✅ Graceful process termination (SIGTERM then SIGKILL)
- ✅ Interrupt handling (Ctrl+C safety)
- ✅ Non-destructive defaults

**SEMP infrastructure cleanup specifically:**
- 🔴 Shows what will be deleted before proceeding
- 🔴 Requires explicit confirmation
- 🔴 Cannot be run accidentally
- 🔴 Uses Solace SEMP API for clean removal

---

## 📁 Backup Locations

| Item | Backup Location |
|------|-----------------|
| Logs | `log-backups/YYYYMMDD_HHMMSS/` |
| .env files | `.env.backup.YYYYMMDD_HHMMSS` |


All timestamps in local timezone.