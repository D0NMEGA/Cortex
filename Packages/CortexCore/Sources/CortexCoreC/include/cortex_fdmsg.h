// cortex_fdmsg.h — IPC-03 cross-process FD passing via mach_msg + MACH_MSG_PORT_DESCRIPTOR.
//
// This is the MANDATED Mach primitive (a conscious low-level choice over XPC's xpc_fd_create —
// see 02-RESEARCH.md Q1 / the threat model / ADR). The shm region's fd is wrapped as a fileport
// (fileport_makeport) and moved inside a COMPLEX mach_msg as ONE port descriptor; the receiver
// reconstructs the fd via fileport_makefd. There is deliberately NO BSD socket control-message
// rights-transfer path here (the no-rights-transfer invariant, SC#2).
//
// CF#5: ONLY the shm region fd is fileport-sendable. A kqueue/socket fd makes fileport_makeport
// error out (man fileport_makeport) — never pass one here.
//
// Lives in CortexCoreC (alongside cortex_shm.h) so the Foundation-free CortexIPCTransport Swift
// can `import CortexCoreC` and call these without pulling Foundation onto the hot path.

#ifndef CORTEX_FDMSG_H
#define CORTEX_FDMSG_H

#include <mach/mach.h>
#include <stdint.h>

// The complex message form mandated by IPC-03: a header (with MACH_MSGH_BITS_COMPLEX), a body
// (msgh_descriptor_count = 1), exactly one MACH_MSG_PORT_DESCRIPTOR carrying the fileport, plus the
// inline ring geometry so the receiver can validate + map the region in one message. shm_name is a
// fixed 32-byte buffer (<=31 + NUL, mirrors Darwin PSHMNAMLEN) — a bounded buffer on receive
// (T-02-02-03).
typedef struct {
  mach_msg_header_t          header;       // msgh_bits |= MACH_MSGH_BITS_COMPLEX
  mach_msg_body_t            body;         // msgh_descriptor_count = 1
  mach_msg_port_descriptor_t fd_port;      // .disposition = MACH_MSG_TYPE_MOVE_SEND, .type = MACH_MSG_PORT_DESCRIPTOR
  uint64_t                   ring_bytes;
  uint64_t                   slot_stride;
  uint32_t                   slot_depth;
  uint32_t                   _pad;
  char                       shm_name[32]; // <=31 + NUL (PSHMNAMLEN)
} cortex_fd_msg_t;

// Send the shm fd (made into a fileport) + ring geometry to `dest` (a send right, provided by the
// harness's CF#3 rendezvous — this function does NOT perform rendezvous). Returns KERN_SUCCESS (0)
// on a successful mach_msg send; a positive mach_msg_return_t on a Mach send failure; or a NEGATIVE
// value (-errno) if fileport_makeport on shm_fd failed.
int cortex_fdmsg_send(mach_port_t dest, int shm_fd,
                      uint64_t ring_bytes, uint64_t slot_stride, uint32_t slot_depth,
                      const char *shm_name);

// Receive on `rcv` (a receive right); reconstruct the fd via fileport_makefd; output the ring
// geometry and shm_name. Returns the received fd (>= 0, CLOEXEC already set by fileport_makefd) on
// success; a NEGATIVE value on failure: -(mach_msg_return_t) for a Mach receive error, or -errno
// for a fileport_makefd failure. `out_shm_name` must point to a 32-byte buffer.
int cortex_fdmsg_recv(mach_port_t rcv,
                      uint64_t *out_ring_bytes, uint64_t *out_slot_stride,
                      uint32_t *out_slot_depth, char out_shm_name[32]);

#endif // CORTEX_FDMSG_H
