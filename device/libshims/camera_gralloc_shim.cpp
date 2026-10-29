/*
 * libshim_camera: gralloc handle layout bridge for the stock Huawei (Android 7.0)
 * camera.msm8937.so running on top of our O-era gralloc1 (display-caf/msm8996).
 *
 * The 7.0 HAL reads the gralloc private_handle_t fields directly, using the old
 * (LA.UM.5.x, display-caf/msm8916-style) layout:
 *     +12 fd, +16 fd_metadata, +20 magic, +24 flags, +28 size, +32 offset,
 *     +64 format, +68 width, +72 height
 * Our gralloc.msm8937 (and the O Adreno / libqdMetaData blobs, which must keep
 * it) use the gralloc1 layout where +28/+32 are width/height and size/offset
 * live at +52/+56. Unpatched, QCamera3GrallocMemory::registerBuffer logs
 * "size = 640, offset = 480" for a 640x480 buffer, maps 640 bytes to the
 * daemon, C2D never gets an output buffer (pp_buf_mgr_get_buf: invalid steam
 * info params) and preview stays black; JPEG reads width from +68 (garbage).
 *
 * Fix: hand the HAL a translated copy ("shadow") of every gralloc1 handle in
 * process_capture_request. The 8.1 CameraDeviceSession matches results by
 * (streamId, frameNumber) and ignores the buffer pointer the HAL returns, so
 * nothing needs translating back. setMetaData() calls the HAL makes on a
 * shadow are redirected to the original handle (libqdMetaData is the O blob
 * and expects the gralloc1 layout).
 */
#define LOG_TAG "libshim_camera"

#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <vector>

#include <hardware/camera3.h>
#include <log/log.h>

