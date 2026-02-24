#!/bin/bash
# emergency-log-cleanup.sh - Clean up massive log files immediately
# Use this when logs have grown to multi-GB sizes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Configuration
MAX_SIZE_MB="${LOG_MAX_SIZE_MB:-50}"
MAX_SIZE_BYTES=$((MAX_SIZE_MB * 1024 * 1024))
EMERGENCY_THRESHOLD_GB=1
EMERGENCY_THRESHOLD_BYTES=$((EMERGENCY_THRESHOLD_GB * 1024 * 1024 * 1024))

echo "=========================================="
echo "Emergency Log Cleanup"
echo "=========================================="
echo "Max size threshold: ${MAX_SIZE_MB}MB"
echo "Emergency threshold: ${EMERGENCY_THRESHOLD_GB}GB"
echo ""

# Function to get file size (cross-platform)
get_file_size() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f%z "$file" 2>/dev/null || echo "0"
    else
        stat -c%s "$file" 2>/dev/null || echo "0"
    fi
}

# Function to format bytes
format_bytes() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        echo "$((bytes / 1073741824))GB"
    else
        echo "$((bytes / 1048576))MB"
    fi
}

# Check all log files
total_cleaned=0
total_space_freed=0

echo "Scanning logs/ directory..."
echo ""

for log_file in logs/*.log; do
    [[ ! -f "$log_file" ]] && continue
    
    file_size=$(get_file_size "$log_file")
    
    if (( file_size > MAX_SIZE_BYTES )); then
        file_size_formatted=$(format_bytes "$file_size")
        echo "Found oversized log: $log_file ($file_size_formatted)"
        
        # For emergency-sized files (>1GB), truncate aggressively
        if (( file_size > EMERGENCY_THRESHOLD_BYTES )); then
            echo "  ⚠️  EMERGENCY SIZE! Truncating to marker only..."
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Log exceeded ${file_size_formatted} and was emergency truncated" > "$log_file"
            total_space_freed=$((total_space_freed + file_size))
            total_cleaned=$((total_cleaned + 1))
            echo "  ✅ Truncated to ~100 bytes"
        else
            # For large but not emergency files, keep last 1000 lines
            echo "  Keeping last 1000 lines..."
            if tail -n 1000 "$log_file" > "${log_file}.tmp" 2>/dev/null; then
                mv "${log_file}.tmp" "$log_file"
                new_size=$(get_file_size "$log_file")
                space_freed=$((file_size - new_size))
                total_space_freed=$((total_space_freed + space_freed))
                total_cleaned=$((total_cleaned + 1))
                echo "  ✅ Reduced from ${file_size_formatted} to $(format_bytes "$new_size")"
            else
                echo "  ❌ Failed to process, truncating..."
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Processing failed, truncated" > "$log_file"
                total_space_freed=$((total_space_freed + file_size))
                total_cleaned=$((total_cleaned + 1))
            fi
        fi
        echo ""
    fi
done

echo "=========================================="
echo "Cleanup Summary"
echo "=========================================="
echo "Files cleaned: $total_cleaned"
echo "Space freed: $(format_bytes "$total_space_freed")"
echo ""

if (( total_cleaned == 0 )); then
    echo "✅ No oversized log files found"
else
    echo "✅ Emergency cleanup completed"
    echo ""
    echo "Current log sizes:"
    if command -v du &> /dev/null; then
        du -sh logs/*.log 2>/dev/null | sort -h || ls -lh logs/*.log
    else
        ls -lh logs/*.log
    fi
fi
