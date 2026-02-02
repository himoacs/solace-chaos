#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Testing ACL violations across all VPNs"
    
    # Try to access premium market data with restricted user
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="market-data/premium/level3/NYSE/AAPL" \
        -mr=5 -mn=50 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    # Try to access admin trading functions with restricted user
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_TRADE_USER}" \
        -cp="${RESTRICTED_TRADE_PASSWORD}" \
        -ptl="trading/admin/cancel-all-orders" \
        -mr=5 -mn=50 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    # Try cross-VPN access without proper permissions
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="trading/orders/equity/NYSE/new" \
        -mr=5 -mn=50 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    wait
    echo "$(date): Multi-VPN ACL violation tests completed - waiting 90 seconds"
    sleep 90
done
