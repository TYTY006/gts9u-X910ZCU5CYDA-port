#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <termios.h>
#include <unistd.h>

#define SOCK_PATH "/data/local/tmp/temp_su.sock"
#define SU_PROTOCOL_MAGIC 0x53553235U
#define SU_PROTOCOL_VERSION 1U
#define SU_PASSED_FDS 5U

struct su_tty_state {
  uint8_t has_termios;
  uint8_t has_winsize;
  struct termios termios;
  struct winsize winsize;
};

struct su_request_header {
  uint32_t magic;
  uint32_t version;
  uint32_t argc;
  uint32_t envc;
  uint8_t interactive;
  uint8_t reserved[3];
  struct su_tty_state tty;
};

static int write_full(int fd, const void *buf, size_t len) {
  const char *p = buf;
  while (len) {
    ssize_t n = write(fd, p, len);
    if (n < 0) {
      if (errno == EINTR) continue;
      return -1;
    }
    p += n;
    len -= (size_t)n;
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <command> [args...]\n", argv[0]);
    return 64;
  }

  int in_pipe[2], out_pipe[2];
  if (pipe(in_pipe) != 0 || pipe(out_pipe) != 0) {
    perror("pipe");
    return 1;
  }
  int cwd_fd = open("/", O_RDONLY | O_DIRECTORY);
  int io_fd = open("/dev/null", O_RDWR);
  if (cwd_fd < 0 || io_fd < 0) {
    perror("open");
    return 1;
  }
  int fds[SU_PASSED_FDS] = {in_pipe[0], out_pipe[1], out_pipe[1], cwd_fd, io_fd};

  int sock = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sock < 0) {
    perror("socket");
    return 1;
  }
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, SOCK_PATH, sizeof(addr.sun_path) - 1);

  if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    perror("connect");
    return 2;
  }

  /* 1. one-byte marker + 5 fds via SCM_RIGHTS */
  char marker = 'F';
  struct iovec iov = {.iov_base = &marker, .iov_len = sizeof(marker)};
  char control[CMSG_SPACE(sizeof(int) * SU_PASSED_FDS)];
  memset(control, 0, sizeof(control));
  struct msghdr msg;
  memset(&msg, 0, sizeof(msg));
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_control = control;
  msg.msg_controllen = sizeof(control);
  struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
  cmsg->cmsg_level = SOL_SOCKET;
  cmsg->cmsg_type = SCM_RIGHTS;
  cmsg->cmsg_len = CMSG_LEN(sizeof(int) * SU_PASSED_FDS);
  memcpy(CMSG_DATA(cmsg), fds, sizeof(fds));

  if (sendmsg(sock, &msg, 0) != (ssize_t)sizeof(marker)) {
    perror("sendmsg");
    return 3;
  }

  /* 2. header + argv + envp */
  struct su_request_header hdr;
  memset(&hdr, 0, sizeof(hdr));
  hdr.magic = SU_PROTOCOL_MAGIC;
  hdr.version = SU_PROTOCOL_VERSION;
  hdr.argc = (uint32_t)argc;
  hdr.envc = 1;
  if (write_full(sock, &hdr, sizeof(hdr)) != 0) return 4;

  for (int i = 0; i < argc; i++) {
    uint32_t len = (uint32_t)strlen(argv[i]);
    if (write_full(sock, &len, sizeof(len)) != 0 ||
        write_full(sock, argv[i], len) != 0)
      return 5;
  }
  const char *env = "PATH=/sbin:/system/sbin:/system/bin:/system/xbin";
  uint32_t env_len = (uint32_t)strlen(env);
  if (write_full(sock, &env_len, sizeof(env_len)) != 0 ||
      write_full(sock, env, env_len) != 0)
    return 6;

  /* 3. drain stdout */
  close(out_pipe[1]);
  close(in_pipe[0]);
  char buf[8192];
  ssize_t n;
  while ((n = read(out_pipe[0], buf, sizeof(buf))) > 0) {
    if (write(STDOUT_FILENO, buf, (size_t)n) < 0) break;
  }
  return 0;
}
