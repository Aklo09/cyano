#include "CLibraryPlatform.h"
#include <sys/file.h>

/* Avoid the Swift name collision between flock(2) and struct flock. */
int fb_library_flock(int descriptor, int operation) {
    return flock(descriptor, operation);
}
