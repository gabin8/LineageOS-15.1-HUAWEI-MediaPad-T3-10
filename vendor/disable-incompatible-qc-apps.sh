#!/bin/sh
# After the qcom_diag fix lets these QC uid-1000 apps start, they crash on A7-era vendor libraries
# that reference symbols absent in 8.1 (e.g. libizat_core.so needs get_process_name). Because they
# run in the system process, their crash takes down system_server (lock-screen<->bootanim loop).
# They are not needed for basic operation (GNSS is served by a stub HAL). Disable them.
# Permanent fix: remove these from PRODUCT_PACKAGES.
for p in com.qualcomm.location com.quicinc.cne.CNEService com.qti.dpmserviceapp \
         com.qti.service.colorservice com.qualcomm.svi com.qualcomm.cabl com.qualcomm.qti.tetherservice com.qualcomm.qcrilmsgtunnel; do
  pm disable "$p" 2>/dev/null
done
echo "incompatible QC apps disabled"