namespace {

constexpr int kGrallocMagic = 0x676d736d;  // 'gmsm', same in both layouts
constexpr int kNumFds = 2;

// gralloc1 private_handle_t (hardware/qcom/display-caf/msm8996/libgralloc1/gr_priv_handle.h), 32-bit.
struct GrallocHandle {
    int version, numFds, numInts;
    int fd, fd_metadata, magic, flags;
    int width, height, unaligned_width, unaligned_height, format, buffer_type;
    unsigned int size, offset, offset_metadata;
    uint64_t base __attribute__((aligned(8)));
    uint64_t base_metadata __attribute__((aligned(8)));
    uint64_t gpuaddr __attribute__((aligned(8)));
    uint64_t id __attribute__((aligned(8)));
    uint64_t producer_usage __attribute__((aligned(8)));
    uint64_t consumer_usage __attribute__((aligned(8)));
    unsigned int layer_count;
};
static_assert(offsetof(GrallocHandle, width) == 28, "gralloc1 layout");
static_assert(offsetof(GrallocHandle, size) == 52, "gralloc1 layout");
static_assert(offsetof(GrallocHandle, base) == 64, "gralloc1 layout");
static_assert(sizeof(GrallocHandle) == 120, "gralloc1 layout");
constexpr int kGrallocNumInts = (sizeof(GrallocHandle) - 3 * sizeof(int)) / sizeof(int) - kNumFds;  // 25

// Legacy private_handle_t the 7.0 camera blobs were built against, 32-bit.
struct LegacyHandle {
    int version, numFds, numInts;
    int fd, fd_metadata, magic, flags;
    unsigned int size, offset;
    int bufferType;
    uint64_t base __attribute__((aligned(8)));
    unsigned int offset_metadata;
    uint64_t gpuaddr __attribute__((aligned(8)));
    int format, width, height;
    uint64_t base_metadata __attribute__((aligned(8)));
    int unaligned_width, unaligned_height;
};
// Offsets verified against camera.msm8937.so (registerBuffer: +12/+28/+32, jpegEvtHandle: +68).
static_assert(offsetof(LegacyHandle, size) == 28, "legacy layout");
static_assert(offsetof(LegacyHandle, offset) == 32, "legacy layout");
static_assert(offsetof(LegacyHandle, format) == 64, "legacy layout");
static_assert(offsetof(LegacyHandle, width) == 68, "legacy layout");
static_assert(offsetof(LegacyHandle, base_metadata) == 80, "legacy layout");
// numInts deliberately != 25 so the O libqdMetaData rejects a shadow if one ever leaks to it.
constexpr int kLegacyNumInts = (sizeof(LegacyHandle) - 3 * sizeof(int)) / sizeof(int) - kNumFds;  // 19

struct Shadow {
    LegacyHandle h;
    buffer_handle_t handle;           // == &h; the HAL receives &handle
    void* hwi;                        // owning QCamera3HardwareInterface
    buffer_handle_t* slot;            // session's buffer_handle_t* for this buffer
    const GrallocHandle* orig;
};

pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;
std::vector<Shadow*> gShadows;
std::vector<Shadow*> gRetired;  // freed one configure_streams later

bool isGralloc1(const native_handle_t* nh) {
    const GrallocHandle* g = reinterpret_cast<const GrallocHandle*>(nh);
    return g && g->version == (int)sizeof(native_handle_t) && g->numFds == kNumFds &&
            g->numInts == kGrallocNumInts && g->magic == kGrallocMagic;
}

bool matches(const Shadow* s, const GrallocHandle* g) {
    return s->orig == g && s->h.fd == g->fd && s->h.fd_metadata == g->fd_metadata &&
            s->h.size == g->size && s->h.offset == g->offset && s->h.width == g->width &&
            s->h.height == g->height && s->h.format == g->format;
}

void translate(LegacyHandle* l, const GrallocHandle* g) {
    memset(l, 0, sizeof(*l));
    l->version = sizeof(native_handle_t);
    l->numFds = kNumFds;
    l->numInts = kLegacyNumInts;
    l->fd = g->fd;
    l->fd_metadata = g->fd_metadata;
    l->magic = g->magic;
    l->flags = g->flags;
    l->size = g->size;
    l->offset = g->offset;
    l->bufferType = g->buffer_type;
    l->base = g->base;
    l->offset_metadata = g->offset_metadata;
    l->gpuaddr = g->gpuaddr;
    l->format = g->format;
    l->width = g->width;
    l->height = g->height;
    l->base_metadata = g->base_metadata;
    l->unaligned_width = g->unaligned_width;
    l->unaligned_height = g->unaligned_height;
}

buffer_handle_t* shadowFor(void* hwi, buffer_handle_t* slot) {
    if (!slot || !*slot || !isGralloc1(*slot)) return slot;
    const GrallocHandle* g = reinterpret_cast<const GrallocHandle*>(*slot);
    pthread_mutex_lock(&gLock);
    for (Shadow* s : gShadows) {
        if (s->hwi == hwi && s->slot == slot && matches(s, g)) {
            pthread_mutex_unlock(&gLock);
            return &s->handle;
        }
    }
    Shadow* s = new Shadow();
    translate(&s->h, g);
    s->handle = reinterpret_cast<buffer_handle_t>(&s->h);
    s->hwi = hwi;
    s->slot = slot;
    s->orig = g;
    gShadows.push_back(s);
    pthread_mutex_unlock(&gLock);
    ALOGV("shadow %p for handle %p fd %d size %u %dx%d fmt %#x", s, g, g->fd, g->size,
            g->width, g->height, g->format);
    return &s->handle;
}

// Called before the HAL tears down its channels for a new stream configuration;
// buffers registered for the previous configuration are dropped by the HAL then.
void retireShadows(void* hwi) {
    pthread_mutex_lock(&gLock);
    for (Shadow* s : gRetired) delete s;
    gRetired.clear();
    for (auto it = gShadows.begin(); it != gShadows.end();) {
        if ((*it)->hwi == hwi) {
            gRetired.push_back(*it);
            it = gShadows.erase(it);
        } else {
            ++it;
        }
    }
    pthread_mutex_unlock(&gLock);
}

const GrallocHandle* originalFor(const void* handle) {
    const GrallocHandle* orig = nullptr;
    pthread_mutex_lock(&gLock);
    for (const auto* list : {&gShadows, &gRetired}) {
        for (Shadow* s : *list) {
            if (&s->h == handle) {
                orig = s->orig;
                break;
            }
        }
        if (orig) break;
    }
    pthread_mutex_unlock(&gLock);
    return orig;
}

void* halSym(const char* name) {
    void* lib = dlopen("/vendor/lib/hw/camera.msm8937.so", RTLD_NOW | RTLD_NOLOAD);
    if (!lib) lib = dlopen("camera.msm8937.so", RTLD_NOW | RTLD_NOLOAD);
    void* sym = lib ? dlsym(lib, name) : nullptr;
    if (!sym) ALOGE("cannot resolve %s in camera.msm8937.so: %s", name, dlerror());
    return sym;
}

typedef int (*set_meta_t)(void*, int, void*);
set_meta_t realSetMetaData() {
    static set_meta_t fn = nullptr;
    if (!fn) {
        void* lib = dlopen("libqdMetaData.so", RTLD_NOW);
        fn = lib ? reinterpret_cast<set_meta_t>(dlsym(lib, "setMetaData")) : nullptr;
        if (!fn) ALOGE("cannot resolve setMetaData: %s", dlerror());
    }
    return fn;
}

}  // namespace

