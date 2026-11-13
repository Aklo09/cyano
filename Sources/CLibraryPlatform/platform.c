#include "CLibraryPlatform.h"
#include <sys/file.h>
#include <libproc.h>

/* Avoid the Swift name collision between flock(2) and struct flock. */
int fb_library_flock(int descriptor, int operation) {
    return flock(descriptor, operation);
}

unsigned long long fb_process_resident_bytes(int pid) {
    struct proc_taskinfo info;
    int count = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, sizeof(info));
    return count == sizeof(info) ? info.pti_resident_size : 0;
}
