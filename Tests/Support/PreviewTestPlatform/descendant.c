#include "PreviewTestPlatform.h"
#include <crt_externs.h>
#include <fcntl.h>
#include <spawn.h>
#include <unistd.h>

int fb_test_spawn_descendant(const char *executable, int *pid) {
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int result = posix_spawn_file_actions_init(&actions);
    if (result) return result;
    result = posix_spawnattr_init(&attributes);
    if (result) { posix_spawn_file_actions_destroy(&actions); return result; }
    if (!result) result = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT);
    if (!result) result = posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0600);
    if (!result) result = posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0600);
    if (!result) {
        char *arguments[] = {(char *)executable, "descendant-holder", NULL};
        pid_t child;
        /* No SETPGROUP: this descendant remains in the worker's supervised process group. */
        result = posix_spawn(&child, executable, &actions, &attributes, arguments, *_NSGetEnviron());
        if (!result) *pid = child;
    }
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    return result;
}
