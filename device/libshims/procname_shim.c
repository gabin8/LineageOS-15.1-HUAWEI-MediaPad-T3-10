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
