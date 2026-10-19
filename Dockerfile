FROM ubuntu:24.04 AS android-sdk

ARG CMDLINE_TOOLS_BUILD=16111833
ARG CMDLINE_TOOLS_SHA256=0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8
ARG NDK_VERSION=29.0.14206865

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip openjdk-21-jre-headless \
 && rm -rf /var/lib/apt/lists/*

RUN archive="commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip" \
 && curl -fsSL --retry 5 "https://dl.google.com/android/repository/$archive" -o "/tmp/$archive" \
 && echo "$CMDLINE_TOOLS_SHA256  /tmp/$archive" | sha256sum -c - \
 && unzip -q "/tmp/$archive" -d /tmp \
 && sdkmanager=/tmp/cmdline-tools/bin/sdkmanager \
 && yes | "$sdkmanager" --sdk_root=/opt/android-sdk --licenses > /dev/null \
 && "$sdkmanager" --sdk_root=/opt/android-sdk \
      "platform-tools" "platforms;android-35" "platforms;android-36" "platforms;android-37.0" \
      "build-tools;35.0.0" "build-tools;36.0.0" "ndk;$NDK_VERSION" \
 && chmod -R a+rX /opt/android-sdk

FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NDK_VERSION=29.0.14206865
ARG NODE_VERSION=24.14.0
ARG NODE_SHA256=41cd79bb7877c81605a9e68ec4c91547774f46a40c67a17e34d7179ef11729df
ARG BUN_VERSION=1.4.2
ARG BUN_SHA256=36368faef7527875d5ffa52e53cd48021741f2a83eb6208a8dd64068d422a913
ARG RUST_VERSION=1.98.1
ARG RUST_TARGETS=aarch64-linux-android,armv7-linux-androideabi,x86_64-linux-android,i686-linux-android,x86_64-pc-windows-gnullvm,wasm32-wasip1
ARG BOLTFFI_VERSION=0.31.0
ARG LLVM_MINGW_VERSION=20260922
ARG LLVM_MINGW_SHA256=bb7bb7654b33d5aa8712acb837c963b2e0c56352560c76105270a3268c665c21
ARG TEMURIN_WINDOWS_VERSION=21.0.8+9
ARG WASI_SDK_VERSION=33
ARG WASI_SDK_SHA256=0ba8b5bfaeb2adf3f29bab5841d76cf5318ab8e1642ea195f88baba1abd47bce

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git openssh-client sudo just zstd xz-utils unzip \
      build-essential cmake openjdk-17-jdk-headless openjdk-21-jdk-headless \
      fakeroot dpkg-dev rpm makepkg pacman-package-manager libarchive-tools nsis \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -u 1001 -s /bin/bash ci \
 && echo 'ci ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ci \
 && printf '%s\n' 'retry = 5' retry-all-errors 'connect-timeout = 30' 'speed-limit = 1024' 'speed-time = 60' > ~/.curlrc

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_HOME=/opt/android-sdk/ndk/$NDK_VERSION \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    WASI_SDK_PATH=/opt/wasi-sdk \
    JAVA_HOME_x86_64_pc_windows_gnullvm=/opt/jdk-windows \
    CC_x86_64_pc_windows_gnullvm=x86_64-w64-mingw32-clang \
    AR_x86_64_pc_windows_gnullvm=llvm-ar \
    CARGO_TARGET_X86_64_PC_WINDOWS_GNULLVM_LINKER=x86_64-w64-mingw32-clang \
    PATH=/usr/local/cargo/bin:/opt/llvm-mingw/bin:/opt/android-sdk/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH

COPY --from=android-sdk /opt/android-sdk /opt/android-sdk

RUN archive="node-v$NODE_VERSION-linux-x64.tar.xz" \
 && curl -fsSL "https://nodejs.org/dist/v$NODE_VERSION/$archive" -o "/tmp/$archive" \
 && echo "$NODE_SHA256  /tmp/$archive" | sha256sum -c - \
 && tar -xJf "/tmp/$archive" -C /usr/local --strip-components=1 --exclude='*.md' --exclude=LICENSE \
 && rm "/tmp/$archive"

RUN curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/bun-linux-x64.zip" -o /tmp/bun.zip \
 && echo "$BUN_SHA256  /tmp/bun.zip" | sha256sum -c - \
 && unzip -q -j /tmp/bun.zip bun-linux-x64/bun -d /usr/local/bin \
 && rm /tmp/bun.zip

RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal \
      --default-toolchain "$RUST_VERSION" --component rustfmt,clippy --target "$RUST_TARGETS" \
 && cargo install boltffi_cli --version "=$BOLTFFI_VERSION" --locked \
 && rm -rf "$CARGO_HOME/registry" "$CARGO_HOME/git" \
 && chown -R ci:ci "$CARGO_HOME"

RUN archive="llvm-mingw-$LLVM_MINGW_VERSION-ucrt-ubuntu-22.04-x86_64.tar.xz" \
 && curl -fsSL "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VERSION/$archive" -o "/tmp/$archive" \
 && echo "$LLVM_MINGW_SHA256  /tmp/$archive" | sha256sum -c - \
 && tar -xJf "/tmp/$archive" -C /opt \
 && mv "/opt/${archive%.tar.xz}" /opt/llvm-mingw \
 && rm -rf "/tmp/$archive" /opt/llvm-mingw/i686-w64-mingw32 /opt/llvm-mingw/aarch64-w64-mingw32 /opt/llvm-mingw/armv7-w64-mingw32

RUN version="$TEMURIN_WINDOWS_VERSION" \
 && archive="OpenJDK21U-jdk_x64_windows_hotspot_${version/+/_}.zip" \
 && url="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${version/+/%2B}" \
 && cd /tmp \
 && curl -fsSLO "$url/$archive" && curl -fsSLO "$url/$archive.sha256.txt" \
 && sha256sum -c "$archive.sha256.txt" \
 && unzip -q "$archive" -d /opt && mv "/opt/jdk-$version" /opt/jdk-windows \
 && rm "$archive" "$archive.sha256.txt"

RUN archive="wasi-sdk-$WASI_SDK_VERSION.0-x86_64-linux.tar.gz" \
 && curl -fsSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-$WASI_SDK_VERSION/$archive" -o "/tmp/$archive" \
 && echo "$WASI_SDK_SHA256  /tmp/$archive" | sha256sum -c - \
 && tar -xzf "/tmp/$archive" -C /opt \
 && mv "/opt/wasi-sdk-$WASI_SDK_VERSION.0-x86_64-linux" /opt/wasi-sdk \
 && rm "/tmp/$archive"

RUN install -d -o ci -g ci /opt/hostedtoolcache

USER ci
WORKDIR /home/ci
