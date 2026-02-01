# Cleanup Scripts Reference

## Overview
Three different cleanup scripts for different scenarios:

## 📋 Cleanup Scripts Summary

| Script | Speed | Scope | Safety | Use Case |
|--------|-------|-------|--------|----------|
| `quick-cleanup.sh` | ⚡ Fast | Processes only | 🟢 Safe | Routine restarts |
| `full-cleanup.sh` | 🐌 Interactive | Everything | 🟡 Prompted | Complete reset |
| `terraform-cleanup.sh` | ⚡ Fast | Terraform only | 🔴 Destructive | Infrastructure reset |

---

## 🚀 Quick Cleanup
```bash
./quick-cleanup.sh
```
**What it does:**
- ✅ Stops all chaos processes (via daemon)  
- ✅ Removes PID files and locks
- ✅ Preserves all configuration and logs
- ✅ Preserves Terraform infrastructure

**Use when:** You want to restart quickly without losing anything

---

## 🔧 Full Cleanup (Interactive)
```bash
./full-cleanup.sh
```
**What it does:**
- ✅ Stops all chaos processes
- 🟡 Optionally backs up and cleans logs
- 🟡 Optionally cleans SDKPerf extracted files
- 🟡 Optionally resets .env to template defaults
- 🟡 Optionally destroys Terraform resources

**Features:**
- Interactive prompts for each action
- Automatic backups before deletion
- Multiple safety confirmations
- Comprehensive environment reset

**Use when:** You want complete control over what gets cleaned

---

## 💥 Terraform Cleanup (Infrastructure)
```bash
./terraform-cleanup.sh
```
**What it does:**
- 🔴 **DESTROYS ALL TERRAFORM RESOURCES**
- Shows destruction plan before proceeding
- Multiple confirmation prompts
- Backs up Terraform state files
- Preserves local files and processes

**⚠️ DESTROYS:**
- All VPNs (except default)
- All queues and their messages
- All user accounts (except admin)
- All ACL profiles
- All queue subscriptions

**Use when:** You want to reset broker infrastructure only

---

## 🔄 Typical Workflows

### Quick Restart
```bash
./quick-cleanup.sh
./chaos-daemon.sh start
```

### Complete Environment Reset
```bash
./full-cleanup.sh
# Follow prompts for what you want to clean
./bootstrap-chaos-environment.sh  # If you cleaned everything
```

### Infrastructure Reset Only
```bash
./terraform-cleanup.sh
cd terraform/environments/base && terraform apply
./chaos-daemon.sh restart
```

### Partial Reset (Keep Processes Running)
```bash
cd terraform/environments/base
terraform destroy -auto-approve
terraform apply -auto-approve
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

**Terraform cleanup specifically:**
- 🔴 Shows destruction plan before proceeding
- 🔴 Requires two separate confirmations
- 🔴 Cannot be run accidentally
- 🔴 Always backs up state files

---

## 📁 Backup Locations

| Item | Backup Location |
|------|-----------------|
| Logs | `log-backups/YYYYMMDD_HHMMSS/` |
| .env files | `.env.backup.YYYYMMDD_HHMMSS` |
| Terraform state | `terraform-backups/YYYYMMDD_HHMMSS/` |

All timestamps in local timezone.