// int QCamera3HardwareInterface::processCaptureRequest(camera3_capture_request_t*)
extern "C" int _ZN7qcamera25QCamera3HardwareInterface21processCaptureRequestEP23camera3_capture_request(
        void* hwi, camera3_capture_request_t* request) {
    typedef int (*fn_t)(void*, camera3_capture_request_t*);
    static fn_t real = reinterpret_cast<fn_t>(halSym(
            "_ZN7qcamera25QCamera3HardwareInterface21processCaptureRequestEP23camera3_capture_request"));
    if (!real) return -ENODEV;
    if (!request) return real(hwi, request);

    camera3_capture_request_t copy = *request;
    std::vector<camera3_stream_buffer_t> outputs;
    if (request->output_buffers && request->num_output_buffers) {
        outputs.assign(request->output_buffers,
                request->output_buffers + request->num_output_buffers);
        for (auto& b : outputs) b.buffer = shadowFor(hwi, b.buffer);
        copy.output_buffers = outputs.data();
    }
    camera3_stream_buffer_t input;
    if (request->input_buffer) {
        input = *request->input_buffer;
        input.buffer = shadowFor(hwi, input.buffer);
        copy.input_buffer = &input;
    }
    return real(hwi, &copy);
}

// int QCamera3HardwareInterface::configureStreams(camera3_stream_configuration_t*)
extern "C" int _ZN7qcamera25QCamera3HardwareInterface16configureStreamsEP28camera3_stream_configuration(
        void* hwi, camera3_stream_configuration_t* config) {
    typedef int (*fn_t)(void*, camera3_stream_configuration_t*);
    static fn_t real = reinterpret_cast<fn_t>(halSym(
            "_ZN7qcamera25QCamera3HardwareInterface16configureStreamsEP28camera3_stream_configuration"));
    if (!real) return -ENODEV;
    retireShadows(hwi);
    return real(hwi, config);
}

// libqdMetaData: int setMetaData(private_handle_t*, DispParamType, void*)
extern "C" int setMetaData(void* handle, int paramType, void* param) {
    set_meta_t real = realSetMetaData();
    if (!real) return -EINVAL;
    const GrallocHandle* orig = originalFor(handle);
    return real(orig ? const_cast<GrallocHandle*>(orig) : handle, paramType, param);
}
