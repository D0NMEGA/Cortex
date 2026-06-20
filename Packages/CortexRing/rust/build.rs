//! Generates the vendored C ABI header (`include/cortex_ring.h`) from the crate's
//! `extern "C"` surface via cbindgen (RESEARCH §1 recommended build.rs mode; THREAD-06).
//!
//! The committed header IS the contract Swift links against (the `.binaryTarget` modulemap points
//! at it); regeneration here keeps it in lockstep with the Rust source, and the CI drift gate
//! (`cargo build` + `git diff --exit-code include/cortex_ring.h`, Task 3) fails the build if a
//! source change was not reflected in the committed header (threat T-03-01-03 / D-13).
//!
//! Generation is best-effort: if cbindgen cannot produce the header (e.g. a transient parse issue
//! during a `cargo test`-only invocation), we emit a `cargo:warning` and leave the already-vendored
//! header in place rather than hard-failing the build — mirroring the "only when the tool is
//! present" ethos of `Tools/scripts/gen-flatbuffers.sh` (D-13). A genuinely stale header is caught
//! loudly by the CI drift gate, not silently here.

fn main() {
    let crate_dir = match std::env::var("CARGO_MANIFEST_DIR") {
        Ok(dir) => dir,
        Err(e) => {
            println!("cargo:warning=cortex_ring build.rs: CARGO_MANIFEST_DIR unset ({e}); skipping cbindgen header generation");
            return;
        }
    };

    let header_path = std::path::Path::new(&crate_dir)
        .join("include")
        .join("cortex_ring.h");

    // Re-run the build script (and thus regenerate the header) when the FFI surface or the
    // frame layout changes, or when the cbindgen config changes.
    println!("cargo:rerun-if-changed=src/ffi.rs");
    println!("cargo:rerun-if-changed=src/frame.rs");
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed=cbindgen.toml");

    match cbindgen::generate(&crate_dir) {
        Ok(bindings) => {
            // write_to_file only rewrites the file when the contents actually change, so a clean
            // build does not needlessly dirty the working tree.
            bindings.write_to_file(&header_path);
        }
        Err(e) => {
            println!(
                "cargo:warning=cortex_ring build.rs: cbindgen::generate failed ({e}); leaving vendored {} in place (CI drift gate will catch staleness)",
                header_path.display()
            );
        }
    }
}
