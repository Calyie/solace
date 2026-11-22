#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>

#include "my_application.h"
#include "net_block.h"

int main(int argc, char** argv) {
  // AIR-3 (owner, 2026-11-16): the operating system blocks Solace from the network (net_block.h), first of all, while
  // this is the only thread and before GTK, GLib or any library starts. Release builds only: a debug or profile build
  // is reached by Flutter's own tools through the Dart VM service on a loopback internet socket, which the block would
  // refuse. If the kernel does not take the filter, Solace starts anyway and says so: SOLACE_NET_BLOCK is "on" or
  // "off" (set here, whatever the environment held), and Settings > Private by design reads it
  // (lib/core/network_guard.dart).
#ifdef SOLACE_RELEASE_NET_BLOCK
  const bool blocked = solace_block_network();
#else
  const bool blocked = false;
#endif
  setenv("SOLACE_NET_BLOCK", blocked ? "on" : "off", 1);
  // Owner, 2026-11-14 (security: the app is sandboxed from other programs both ways). Linux has no app sandbox, so:
  // no other program running as the same user may attach to Solace or read its memory (ptrace and /proc/<pid>/mem
  // need the process to be "dumpable"), and a crash never writes a core file holding decrypted conversation text.
  prctl(PR_SET_DUMPABLE, 0, 0, 0, 0);
  // every file Solace writes is readable by this user only, never by other accounts on the computer
  umask(077);
  struct rlimit no_core = {0, 0};
  setrlimit(RLIMIT_CORE, &no_core);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
