# OpenJDK desugaring runtime 2.1.5

Android uses the unmodified Maven artifact
`com.android.tools:desugar_jdk_libs_nio:2.1.5` for the Java APIs needed by document
parsing on older Android releases.

Complete upstream source, notices and build scripts are retained, unmodified,
in `desugar-jdk/source-2.1.5.tar.gz` from:

- Repository: https://github.com/google/desugar_jdk_libs
- Revision: `73170c345e6a762fc6a1f0301bb15218850023ef`
- Commit: Prepare for jdk-11 based desugared library version 2.1.5
- Upstream `CHANGELOG.md`: Version 2.1.5 (2025-02-14)
- License: GPL version 2 with the Classpath Exception, retained in `LICENSE`
  and the app's `assets/licenses/desugar-jdk.txt`.

Extract with `tar -xzf third_party/desugar-jdk/source-2.1.5.tar.gz` from the
project root. The archive retains the upstream directory, notices and scripts.

This archive is source distribution material, not a replacement binary. The
Android Gradle build resolves the pinned Maven artifact. Include this source
archive and this provenance file with the app's corresponding source.
