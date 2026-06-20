// cortex_fdmsg.c — IPC-03 mach_msg + fileport FD passing (NO socket control-message rights path).
//
// IPC-03 mandates the raw mach_msg + fileport primitive over XPC's xpc_fd_create — a conscious
// low-level choice (the "thinnest viable" transport). See 02-RESEARCH.md Q1 and the threat-model
// ADR. The shm fd is wrapped with fileport_makeport into ONE MACH_MSG_PORT_DESCRIPTOR inside a
// COMPLEX message; the receiver reconstructs it with fileport_makefd. This file contains no BSD
// socket control-message rights-transfer path of any kind (the no-rights-transfer invariant, SC#2).
//
// CF#5: only the shm region fd is fileport-sendable; fileport_makeport errors on a kqueue/socket fd.
//
// References for the exact send/recv incantation: frida-core lib/pipe/pipe-darwin.c (fileport +
// mach_msg), HexFiend helper_subprocess (a shipping macOS app passing fds to a helper subprocess).

#include "cortex_fdmsg.h"

#include <sys/fileport.h> // fileport_makeport / fileport_makefd
#include <mach/mach.h>
#include <string.h>     // memset, strncpy
#include <errno.h>

int cortex_fdmsg_send(mach_port_t dest, int shm_fd,
                      uint64_t ring_bytes, uint64_t slot_stride, uint32_t slot_depth,
                      const char *shm_name) {
  // Wrap the shm fd as a fileport (a Mach port with a send right). Only the shm fd is eligible
  // (CF#5); fileport_makeport returns -1/errno for an ineligible fd (kqueue/socket).
  fileport_t fp = FILEPORT_NULL;
  if (fileport_makeport(shm_fd, &fp) != 0) {
    return -errno; // negative => fileport failure, distinguishable from a positive mach_msg_return_t
  }

  cortex_fd_msg_t msg;
  memset(&msg, 0, sizeof(msg));

  // COPY_SEND on the remote port (we were handed `dest`, a send right, by the rendezvous harness);
  // the message is COMPLEX because it carries a port descriptor.
  msg.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
  msg.header.msgh_remote_port = dest;
  msg.header.msgh_local_port = MACH_PORT_NULL;
  msg.header.msgh_size = sizeof(msg);
  msg.header.msgh_id = 0x434F5258; // 'CORX' — a small marker id

  msg.body.msgh_descriptor_count = 1;

  // Exactly one port descriptor: MOVE_SEND transfers the fileport's send right to the receiver.
  msg.fd_port.name = fp;
  msg.fd_port.disposition = MACH_MSG_TYPE_MOVE_SEND;
  msg.fd_port.type = MACH_MSG_PORT_DESCRIPTOR;

  // Inline ring geometry so the receiver can validate (T-02-02-02) and map the region.
  msg.ring_bytes = ring_bytes;
  msg.slot_stride = slot_stride;
  msg.slot_depth = slot_depth;
  if (shm_name != NULL) {
    strncpy(msg.shm_name, shm_name, sizeof(msg.shm_name) - 1); // bounded; NUL guaranteed (T-02-02-03)
    msg.shm_name[sizeof(msg.shm_name) - 1] = '\0';
  }

  mach_msg_return_t kr = mach_msg(&msg.header,
                                  MACH_SEND_MSG,
                                  sizeof(msg),
                                  0,             // rcv_size
                                  MACH_PORT_NULL, // rcv_name
                                  MACH_MSG_TIMEOUT_NONE,
                                  MACH_PORT_NULL); // notify
  if (kr != MACH_MSG_SUCCESS) {
    // On a send failure the kernel did NOT consume the descriptor's send right; drop the fileport
    // so we don't leak it.
    mach_port_deallocate(mach_task_self(), fp);
    return (int)kr; // positive mach_msg_return_t
  }
  // On success MACH_MSG_TYPE_MOVE_SEND consumed `fp` — nothing to deallocate here.
  return KERN_SUCCESS; // 0
}

int cortex_fdmsg_recv(mach_port_t rcv,
                      uint64_t *out_ring_bytes, uint64_t *out_slot_stride,
                      uint32_t *out_slot_depth, char out_shm_name[32]) {
  // Receive buffer must reserve room for the message PLUS its trailer.
  typedef struct {
    cortex_fd_msg_t   msg;
    mach_msg_trailer_t trailer;
  } cortex_fd_rcv_t;

  cortex_fd_rcv_t buf;
  memset(&buf, 0, sizeof(buf));

  mach_msg_return_t kr = mach_msg(&buf.msg.header,
                                  MACH_RCV_MSG,
                                  0,                // send_size
                                  sizeof(buf),       // rcv_size (message + trailer)
                                  rcv,
                                  MACH_MSG_TIMEOUT_NONE,
                                  MACH_PORT_NULL);
  if (kr != MACH_MSG_SUCCESS) {
    return -(int)kr; // negative => Mach receive error
  }

  // Reconstruct the fd from the received fileport, then release the port right we received.
  int fd = fileport_makefd(buf.msg.fd_port.name); // CLOEXEC set by fileport_makefd
  int saved_errno = errno;
  mach_port_deallocate(mach_task_self(), buf.msg.fd_port.name);

  if (fd < 0) {
    return -saved_errno; // negative => fileport_makefd failure
  }

  // Copy out the inline geometry; treat shm_name as a bounded buffer (NUL-terminate defensively).
  if (out_ring_bytes != NULL)  { *out_ring_bytes = buf.msg.ring_bytes; }
  if (out_slot_stride != NULL) { *out_slot_stride = buf.msg.slot_stride; }
  if (out_slot_depth != NULL)  { *out_slot_depth = buf.msg.slot_depth; }
  if (out_shm_name != NULL) {
    memcpy(out_shm_name, buf.msg.shm_name, sizeof(buf.msg.shm_name));
    out_shm_name[sizeof(buf.msg.shm_name) - 1] = '\0';
  }

  return fd; // >= 0
}
