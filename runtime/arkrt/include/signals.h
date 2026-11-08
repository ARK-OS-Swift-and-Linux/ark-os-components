#ifndef ARKRT_SIGNALS_H
#define ARKRT_SIGNALS_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Installs POSIX signal handlers using sigaction for SIGCHLD, SIGTERM, and SIGINT.
 * All handlers are implemented in pure C to ensure true async-signal-safety.
 */
void arkrt_init_signals(void);

/*
 * Checks whether a termination signal (SIGTERM or SIGINT) has been received.
 * Reads an internal volatile sig_atomic_t flag.
 */
int arkrt_is_shutdown_requested(void);

/*
 * Resets the shutdown request flag.
 */
void arkrt_reset_shutdown_requested(void);

/*
 * Sets SIGTERM disposition to SIG_IGN using C sigaction.
 */
void arkrt_ignore_sigterm(void);

/*
 * Sets up controlling terminal on the given TTY device path for a child process.
 * Calls setsid(), open(tty_path), ioctl(fd, TIOCSCTTY, 1), and dup2 onto stdio streams.
 * Returns 0 on success, or -1 on error.
 */
int arkrt_setup_tty(const char *tty_path);

#ifdef __cplusplus
}
#endif

#endif /* ARKRT_SIGNALS_H */
