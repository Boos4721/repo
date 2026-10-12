"""Verify Dart FFI exports survive the final iOS link. Run only on macOS."""
import subprocess
import sys
symbols={
    '_ant_engine_new','_ant_engine_free','_ant_engine_feed','_ant_engine_reset',
    '_ant_string_free','_ant_read_request','_ant_demo_frame',
}
output=subprocess.check_output(['xcrun','nm','-gU',sys.argv[1]],text=True)
found={line.split()[-1] for line in output.splitlines() if line.split()}
missing=symbols-found
if missing:raise SystemExit('Missing FFI exports: '+', '.join(sorted(missing)))
print('All 7 Rust FFI exports exist in the linked iOS executable.')
