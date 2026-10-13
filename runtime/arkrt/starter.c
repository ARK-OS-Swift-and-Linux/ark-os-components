#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

static volatile sig_atomic_t g_reap_children = 0;
static volatile sig_atomic_t g_shutdown_requested = 0;

static void sigchld_handler(int sig) {
    (void)sig;
    g_reap_children = 1;
}

static void sigterm_handler(int sig) {
    (void)sig;
    g_shutdown_requested = 1;
}

static void mount_or_warn(const char *source, const char *target, const char *fstype, unsigned long flags, const void *data) {
    mkdir(target, 0755);
    if (mount(source, target, fstype, flags, data) != 0) {
        if (errno != EBUSY) {
            fprintf(stderr, "[arkrt] Warning: Failed to mount %s (%s): %s (errno %d)\n",
                    target, fstype, strerror(errno), errno);
        }
    }
}

int main(int argc, char *argv[], char *envp[]) {
    (void)argc;
    (void)argv;

    pid_t my_pid = getpid();
    if (my_pid != 1) {
        fprintf(stderr, "[arkrt] Fatal: Process is running as PID %d, expected PID 1.\n", (int)my_pid);
        return 1;
    }

    /* 1. Mount /dev first so device nodes are available */
    mkdir("/dev", 0755);
    if (mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755") != 0 && errno != EBUSY) {
        /* devtmpfs may not be built-in or already mounted */
    }

    /* 2. Set up standard I/O streams to /dev/console */
    int console_fd = open("/dev/console", O_RDWR);
    if (console_fd < 0) {
        console_fd = open("/dev/ttyS0", O_RDWR);
    }
    if (console_fd >= 0) {
        dup2(console_fd, STDIN_FILENO);
        dup2(console_fd, STDOUT_FILENO);
        dup2(console_fd, STDERR_FILENO);
        if (console_fd > STDERR_FILENO) {
            close(console_fd);
        }
    }

    printf("[arkrt] ARK-OS PID 1 C starter initializing (PID: %d)...\n", (int)my_pid);
    fflush(stdout);

    /* 3. Mount remaining essential pseudo-filesystems */
    mount_or_warn("proc", "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
    mount_or_warn("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
    mount_or_warn("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755");

    mkdir("/dev/pts", 0755);
    mount_or_warn("devpts", "/dev/pts", "devpts", MS_NOSUID | MS_NOEXEC, "gid=5,mode=620");

    mkdir("/dev/shm", 1777);
    mount_or_warn("tmpfs", "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");

    printf("[arkrt] Virtual filesystems mounted: /dev, /proc, /sys, /run, /dev/pts, /dev/shm.\n");
    fflush(stdout);

    /* 4. Locate and hand off to Swift main runtime */
    const char *swift_bin = "/sbin/arkrt-swift";
    if (access(swift_bin, X_OK) == 0) {
        printf("[arkrt] Handing off control to Swift main runtime (%s)...\n", swift_bin);
        fflush(stdout);

        char *new_argv[] = { (char *)swift_bin, NULL };
        execve(swift_bin, new_argv, envp);

        /* If execve returns, handoff failed! Report exact cause */
        fprintf(stderr, "[arkrt] Error: execve(%s) failed: %s (errno %d)\n",
                swift_bin, strerror(errno), errno);
    } else {
        printf("[arkrt] Notice: Swift runtime (%s) not found (%s).\n",
               swift_bin, strerror(errno));
    }

    /* 5. Fallback Mode: Maintain PID 1 supervisory responsibilities in C */
    fprintf(stderr, "[arkrt] ========================================================\n");
    fprintf(stderr, "[arkrt] SYSTEM IN FALLBACK MODE: Running C starter supervisor\n");
    fprintf(stderr, "[arkrt] Swift runtime failed or absent; PID 1 remaining in C starter\n");
    fprintf(stderr, "[arkrt] ========================================================\n");
    fflush(stderr);

    struct sigaction sa_chld;
    memset(&sa_chld, 0, sizeof(sa_chld));
    sa_chld.sa_handler = sigchld_handler;
    sa_chld.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    sigaction(SIGCHLD, &sa_chld, NULL);

    struct sigaction sa_term;
    memset(&sa_term, 0, sizeof(sa_term));
    sa_term.sa_handler = sigterm_handler;
    sa_term.sa_flags = SA_RESTART;
    sigaction(SIGTERM, &sa_term, NULL);
    sigaction(SIGINT, &sa_term, NULL);

    printf("[arkrt-fallback] Supervisor active. Entering event loop.\n");
    fflush(stdout);

    while (!g_shutdown_requested) {
        pause();

        if (g_reap_children) {
            g_reap_children = 0;
            pid_t child_pid;
            int child_status;
            while ((child_pid = waitpid(-1, &child_status, WNOHANG)) > 0) {
                char msg[128];
                int len = snprintf(msg, sizeof(msg), "[arkrt-fallback] Reaped child process (PID: %d)\n", (int)child_pid);
                if (len > 0) {
                    write(STDOUT_FILENO, msg, len);
                }
            }
        }
    }

    printf("[arkrt-fallback] Shutdown requested. Halting PID 1.\n");
    return 0;
}
