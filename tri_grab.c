#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <linux/input.h>

static int g_fd = -1;
static volatile sig_atomic_t g_stop = 0;

static void on_sig(int s) {
    (void)s;
    g_stop = 1;
}

static int find_dev(char *out, size_t n) {
    DIR *d = opendir("/dev/input");
    if (!d) return -1;
    struct dirent *e;
    char path[256], name[256];
    int ret = -1;
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, "event", 5) != 0) continue;
        snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
        int fd = open(path, O_RDONLY);
        if (fd < 0) continue;
        memset(name, 0, sizeof(name));
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) >= 0) {
            if (strstr(name, "hall_tri_state")) {
                snprintf(out, n, "%s", path);
                close(fd);
                ret = 0;
                break;
            }
        }
        close(fd);
    }
    closedir(d);
    return ret;
}

int main(int argc, char **argv) {
    char dev[256] = {0};
    const char *log = "/data/local/tmp/tri_key/grab.log";

    if (argc > 1 && argv[1][0] == '/') {
        snprintf(dev, sizeof(dev), "%s", argv[1]);
    } else if (find_dev(dev, sizeof(dev)) < 0) {
        fprintf(stderr, "ERR: hall_tri_state device not found\n");
        return 2;
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_sig;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);

    g_fd = open(dev, O_RDONLY | O_NONBLOCK);
    if (g_fd < 0) {
        fprintf(stderr, "ERR: open %s: %s\n", dev, strerror(errno));
        return 3;
    }

    if (ioctl(g_fd, EVIOCGRAB, 1) < 0) {
        fprintf(stderr, "ERR: EVIOCGRAB %s: %s\n", dev, strerror(errno));
        close(g_fd);
        return 4;
    }

    fprintf(stderr, "OK grabbed %s (pid %d)\n", dev, (int)getpid());
    fflush(stderr);

    /* 读事件并直接丢弃：防止内核缓冲溢出，同时让 system_server 收不到 */
    while (!g_stop) {
        fd_set rf;
        FD_ZERO(&rf);
        FD_SET(g_fd, &rf);
        struct timeval tv = { .tv_sec = 1, .tv_usec = 0 };
        int r = select(g_fd + 1, &rf, NULL, NULL, &tv);
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (r == 0) continue;
        if (FD_ISSET(g_fd, &rf)) {
            struct input_event ev;
            while (read(g_fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
                /* 丢弃 */
            }
        }
    }

    ioctl(g_fd, EVIOCGRAB, 0);
    close(g_fd);
    fprintf(stderr, "RELEASED %s\n", dev);
    (void)log;
    return 0;
}
