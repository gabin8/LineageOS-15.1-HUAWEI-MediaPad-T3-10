LOCAL_PATH := $(call my-dir)

# Huawei camera.msm8937.so: pre-8.1 DisplayEventReceiver() constructor
include $(CLEAR_VARS)
LOCAL_SRC_FILES := camera_shim.cpp
LOCAL_SHARED_LIBRARIES := libgui libsensor
LOCAL_MODULE := libshim_camera
LOCAL_MODULE_TAGS := optional
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MULTILIB := 32
include $(BUILD_SHARED_LIBRARY)

# Huawei libizat_core.so (sensors HAL dependency): get_process_name()
include $(CLEAR_VARS)
LOCAL_SRC_FILES := procname_shim.c
LOCAL_MODULE := libshim_procname
LOCAL_MODULE_TAGS := optional
LOCAL_PROPRIETARY_MODULE := true
include $(BUILD_SHARED_LIBRARY)
