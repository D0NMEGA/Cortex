// cortex_rendezvous.h — CF#3 Mach rendezvous: hand a Mach port right from a parent process to a
// posix_spawn'd child WITHOUT a launchd plist and WITHOUT the BSD socket control-message
// rights-transfer path. The injection mechanism is recorded as PASS (3/3 deterministic on the real
// M4 / Xcode 26.3 / macOS 26.5) in 02-SPIKES.md and proven in Tools/spikes/rendezvous-spike/main.c.
//
// MECHANISM (D-08 ADOPT-WITH-RATIONALE, 02-SPIKES.md): the parent injects a rendezvous SEND right
// into the child at spawn via posix_spawnattr_setspecialport_np(attr, <send right>,
// TASK_BOOTSTRAP_PORT); the child reads it via task_get_special_port(mach_task_self(),
// TASK_BOOTSTRAP_PORT, &p). Special-port index = TASK_BOOTSTRAP_PORT (= 4). NO bootstrap_register
// (returns BOOTSTRAP_NOT_PRIVILEGED for ad-hoc names on modern macOS), NO launchd plist, NO socket
// control-message FD-passing path.
//
// DIRECTIONALITY (the proven spike + a one-message reply-port flip — documented per the Plan 02-04
// directive "adjust send/receive ownership so the fd flows producer->consumer"):
// posix_spawnattr_setspecialport_np injects exactly a SEND right into the child (empirically
// verified: trying to make the child RECEIVE on the injected port yields MACH_RCV_INVALID_NAME
// 0x10004002). So the spike's proven direction is FIXED: child=SEND, parent=RECEIVE on the
// bootstrap port. But FDChannel needs the opposite to flow the shm fd producer(parent)->consumer
// (child):
//   • FDChannel.send(to: dest)  needs a SEND right (dest = the peer's receive right, COPY_SEND)
//   • FDChannel.receive(on: rcv) needs a RECEIVE right (rcv, MACH_RCV_MSG)
// We bridge with ONE bootstrap handshake message: the child allocates its OWN reply port (a receive
// right it keeps) and sends the parent that reply port's SEND right inside a MACH_MSG_PORT_DESCRIPTOR
// over the injected bootstrap send right. The parent receives it and uses that reply send right as
// `dest` for FDChannel.send; the child receives the fd-bearing message on its reply RECEIVE right.
// Net: the shm fd flows parent(producer) -> child(consumer), using only the spike-proven injection
// primitive plus the same mach_msg + port-descriptor machinery FDChannel already speaks. Verified
// 3/3 deterministic on this machine (the handshake probe in the Plan 02-04 executor log).
//
// Caveat (02-SPIKES.md §CF#3 #3): injecting TASK_BOOTSTRAP_PORT drops the child's real launchd
// bootstrap port. SAFE for this minimal harness consumer — it needs no CFRunLoop/launchd services
// to allocate a reply port, receive an fd, and busy-poll a shm ring. (The XCTest two-process proof
// is XCTSkip-guarded; the always-on in-process correctness gate needs no rendezvous at all.)

#ifndef CORTEX_RENDEZVOUS_H
#define CORTEX_RENDEZVOUS_H

#include <mach/mach.h>
#include <spawn.h>

// Parent step 1 — before posix_spawn: allocate the bootstrap RECEIVE right, insert a SEND right, and
// arm `attr` so the child receives that SEND right as its TASK_BOOTSTRAP_PORT special port. On
// success *out_bootstrap_recv is the bootstrap RECEIVE right the parent holds (pass it to
// cortex_rendezvous_parent_await_reply after the spawn). Returns a kern_return_t (0 == success); on
// any failure *out_bootstrap_recv is MACH_PORT_NULL and the allocated right is released.
kern_return_t cortex_rendezvous_parent_prepare(posix_spawnattr_t *attr,
                                               mach_port_t *out_bootstrap_recv);

// Parent step 2 — after posix_spawn: block (bounded by timeout_ms; 0 == wait forever) until the
// child sends its bootstrap handshake, then output the child's reply SEND right (`dest` for
// FDChannel.send(to:)). `bootstrap_recv` is the right returned by parent_prepare; it is deallocated
// here (the rendezvous is one-shot). Returns the kern_return_t from the receive (0 == success); on
// failure *out_child_send is MACH_PORT_NULL.
kern_return_t cortex_rendezvous_parent_await_reply(mach_port_t bootstrap_recv,
                                                   uint32_t timeout_ms,
                                                   mach_port_t *out_child_send);

// Child side: obtain the injected bootstrap SEND right (task_get_special_port, TASK_BOOTSTRAP_PORT),
// allocate the reply port, send the bootstrap handshake advertising the reply port's SEND right back
// to the parent, and output the reply RECEIVE right (`rcv` for FDChannel.receive(on:)). The
// bootstrap send right is deallocated after the handshake. Returns a kern_return_t (0 == success);
// on failure *out_reply_recv is MACH_PORT_NULL.
kern_return_t cortex_rendezvous_child_acquire(mach_port_t *out_reply_recv);

#endif // CORTEX_RENDEZVOUS_H
