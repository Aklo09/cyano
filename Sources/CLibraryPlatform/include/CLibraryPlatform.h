#ifndef FB_NATIVE_LIBRARY_PLATFORM_H
#define FB_NATIVE_LIBRARY_PLATFORM_H
int fb_library_flock(int descriptor, int operation);
unsigned long long fb_process_resident_bytes(int pid);
#endif
