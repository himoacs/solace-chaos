#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Testing ACL violations across all VPNs"
    
    # Try to access premium market data with restricted user (gentle continuous)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="market-data/premium/level3/NYSE/AAPL" \
        -mr=1 -mn=999999999 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    # Try to access admin trading functions with restricted user (gentle continuous)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_TRADE_USER}" \
        -cp="${RESTRICTED_TRADE_PASSWORD}" \
        -ptl="trading/admin/cancel-all-orders" \
        -mr=1 -mn=999999999 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    # Try cross-VPN access without proper permissions (gentle continuous)
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="trading/orders/equities/NYSE/new" \
        -mr=1 -mn=999999999 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    # Let run for 1 hour, then restart
    sleep 3600
    pkill -f "premium/level3\|admin/cancel-all-orders" 2>/dev/null
    echo "$(date): ACL violation test cycle completed - restarting"
done
