#!/bin/bash
source scripts/load-env.sh

while true; do
    echo "$(date): Testing ACL violations across all VPNs (optimized single process with multi-flow)"
    
    # Single process testing multiple ACL violations with publisher flows
    # Tests: premium market data access, admin functions, and cross-VPN access
    bash "${SDKPERF_SCRIPT_PATH}" \
        -cip="${SOLACE_BROKER_HOST}:${SOLACE_BROKER_PORT}" \
        -cu="${RESTRICTED_MARKET_USER}" \
        -cp="${RESTRICTED_MARKET_PASSWORD}" \
        -ptl="market-data/premium/level3/NYSE/AAPL,trading/admin/cancel-all-orders,trading/orders/equities/NYSE/new" \
        -pfl=3 \
        -mr=1 -mn=999999999 -msa=256 >> logs/acl-violator.log 2>&1 &
    
    ACL_PID=$!
    
    # Let run for 1 hour, then restart
    sleep 3600
    kill $ACL_PID 2>/dev/null
    echo "$(date): ACL violation test cycle completed - restarting"
done
