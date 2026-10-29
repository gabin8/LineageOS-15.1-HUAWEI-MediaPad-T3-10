/*
 * libshim_camera - AGS-W09 LineageOS 15.1 (camera.msm8937.so + libcamera_huawei_hal3.so)
 *
 * The Huawei camera.msm8937.so was built against a pre-8.1 libgui and calls the
 * no-argument android::DisplayEventReceiver constructor. 8.1 only has
 * DisplayEventReceiver(ISurfaceComposer::VsyncSource), so provide the old symbol
 * and forward with the default source (eVsyncSourceApp == 0).
 */
extern "C" void _ZN7android20DisplayEventReceiverC1ENS_16ISurfaceComposer11VsyncSourceE(
        void* receiver, int vsyncSource);

extern "C" void _ZN7android20DisplayEventReceiverC1Ev(void* receiver) {
    _ZN7android20DisplayEventReceiverC1ENS_16ISurfaceComposer11VsyncSourceE(receiver, 0);
}

/*
 * libcamera_huawei_hal3.so imports isLogEnabled(), which only Huawei's EMUI libcutils
 * exports (stock: "movs r0, #1; bx lr").
 */
extern "C" int isLogEnabled() {
    return 1;
}
