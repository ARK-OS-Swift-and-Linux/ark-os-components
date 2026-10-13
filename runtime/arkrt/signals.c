#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stddef.h>
#include <string.h>
#include "signals.h"

static volatile sig_atomic_t g_shutdown_requested = 0;

static void arkrt_sigterm_handler(int sig) {
    (void)sig;
    g_shutdown_requested = 1;
}

static void arkrt_sigchld_handler(int sig) {
    (void)sig;
    /* Handled via non-blocking waitpid in main loop */
}

void arkrt_init_signals(void) {
    struct sigaction sa_chld;
    memset(&sa_chld, 0, sizeof(sa_chld));
    sa_chld.sa_handler = arkrt_sigchld_handler;
    sa_chld.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    sigaction(SIGCHLD, &sa_chld, NULL);

    struct sigaction sa_term;
    memset(&sa_term, 0, sizeof(sa_term));
    sa_term.sa_handler = arkrt_sigterm_handler;
    sa_term.sa_flags = SA_RESTART;
    sigaction(SIGTERM, &sa_term, NULL);
    sigaction(SIGINT, &sa_term, NULL);
}

int arkrt_is_shutdown_requested(void) {
    return (int)g_shutdown_requested;
}

void arkrt_reset_shutdown_requested(void) {
    g_shutdown_requested = 0;
}

void arkrt_ignore_sigterm(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_IGN;
    sigaction(SIGTERM, &sa, NULL);
}
