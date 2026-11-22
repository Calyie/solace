// AIR-3 (security review 2026-11-14; owner, 2026-11-16): the operating system's own network block for Solace on
// Linux, which has no app sandbox and no per-app network switch. A seccomp-BPF filter, installed by main.cc at the very
// start of main() (before GTK, GLib or any thread), makes the kernel refuse:
//   - every new socket except the two local kinds: AF_UNIX (D-Bus, X11 and Wayland, PulseAudio and PipeWire, the
//     keyring, GLib) and AF_NETLINK (the kernel's own device and link events). AF_INET, AF_INET6, AF_PACKET and every
//     other family (Bluetooth, VSOCK and the rest) fail with EACCES, so no internet socket can be made at all, and no
//     name can be looked up over the network;
//   - io_uring_setup, with ENOSYS, as io_uring can open sockets without the socket system call;
//   - any system call made under another architecture's numbering (x86-64's 32-bit and x32 entry points, where the
//     socket calls have other numbers), with ENOSYS.
// Everything else is allowed. The filter is inherited by every thread (SECCOMP_FILTER_FLAG_TSYNC) and by every program
// Solace starts (parecord for the microphone, df for the free space), and it cannot be removed. PR_SET_NO_NEW_PRIVS,
// which seccomp needs, also means a program Solace starts can never gain privileges (set-user-ID); Solace starts none
// that need them. Built for x86-64 and arm64 only: on any other architecture nothing is installed, rather than a
// filter written for other system call numbers.
//
// tools/traffic/net_block_test.cc checks this filter on the machine that builds it (g++, no network traffic).
//
// Solace Home (docs/HOME_SERVER.md, owner 2026-11-19), and only there: a Home build (made with
// --dart-define=SOLACE_HOME=true, which the runner's CMakeLists.txt reads and turns into SOLACE_HOME_NET) also lets
// AF_INET and AF_INET6 sockets of the two ordinary types through, stream (TCP, to reach the paired home server) and
// datagram (UDP, so a server's name can be looked up); raw, packet, Bluetooth, VSOCK and every other kind stay refused.
// The kernel cannot see where a socket connects, so which server may be reached is the app's own guard
// (home/home_link_impl.dart: the paired address and port only, with its pinned certificate). The default build's
// filter is the one below, unchanged.
#ifndef SOLACE_NET_BLOCK_H_
#define SOLACE_NET_BLOCK_H_

#include <errno.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

#if defined(__x86_64__)
#define SOLACE_AUDIT_ARCH AUDIT_ARCH_X86_64
#elif defined(__aarch64__)
#define SOLACE_AUDIT_ARCH AUDIT_ARCH_AARCH64
#endif

#ifndef SECCOMP_FILTER_FLAG_TSYNC
#define SECCOMP_FILTER_FLAG_TSYNC (1UL << 0)
#endif

// Installs the filter for the whole process; true when the kernel took it. Called once, before any other thread.
static inline bool solace_block_network() {
#if !defined(SOLACE_AUDIT_ARCH) || !defined(__NR_seccomp) || !defined(__NR_io_uring_setup)
  return false;  // an architecture or C library this filter was not written for: none rather than a wrong one
#else
  struct sock_filter filter[] = {
      // [0-2] the system call's architecture must be this build's; any other numbering is refused whole
      BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SOLACE_AUDIT_ARCH, 1, 0),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (ENOSYS & SECCOMP_RET_DATA)),
      BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
#if defined(__x86_64__)
      // x32 system calls carry the x86-64 architecture value with bit 30 set in the number: refused whole
      BPF_JUMP(BPF_JMP | BPF_JGE | BPF_K, 0x40000000, 0, 1),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (ENOSYS & SECCOMP_RET_DATA)),
#endif
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_io_uring_setup, 0, 1),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (ENOSYS & SECCOMP_RET_DATA)),
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_socket, 1, 0),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
      // a new socket: its family is the first argument, an int (the low 32 bits; both builds are little-endian)
      BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, args[0])),
#ifndef SOLACE_HOME_NET
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_UNIX, 2, 0),
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_NETLINK, 1, 0),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EACCES & SECCOMP_RET_DATA)),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
#else
      // Solace Home: [0] family; local and netlink allowed, internet families go on to the type check, the rest refused
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_UNIX, 9, 0),     // to [10] allow
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_NETLINK, 8, 0),  // to [10] allow
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_INET, 2, 0),     // to [5] the type
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AF_INET6, 1, 0),    // to [5] the type
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EACCES & SECCOMP_RET_DATA)),
      // [5] the type is the second argument; its low four bits without SOCK_NONBLOCK and SOCK_CLOEXEC
      BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, args[1])),
      BPF_STMT(BPF_ALU | BPF_AND | BPF_K, 0xf),
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SOCK_STREAM, 2, 0),  // to [10] allow
      BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SOCK_DGRAM, 1, 0),   // to [10] allow
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EACCES & SECCOMP_RET_DATA)),
      BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),            // [10]
#endif
  };
  struct sock_fprog program = {static_cast<unsigned short>(sizeof(filter) / sizeof(filter[0])), filter};
  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) return false;
  return syscall(__NR_seccomp, SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_TSYNC, &program) == 0;
#endif
}

#endif  // SOLACE_NET_BLOCK_H_
