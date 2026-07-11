# Third-Party Code

CocoaSpice embeds third-party decoder and emulator code. Source and notices are kept with each dependency under `vendor/`.

## lazyusf2

- Purpose: Nintendo 64 USF and miniUSF decoding.
- Source: `vendor/lazyusf2/`
- Upstream: [kode54/lazyusf2](https://gitlab.com/kode54/lazyusf2)
- License: GPL-2.0-or-later, as stated in the vendored source headers and `vendor/lazyusf2/rsp_hle/LICENSES`.

## psflib

- Purpose: PSF-chain loading used by USF and miniUSF.
- Source: `vendor/psflib/`
- License and attribution: preserve the source as imported and audit its upstream licensing before distributing CocoaSpice binaries.

Distribution of CocoaSpice must preserve the applicable source, copyright, and license obligations for all bundled dependencies.
