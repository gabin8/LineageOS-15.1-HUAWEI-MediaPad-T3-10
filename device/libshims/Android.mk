LOCAL_PATH := $(call my-dir)

# Huawei libizat_core.so (sensors HAL dependency): get_process_name()
include $(CLEAR_VARS)
LOCAL_SRC_FILES := procname_shim.c
LOCAL_MODULE := libshim_procname
LOCAL_MODULE_TAGS := optional
LOCAL_PROPRIETARY_MODULE := true
include $(BUILD_SHARED_LIBRARY)
