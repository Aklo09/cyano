#ifndef FB_NATIVE_LIBRARY_PLATFORM_H
#define FB_NATIVE_LIBRARY_PLATFORM_H
int fb_library_flock(int descriptor, int operation);
unsigned long long fb_process_resident_bytes(int pid);
int fb_spawn_preview(const char *path, int input, int output, int errors, int lease, int *pid);
int fb_wait_preview(int pid, int nonblocking, int *exit_code);
#endif
