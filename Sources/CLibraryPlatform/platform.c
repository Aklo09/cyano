#include "CLibraryPlatform.h"
#include <sys/file.h>
#include <libproc.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

/* Avoid the Swift name collision between flock(2) and struct flock. */
int fb_library_flock(int descriptor, int operation) {
    return flock(descriptor, operation);
}

unsigned long long fb_process_resident_bytes(int pid) {
    struct proc_taskinfo info;
    int count = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, sizeof(info));
    return count == sizeof(info) ? info.pti_resident_size : 0;
}

/* Explicit allowlists: the worker receives stdin, stdout, and stderr only, and an empty environment. */
int fb_spawn_preview(const char *path, int input, int output, int errors, int *pid) {
    int originals[3] = {input, output, errors};
    int copies[3] = {-1, -1, -1};
    int result = 0;
    for (int i = 0; i < 3; i++) {
        copies[i] = fcntl(originals[i], F_DUPFD_CLOEXEC, 10);
        if (copies[i] < 0) { result = errno; goto close_copies; }
    }
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    result = posix_spawn_file_actions_init(&actions);
    if (result) goto close_copies;
    result = posix_spawnattr_init(&attributes);
    if (result) { posix_spawn_file_actions_destroy(&actions); goto close_copies; }
    for (int i = 0; i < 3 && !result; i++) {
        result = posix_spawn_file_actions_adddup2(&actions, copies[i], i);
    }
    if (!result) result = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP);
    if (!result) result = posix_spawnattr_setpgroup(&attributes, 0);
    if (!result) {
        char *arguments[] = {(char *)path, NULL};
        char *environment[] = {NULL};
        pid_t child;
        result = posix_spawn(&child, path, &actions, &attributes, arguments, environment);
        if (!result) *pid = child;
    }
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
close_copies:
    for (int i = 0; i < 3; i++) if (copies[i] >= 0) close(copies[i]);
    return result;
}

/* Poll without reaping: reserve the leader PID until its entire process group is stopped. */
int fb_wait_preview(int pid, int nonblocking, int *exit_code) {
    if (nonblocking) {
        siginfo_t info = {0};
        int result;
        do { result = waitid(P_PID, (id_t)pid, &info, WEXITED | WNOHANG | WNOWAIT); } while (result < 0 && errno == EINTR);
        if (result < 0) return -errno;
        if (info.si_pid == 0) return 0;
        *exit_code = info.si_code == CLD_EXITED ? info.si_status : -1;
        return 1;
    }
    int status;
    pid_t result;
    do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
    if (result < 0) return -errno;
    if (result == 0) return 0;
    *exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    return 1;
}
