// cortex_rendezvous.c — CF#3 Mach rendezvous (Plan 02-04 Task 1, IPC-03). Ports the PROVEN core of
// Tools/spikes/rendezvous-spike/main.c (PASS 3/3 on real M4 / Xcode 26.3 / macOS 26.5, 02-SPIKES.md)
// and adds the reply-port flip so the shm fd can flow producer(parent) -> consumer(child).
//
// The spike proved: parent allocates a receive right, inserts a send right, injects the SEND right
// into the child as TASK_BOOTSTRAP_PORT via posix_spawnattr_setspecialport_np; the child reads it
// via task_get_special_port and can SEND to the parent. setspecialport_np transfers exactly a SEND
// right (injecting it and trying to RECEIVE in the child fails with MACH_RCV_INVALID_NAME), so the
// child->parent direction is fixed. FDChannel needs the fd to go parent->child, so the child
// advertises a reply port (one bootstrap handshake message carrying the reply port's send right in a
// port descriptor); the parent then uses that reply send right as FDChannel.send's `dest`.
//
// NO bootstrap_register (BOOTSTRAP_NOT_PRIVILEGED for ad-hoc names on modern macOS, 02-RESEARCH.md
// Critical Finding #3), NO launchd plist, and deliberately NO BSD socket control-message
// rights-transfer path here (the no-rights-transfer invariant, SC#2 — FD passing is cortex_fdmsg.c's
// mach_msg + fileport job; this file only moves Mach port rights).
//
// Lives in CortexCoreC alongside cortex_fdmsg.h/cortex_shm.h so the Foundation-free transport and the
// CortexIPCSession harness can both reach it via `import CortexCoreC`.

#include "cortex_rendezvous.h"

#include <mach/mach.h>
#include <mach/task_special_ports.h>
#include <stddef.h>

// One-shot bootstrap handshake message: a COMPLEX message carrying exactly one port descriptor —
// the child's reply port SEND right (MAKE_SEND). No inline payload; the only purpose is to flip the
// direction so the parent learns a send right to the child's reply receive port.
typedef struct {
  mach_msg_header_t          header; // msgh_bits |= MACH_MSGH_BITS_COMPLEX
  mach_msg_body_t            body;   // msgh_descriptor_count = 1
  mach_msg_port_descriptor_t reply_port;
} cortex_rdv_boot_msg_t;

// Receive buffer reserves room for the message PLUS its trailer.
typedef struct {
  cortex_rdv_boot_msg_t msg;
  mach_msg_trailer_t    trailer;
} cortex_rdv_boot_rcv_t;

// Small marker id for the bootstrap handshake (distinct from cortex_fdmsg's 'CORX' data id).
#define CORTEX_RDV_BOOT_MSG_ID 0x52445648 /* 'RDVH' */

kern_return_t cortex_rendezvous_parent_prepare(posix_spawnattr_t *attr,
                                               mach_port_t *out_bootstrap_recv) {
  if (out_bootstrap_recv != NULL) {
    *out_bootstrap_recv = MACH_PORT_NULL;
  }

  // 1. Allocate the bootstrap RECEIVE right the parent keeps (it receives the child's handshake here).
  mach_port_t boot = MACH_PORT_NULL;
  kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &boot);
  if (kr != KERN_SUCCESS) {
    return kr;
  }

  // 2. Insert a SEND right (same port name now holds receive + send) — the send right is what the
  //    spawn injection hands the child.
  kr = mach_port_insert_right(mach_task_self(), boot, boot, MACH_MSG_TYPE_MAKE_SEND);
  if (kr != KERN_SUCCESS) {
    mach_port_mod_refs(mach_task_self(), boot, MACH_PORT_RIGHT_RECEIVE, -1);
    return kr;
  }

  // 3. Inject the SEND right as the child's TASK_BOOTSTRAP_PORT (the proven spike mechanism). The
  //    `_np` call returns an errno-style int, not a kern_return_t; map a nonzero rc to a generic
  //    failure so callers see a single nonzero-is-error contract.
  int rc = posix_spawnattr_setspecialport_np(attr, boot, TASK_BOOTSTRAP_PORT);
  if (rc != 0) {
    // The send right was duplicated for the attr by the call's failure path is unspecified; drop our
    // send + receive refs so we never leak the rendezvous port on a prepare failure.
    mach_port_deallocate(mach_task_self(), boot);                                  // send ref
    mach_port_mod_refs(mach_task_self(), boot, MACH_PORT_RIGHT_RECEIVE, -1);        // receive ref
    return KERN_FAILURE;
  }

  if (out_bootstrap_recv != NULL) {
    *out_bootstrap_recv = boot; // parent holds the receive right (+ a send ref consumed by the child)
  }
  return KERN_SUCCESS;
}

