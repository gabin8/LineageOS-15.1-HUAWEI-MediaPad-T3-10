# CAF liblight (hardware/qcom/display/msm8996/liblight), built for this device in
# place of the Huawei lights.msm8937.so blob, which usleep()s inside setLight and
# stalls BatteryService -> PowerManagerService -> input dispatch for ~4 s.
LOCAL_PATH:= $(call my-dir)
include $(CLEAR_VARS)

LOCAL_SRC_FILES := lights.c
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_PROPRIETARY_MODULE := true
LOCAL_SHARED_LIBRARIES := liblog
LOCAL_CFLAGS := -DLOG_TAG=\"qdlights\"
LOCAL_CLANG  := true
LOCAL_MODULE := lights.$(TARGET_BOARD_PLATFORM)
LOCAL_MODULE_TAGS := optional

include $(BUILD_SHARED_LIBRARY)
