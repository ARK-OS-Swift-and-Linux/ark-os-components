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

#ifdef __cplusplus
}
#endif

#endif /* ARKRT_SIGNALS_H */