kern_return_t cortex_rendezvous_parent_await_reply(mach_port_t bootstrap_recv,
                                                   uint32_t timeout_ms,
                                                   mach_port_t *out_child_send) {
  if (out_child_send != NULL) {
    *out_child_send = MACH_PORT_NULL;
  }

  cortex_rdv_boot_rcv_t rcv;
  // Zero the buffer (no memset dependency: this struct is small and POD).
  for (size_t i = 0; i < sizeof(rcv); ++i) {
    ((unsigned char *)&rcv)[i] = 0;
  }

  mach_msg_option_t opts = MACH_RCV_MSG;
  mach_msg_timeout_t to = MACH_MSG_TIMEOUT_NONE;
  if (timeout_ms != 0) {
    opts |= MACH_RCV_TIMEOUT;
    to = (mach_msg_timeout_t)timeout_ms;
  }

  kern_return_t kr = mach_msg(&rcv.msg.header,
                              opts,
                              0,                 // send_size
                              sizeof(rcv),       // rcv_size (message + trailer)
                              bootstrap_recv,
                              to,
                              MACH_PORT_NULL);

  // The rendezvous is one-shot: release the bootstrap receive right regardless of outcome.
  mach_port_mod_refs(mach_task_self(), bootstrap_recv, MACH_PORT_RIGHT_RECEIVE, -1);

  if (kr != KERN_SUCCESS) {
    return kr;
  }

  // Extract the child's reply port SEND right from the single port descriptor.
  if (out_child_send != NULL) {
    *out_child_send = rcv.msg.reply_port.name;
  }
  return KERN_SUCCESS;
}

kern_return_t cortex_rendezvous_child_acquire(mach_port_t *out_reply_recv) {
  if (out_reply_recv != NULL) {
    *out_reply_recv = MACH_PORT_NULL;
  }

  // 1. Read the injected bootstrap SEND right (the proven spike call).
  mach_port_t boot_send = MACH_PORT_NULL;
  kern_return_t kr = task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &boot_send);
  if (kr != KERN_SUCCESS) {
    return kr;
  }

  // 2. Allocate the reply port (RECEIVE right the child keeps) + a SEND right to advertise.
  mach_port_t reply = MACH_PORT_NULL;
  kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &reply);
  if (kr != KERN_SUCCESS) {
    mach_port_deallocate(mach_task_self(), boot_send);
    return kr;
  }
  kr = mach_port_insert_right(mach_task_self(), reply, reply, MACH_MSG_TYPE_MAKE_SEND);
  if (kr != KERN_SUCCESS) {
    mach_port_mod_refs(mach_task_self(), reply, MACH_PORT_RIGHT_RECEIVE, -1);
    mach_port_deallocate(mach_task_self(), boot_send);
    return kr;
  }

  // 3. Send the bootstrap handshake to the parent carrying reply's SEND right (MAKE_SEND descriptor).
  cortex_rdv_boot_msg_t msg;
  for (size_t i = 0; i < sizeof(msg); ++i) {
    ((unsigned char *)&msg)[i] = 0;
  }
  msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
  msg.header.msgh_remote_port = boot_send; // the parent's receive right (we hold a send right)
  msg.header.msgh_local_port = MACH_PORT_NULL;
  msg.header.msgh_size = sizeof(msg);
  msg.header.msgh_id = CORTEX_RDV_BOOT_MSG_ID;
  msg.body.msgh_descriptor_count = 1;
  msg.reply_port.name = reply;
  msg.reply_port.disposition = MACH_MSG_TYPE_MAKE_SEND; // hand the parent a send right to `reply`
  msg.reply_port.type = MACH_MSG_PORT_DESCRIPTOR;

  kr = mach_msg(&msg.header,
                MACH_SEND_MSG,
                sizeof(msg),
                0,                 // rcv_size
                MACH_PORT_NULL,    // rcv_name
                MACH_MSG_TIMEOUT_NONE,
                MACH_PORT_NULL);

  // Done with the bootstrap send right whether or not the send succeeded.
  mach_port_deallocate(mach_task_self(), boot_send);

  if (kr != KERN_SUCCESS) {
    // The send did not consume the MAKE_SEND descriptor on failure; drop reply's send + receive refs.
    mach_port_deallocate(mach_task_self(), reply);                            // send ref
    mach_port_mod_refs(mach_task_self(), reply, MACH_PORT_RIGHT_RECEIVE, -1); // receive ref
    return kr;
  }

  // On success the parent holds a send right to `reply`; the child keeps the RECEIVE right.
  if (out_reply_recv != NULL) {
    *out_reply_recv = reply;
  }
  return KERN_SUCCESS;
}
