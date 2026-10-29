/*
 * libshim_camera: disable the stock 7.0 HAL1 path (QCamera2HardwareInterface).
 *
 * On 8.1 the HAL1 path cannot work with this blob:
 *  - QCameraGrallocMemory::allocate passes its own object as the get_memory
 *    cookie; 8.1's camera.device@1.0-impl casts it to CameraDevice* and the
 *    provider dies with SIGSEGV in CameraDevice::sGetMemory (cameraserver then
 *    aborts on DEAD_OBJECT);
 *  - its preview-window buffers would also need the gralloc layout bridge.
 * Failing the HAL1 open makes QCamera2Factory::openLegacy return -ENODEV, so the
 * 2.4 provider does not advertise device@1.0. Camera.openLegacy() then fails
 * cleanly and Snap falls back to Camera.open() (API1 on HAL3 via Camera2Client),
 * and the provider no longer spends ~8 s per camera probing HAL1 at start.
 *
 * setprop persist.camera.shim.hal1 1 (and restart the provider) re-enables it.
 */
#define LOG_TAG "libshim_camera"

#include <dlfcn.h>
#include <errno.h>

#include <cutils/properties.h>
#include <hardware/hardware.h>
#include <log/log.h>

// int QCamera2HardwareInterface::openCamera(hw_device_t**)
extern "C" int _ZN7qcamera25QCamera2HardwareInterface10openCameraEPP11hw_device_t(
        void* hwi, hw_device_t** device) {
    if (property_get_bool("persist.camera.shim.hal1", false)) {
        typedef int (*fn_t)(void*, hw_device_t**);
        static fn_t real = nullptr;
        if (!real) {
            void* lib = dlopen("/vendor/lib/hw/camera.msm8937.so", RTLD_NOW | RTLD_NOLOAD);
            real = lib ? reinterpret_cast<fn_t>(dlsym(lib,
                    "_ZN7qcamera25QCamera2HardwareInterface10openCameraEPP11hw_device_t")) : nullptr;
        }
        if (real) return real(hwi, device);
    }
    ALOGI("HAL1 open refused (incompatible with 8.1 device@1.0 wrapper); use HAL3");
    if (device) *device = nullptr;
    return -ENODEV;
}
