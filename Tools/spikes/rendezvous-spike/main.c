// CF#3 spike — parent->child Mach-port rendezvous WITHOUT a launchd plist and WITHOUT the
// deprecated bootstrap_register (Phase 2, Plan 02-01, Task 3).
//
// 02-RESEARCH.md Critical Finding #3: D-08 names "parent publishes a receive right under a
// bootstrap service name; child bootstrap_look_up"s it" — but bootstrap_register is
// __OSX_AVAILABLE_BUT_DEPRECATED(10.4->10.5) and returns BOOTSTRAP_NOT_PRIVILEGED (1100) for
// ad-hoc names on modern macOS, and the non-deprecated bootstrap_check_in needs a launchd plist
// (which D-08 avoids). The robust non-deprecated alternative is posix_spawnattr_setspecialport_np:
// the parent injects a rendezvous SEND right into the child at spawn as TASK_BOOTSTRAP_PORT; the
// child reads it via task_get_special_port and messages the parent directly.
//
// This program proves the mechanism: the parent allocates a receive right, inserts a send right,
// injects that send right as the child's TASK_BOOTSTRAP_PORT, posix_spawns ITSELF with arg "child",
// then blocks in mach_msg(MACH_RCV_MSG). The child reads TASK_BOOTSTRAP_PORT and sends a one-word
// message back. If the parent prints the received word, the rendezvous works.
//
// Build + run (no signing needed):
//   xcrun clang main.c -o /tmp/cortex-rdv-spike
//   /tmp/cortex-rdv-spike          # parent posix_spawns itself with `child`

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <spawn.h>
#include <mach/mach.h>
#include <mach/task_special_ports.h>

extern char **environ;

// One-word message: a fixed-size header + a single uint32 payload.
typedef struct {
  mach_msg_header_t header;
  uint32_t          word;
} rdv_msg_t;

// Receive struct must also reserve room for the trailer.
typedef struct {
  mach_msg_header_t  header;
  uint32_t           word;
  mach_msg_trailer_t trailer;
} rdv_rcv_t;

#define RDV_WORD 0xC0FFEEu

// ---- CHILD ----------------------------------------------------------------
// Reads the injected rendezvous SEND right from TASK_BOOTSTRAP_PORT and sends one word to it.
static int run_child(void) {
  mach_port_t rendezvous = MACH_PORT_NULL;
  kern_return_t kr = task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &rendezvous);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "child: task_get_special_port(TASK_BOOTSTRAP_PORT) failed: %s (0x%x)\n",
            mach_error_string(kr), kr);
    return 1;
  }

  rdv_msg_t msg;
  memset(&msg, 0, sizeof(msg));
  msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
  msg.header.msgh_size = sizeof(msg);
  msg.header.msgh_remote_port = rendezvous;     // the parent's receive right (we hold a send right)
  msg.header.msgh_local_port = MACH_PORT_NULL;
  msg.header.msgh_id = 0x10;
  msg.word = RDV_WORD;

  kr = mach_msg(&msg.header, MACH_SEND_MSG, sizeof(msg), 0,
                MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "child: mach_msg(MACH_SEND_MSG) failed: %s (0x%x)\n", mach_error_string(kr), kr);
    return 1;
  }
  fprintf(stderr, "child: sent word 0x%X over TASK_BOOTSTRAP_PORT rendezvous\n", RDV_WORD);
  return 0;
}

// ---- PARENT ---------------------------------------------------------------
static int run_parent(const char *self_path) {
  // 1. Allocate a receive right (the rendezvous port).
  mach_port_t rx = MACH_PORT_NULL;
  kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &rx);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "parent: mach_port_allocate failed: %s (0x%x)\n", mach_error_string(kr), kr);
    return 1;
  }
  // 2. Insert a SEND right we can hand to the child.
  kr = mach_port_insert_right(mach_task_self(), rx, rx, MACH_MSG_TYPE_MAKE_SEND);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "parent: mach_port_insert_right failed: %s (0x%x)\n", mach_error_string(kr), kr);
    return 1;
  }

  // 3. Build spawn attrs and inject the send right as the child's TASK_BOOTSTRAP_PORT.
  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
  int rc = posix_spawnattr_setspecialport_np(&attr, rx, TASK_BOOTSTRAP_PORT);
  if (rc != 0) {
    fprintf(stderr, "parent: posix_spawnattr_setspecialport_np failed: rc=%d\n", rc);
    posix_spawnattr_destroy(&attr);
    return 1;
  }

  // 4. posix_spawn ourselves with arg "child".
  char *const argv[] = { (char *)self_path, (char *)"child", NULL };
  pid_t pid = 0;
  rc = posix_spawn(&pid, self_path, NULL, &attr, argv, environ);
  posix_spawnattr_destroy(&attr);
  if (rc != 0) {
    fprintf(stderr, "parent: posix_spawn failed: rc=%d\n", rc);
    return 1;
  }
  fprintf(stderr, "parent: spawned child pid=%d; waiting for rendezvous word...\n", pid);

  // 5. Block until the child messages us (10s safety timeout so the spike never hangs CI).
  rdv_rcv_t rcv;
  memset(&rcv, 0, sizeof(rcv));
  kr = mach_msg(&rcv.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof(rcv),
                rx, 10000 /* ms */, MACH_PORT_NULL);
  if (kr != KERN_SUCCESS) {
    fprintf(stderr, "parent: mach_msg(MACH_RCV_MSG) failed: %s (0x%x)\n", mach_error_string(kr), kr);
    return 1;
  }

  if (rcv.word == RDV_WORD) {
    printf("PASS: parent received word 0x%X from posix_spawn'd child over TASK_BOOTSTRAP_PORT\n",
           rcv.word);
    return 0;
  }
  fprintf(stderr, "parent: received unexpected word 0x%X (expected 0x%X)\n", rcv.word, RDV_WORD);
  return 1;
}

int main(int argc, char **argv) {
  if (argc > 1 && strcmp(argv[1], "child") == 0) {
    return run_child();
  }
  return run_parent(argv[0]);
}
