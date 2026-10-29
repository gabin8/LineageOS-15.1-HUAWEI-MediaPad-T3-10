/*
 * libshim_procname.so - AGS-W09 LineageOS 15.1
 *
 * get_process_name() was dropped from libcutils in Android O, but the Huawei
 * A8.0-era /vendor/lib{,64}/libizat_core.so still imports it. libizat_core is
 * pulled in by sensors.ssc.so -> liblocationservice.so, so without this symbol
 * the multihal's dlopen("sensors.ssc.so") fails and the device exposes no
 * sensors at all (no accelerometer -> no auto-rotate).
 *
 * Old libcutils (process_name.c) returned "unknown" unless set_process_name()
 * had been called, which nothing does any more - so do exactly that.
 * No libc dependency on purpose: the lib has no DT_NEEDED entries.
 */
__attribute__((visibility("default")))
const char *get_process_name(void)
{
    return "unknown";
}

__attribute__((visibility("default")))
void set_process_name(const char *name)
{
    (void)name;
}
