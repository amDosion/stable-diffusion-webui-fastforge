# Use an official lightweight Python base image
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04

# Set the working directory in the container
WORKDIR /app

RUN echo "🔧 [1.1] 设置系统时区为 ${TZ}..." && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    echo "✅ [1.1] 时区设置完成"

# ================================================================
# 🧱 2.1 安装 Python 3.11 + 基础系统依赖
# ================================================================
RUN echo "🔧 [2.1] 安装 Python 3.11 及系统依赖..." && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y jq && \
    apt-get install -y --no-install-recommends \
        python3.11 python3.11-venv python3.11-dev \
        wget git git-lfs curl procps bc \
        libgl1 libgl1-mesa-glx libglvnd0 \
        libglib2.0-0 libsm6 libxrender1 libxext6 \
        xvfb build-essential \
        libgoogle-perftools-dev \
        sentencepiece \
        libgtk2.0-dev libgtk-3-dev libjpeg-dev libpng-dev libtiff-dev \
        libopenblas-base libopenmpi-dev \
        apt-transport-https htop nano bsdmainutils \
        lsb-release software-properties-common \
        libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
        libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev && \
    echo "✅ [2.1] 系统依赖安装完成" && \
    curl -sSL https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.11 get-pip.py && \
    rm get-pip.py && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ [2.1] Python 3.11 设置完成"

# ================================================================
# 🧱 2.2 安装构建工具 pip/wheel/setuptools/cmake/ninja
# ================================================================
RUN echo "🔧 [2.2] 安装 Python 构建工具..." && \
    python3.11 -m pip install --upgrade pip setuptools wheel cmake ninja --no-cache-dir && \
    echo "✅ [2.2] 构建工具安装完成"

# ================================================================
# 🧱 2.3 安装 xformers 所需 C++ 系统构建依赖
# ================================================================
RUN echo "🔧 [2.3] 安装 xformers C++ 构建依赖..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    g++ ninja-build zip unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ [2.3] xformers 构建依赖安装完成"

# ================================================================
# 🧱 2.4 编译安装 GCC 12.4.0（适配 TensorFlow 构建）
# ================================================================
RUN echo "🔧 安装 GCC 12.4.0..." && \
    apt-get update && \
    apt-get install -y libgmp-dev libmpfr-dev libmpc-dev flex bison file && \
    cd /tmp && \
    wget https://ftp.gnu.org/gnu/gcc/gcc-12.4.0/gcc-12.4.0.tar.xz && \
    tar -xf gcc-12.4.0.tar.xz && cd gcc-12.4.0 && \
    mkdir build && cd build && \
    ../configure \
        --disable-bootstrap \
        --disable-libstdcxx-pch \
        --disable-nls \
        --disable-multilib \
        --disable-werror \
        --enable-languages=c,c++ \
        --without-included-gettext \
        --prefix=/opt/gcc-12.4 \
        --with-gmp=/usr \
        --with-mpfr=/usr \
        --with-mpc=/usr && \
    make -j"$(nproc)" && \
    make install && \
    ln -sf /opt/gcc-12.4/bin/gcc /usr/local/bin/gcc && \
    ln -sf /opt/gcc-12.4/bin/g++ /usr/local/bin/g++ && \
    cd / && rm -rf /tmp/gcc-12.4.0* && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ GCC 12.4 安装完成"

# ================================================================
# 🧠 安装 LLVM/Clang 20 + 设置 apt 源 + gpg key
# ================================================================
RUN mkdir -p /usr/share/keyrings && \
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | \
    gpg --dearmor -o /usr/share/keyrings/llvm-archive-keyring.gpg && \
    echo "✅ LLVM GPG Key 安装完成"

RUN echo "deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] http://apt.llvm.org/jammy/ llvm-toolchain-jammy-20 main" \
    > /etc/apt/sources.list.d/llvm-toolchain-jammy-20.list && \
    echo "✅ 已添加 LLVM apt 软件源"

RUN apt-get update && echo "✅ APT 软件源更新完成"

RUN apt-get install -y --no-install-recommends \
    clang-20 clangd-20 clang-format-20 clang-tidy-20 \
    libclang-common-20-dev libclang-20-dev libclang1-20 \
    lld-20 llvm-20 llvm-20-dev llvm-20-runtime \
    llvm-20-tools libomp-20-dev \
    libc++-20-dev libc++abi-20-dev && \
    echo "✅ LLVM/Clang 20 及依赖组件安装完成"

RUN ln -sf /usr/bin/clang-20 /usr/bin/clang && \
    ln -sf /usr/bin/clang++-20 /usr/bin/clang++ && \
    ln -sf /usr/bin/llvm-config-20 /usr/bin/llvm-config && \
    echo "✅ 创建 clang/clang++/llvm-config 别名完成"

RUN echo "✅ LLVM 工具链版本信息如下：" && \
    echo "🔹 clang:        $(clang --version | head -n1)" && \
    echo "🔹 clang++:      $(clang++ --version | head -n1)" && \
    echo "🔹 ld.lld:       $(ld.lld-20 --version)" && \
    echo "🔹 llvm-config:  $(llvm-config --version)"

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* && \
    echo "🧹 LLVM 安装完成，APT 缓存已清理"

# ================================================================
# 🧱 2.5 安装 TensorFlow 源码构建依赖
# ================================================================
RUN echo "🔧 [2.5] 安装 TensorFlow 构建依赖..." && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    zlib1g-dev libcurl4-openssl-dev libssl-dev liblzma-dev \
    libtool autoconf automake python-is-python3 \
    expect && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ [2.5] TensorFlow 编译依赖安装完成"

RUN echo "🔧 [2.6] 安装 NCCL 2.25.1 (dev + lib)..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    libnccl2=2.25.1-1+cuda12.8 \
    libnccl-dev=2.25.1-1+cuda12.8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /root/.cache /tmp/* && \
    echo "✅ [2.6] NCCL 安装完成"

RUN if [ -L /usr/local/cuda-12.8/lib/lib64 ]; then \
      echo '⚠️ 递归软链接检测: 修复 /usr/local/cuda-12.8/lib'; \
      rm -rf /usr/local/cuda-12.8/lib && \
      ln -s /usr/local/cuda-12.8/lib64 /usr/local/cuda-12.8/lib; \
    fi

RUN apt-get update && apt-get install -y --reinstall cuda-cudart-dev-12-8 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo "🔍 [2.6] 检查 CUDA / cuDNN / NCCL 安装状态..." && \
    echo "====================== CUDA ======================" && \
    nvcc --version || echo "❌ nvcc 不存在" && \
    echo "📁 CUDA 路径检测：" && \
    ls -l /usr/local/cuda* || echo "❌ 未找到 /usr/local/cuda*" && \
    echo "🔍 libcudart 路径：" && \
    find /usr -name "libcudart*" 2>/dev/null || echo "❌ 未找到 libcudart*" && \
    echo "===================== cuDNN ======================" && \
    echo "🔍 cudnn.h 路径：" && \
    find /usr -name "cudnn.h" 2>/dev/null || echo "❌ 未找到 cudnn.h" && \
    echo "🔍 libcudnn.so 路径：" && \
    find /usr -name "libcudnn.so*" 2>/dev/null || echo "❌ 未找到 libcudnn.so*" && \
    echo "===================== NCCL =======================" && \
    dpkg -l | grep nccl || echo "⚠️ 未通过 dpkg 查询到 NCCL 安装信息" && \
    echo "🔍 libnccl 路径：" && \
    find /usr -name "libnccl.so*" 2>/dev/null || echo "❌ 未找到 libnccl.so*" && \
    echo "🔍 nccl.h 路径：" && \
    find /usr -name "nccl.h" 2>/dev/null || echo "❌ 未找到 nccl.h" && \
    echo "==================================================" && \
    echo "✅ [2.6] CUDA / cuDNN / NCCL 检查完成"

# ================================================================
# 🧱 3.1 安装 PyTorch Nightly + Torch-TensorRT
# ================================================================
RUN echo "🔧 [3.1] 安装 PyTorch Nightly..." && \
    python3.11 -m pip install --upgrade pip && \
    python3.11 -m pip install --pre \
        torch==2.8.0.dev20250326+cu128 \
        torchvision==0.22.0.dev20250326+cu128 \
        torchaudio==2.6.0.dev20250326+cu128 \
        torch-tensorrt==2.7.0.dev20250326+cu128 \
        --extra-index-url https://download.pytorch.org/whl/nightly/cu128 \
        --no-cache-dir && \
    rm -rf /root/.cache /tmp/* ~/.cache && \
    echo "✅ [3.1] PyTorch 安装完成"

# ================================================================
# 🧱 3.2 安装 Python 推理相关依赖
# ================================================================
RUN echo "🔧 [3.2] 安装额外 Python 包..." && \
    python3.11 -m pip install --no-cache-dir \
        numpy scipy opencv-python scikit-learn Pillow insightface && \
    rm -rf /root/.cache /tmp/* ~/.cache && \
    echo "✅ [3.2] 其他依赖安装完成"

# ================================================================
# 🧱 3.3 安装 Bazelisk（自动管理 Bazel）
# ================================================================
RUN echo "🔧 [3.3] 安装 Bazelisk..." && \
    mkdir -p /usr/local/bin && \
    curl -fsSL https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-linux-amd64 \
    -o /usr/local/bin/bazelisk && \
    chmod +x /usr/local/bin/bazelisk && \
    ln -sf /usr/local/bin/bazelisk /usr/local/bin/bazel && \
    rm -rf /root/.cache /tmp/* ~/.cache && \
    echo "✅ [3.3] Bazelisk 安装完成"

# Clone repositories with error handling
RUN echo "  - 克隆 stable-diffusion-webui-assets 仓库..." && \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui-assets.git "repositories/stable-diffusion-webui-assets" || { \
    echo "❌ 克隆 stable-diffusion-webui-assets 仓库失败"; exit 1; } && \
    echo "  - 克隆 huggingface_guess 仓库..." && \
    git clone https://github.com/lllyasviel/huggingface_guess.git "repositories/huggingface_guess" || { \
    echo "❌ 克隆 huggingface_guess 仓库失败"; exit 1; } && \
    echo "  - 克隆 BLIP 仓库..." && \
    git clone https://github.com/salesforce/BLIP.git "repositories/BLIP" || { \
    echo "❌ 克隆 BLIP 仓库失败"; exit 1; } && \
    echo "  - 克隆 google_blockly_prototypes 仓库..." && \
    git clone https://github.com/lllyasviel/google_blockly_prototypes.git "repositories/google_blockly_prototypes" || { \
    echo "❌ 克隆 google_blockly_prototypes 仓库失败"; exit 1; }

# ================================================================
RUN echo "🔧 [5] 补丁修正 requirements_versions.txt..." && \
    REQ_FILE="/app/requirements_versions.txt" && \
    touch "$REQ_FILE" && \
    add_or_replace_requirement() { \
        local package="$1"; \
        local version="$2"; \
        if grep -q "^$package==" "$REQ_FILE"; then \
            echo "🔁 替换: $package==... → $package==$version"; \
            sed -i "s|^$package==.*|$package==$version|" "$REQ_FILE"; \
        else \
            echo "➕ 追加: $package==$version"; \
            echo "$package==$version" >> "$REQ_FILE"; \
        fi; \
    } && \
    add_or_replace_requirement "xformers" "0.0.29.post3" && \
    add_or_replace_requirement "diffusers" "0.31.0" && \
    add_or_replace_requirement "transformers" "4.46.1" && \
    add_or_replace_requirement "torchdiffeq" "0.2.3" && \
    add_or_replace_requirement "torchsde" "0.2.6" && \
    add_or_replace_requirement "protobuf" "4.25.3" && \
    add_or_replace_requirement "pydantic" "2.6.4" && \
    add_or_replace_requirement "open-clip-torch" "2.24.0" && \
    add_or_replace_requirement "GitPython" "3.1.41" && \
    echo "🧹 清理注释内容..." && \
    CLEANED_REQ_FILE="${REQ_FILE}.cleaned" && \
    sed 's/#.*//' "$REQ_FILE" | sed '/^\s*$/d' > "$CLEANED_REQ_FILE" && \
    mv "$CLEANED_REQ_FILE" "$REQ_FILE" && \
    echo "📄 最终依赖列表如下：" && \
    cat "$REQ_FILE" && \
    echo "📦 最终依赖列表如下：" && \
    grep -E '^(xformers|diffusers|transformers|torchdiffeq|torchsde|GitPython|protobuf|pydantic|open-clip-torch)=' "$REQ_FILE" | sort && \
    echo "📥 安装主依赖 requirements_versions.txt ..." && \
    DEPENDENCIES_INFO_URL="https://raw.githubusercontent.com/amDosion/SD-webui-forge/main/dependencies_info.json" && \
    DEPENDENCIES_INFO=$(curl -s "$DEPENDENCIES_INFO_URL") && \
    sed -i 's/\r//' "$REQ_FILE" && \
    while IFS= read -r line || [[ -n "$line" ]]; do \
        line=$(echo "$line" | sed 's/#.*//' | xargs) && \
        [[ -z "$line" ]] && continue && \
        if [[ "$line" == *"=="* ]]; then \
            package_name=$(echo "$line" | cut -d'=' -f1 | xargs) && \
            package_version=$(echo "$line" | cut -d'=' -f3 | xargs); \
        else \
            package_name=$(echo "$line" | xargs) && \
            package_version=$(echo "$DEPENDENCIES_INFO" | jq -r --arg pkg "$package_name" '.[$pkg].version // empty') && \
            if [[ -z "$package_version" || "$package_version" == "null" ]]; then \
                echo "⚠️ 警告: 未指定 $package_name 的版本，且 JSON 中也未找到版本信息，跳过"; \
                continue; \
            else \
                echo "ℹ️ 来自 JSON 的版本补全：$package_name==$package_version"; \
            fi; \
        fi; \
        description=$(echo "$DEPENDENCIES_INFO" | jq -r --arg pkg "$package_name" '.[$pkg].description // empty') && \
        [[ -n "$description" ]] && echo "📘 说明: $description" || echo "⚠️ 警告: 未找到 $package_name 的描述信息，继续执行..." && \
        echo "📦 安装 ${package_name}==${package_version}" && \
        pip install "${package_name}==${package_version}" --extra-index-url "$PIP_EXTRA_INDEX_URL" 2>&1 | tee -a "$LOG_FILE" | sed 's/^Successfully installed/✅ 成功安装/'; \
    done < "$REQ_FILE"


# ================================================================
# 🧱 3.0 解析下载开关环境变量
# ================================================================
RUN echo "🔧 [2] 解析下载开关环境变量 (默认全部启用)..." && \
    # 解析全局下载开关
    ENABLE_DOWNLOAD_ALL="${ENABLE_DOWNLOAD:-true}" && \
    ENABLE_DOWNLOAD_EXTS="${ENABLE_DOWNLOAD_EXTS:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_MODEL_SD15="${ENABLE_DOWNLOAD_MODEL_SD15:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_MODEL_SDXL="${ENABLE_DOWNLOAD_MODEL_SDXL:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_MODEL_FLUX="${ENABLE_DOWNLOAD_MODEL_FLUX:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_VAE_FLUX="${ENABLE_DOWNLOAD_VAE_FLUX:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_TE_FLUX="${ENABLE_DOWNLOAD_TE_FLUX:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_CNET_SD15="${ENABLE_DOWNLOAD_CNET_SD15:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_CNET_SDXL="${ENABLE_DOWNLOAD_CNET_SDXL:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_CNET_FLUX="${ENABLE_DOWNLOAD_CNET_FLUX:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_VAE="${ENABLE_DOWNLOAD_VAE:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_LORAS="${ENABLE_DOWNLOAD_LORAS:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_EMBEDDINGS="${ENABLE_DOWNLOAD_EMBEDDINGS:-$ENABLE_DOWNLOAD_ALL}" && \
    ENABLE_DOWNLOAD_UPSCALERS="${ENABLE_DOWNLOAD_UPSCALERS:-$ENABLE_DOWNLOAD_ALL}" && \
    USE_HF_MIRROR="${USE_HF_MIRROR:-false}" && \
    USE_GIT_MIRROR="${USE_GIT_MIRROR:-false}" && \
    echo "  - 下载总开关        (ENABLE_DOWNLOAD_ALL): ${ENABLE_DOWNLOAD_ALL}" && \
    echo "  - 下载 Extensions   (ENABLE_DOWNLOAD_EXTS): ${ENABLE_DOWNLOAD_EXTS}" && \
    echo "  - 下载 Checkpoint SD1.5 (ENABLE_DOWNLOAD_MODEL_SD15): ${ENABLE_DOWNLOAD_MODEL_SD15}" && \
    echo "  - 下载 Checkpoint SDXL  (ENABLE_DOWNLOAD_MODEL_SDXL): ${ENABLE_DOWNLOAD_MODEL_SDXL}" && \
    echo "  - 下载 Checkpoint FLUX (ENABLE_DOWNLOAD_MODEL_FLUX): ${ENABLE_DOWNLOAD_MODEL_FLUX}" && \
    echo "  - 下载 VAE FLUX       (ENABLE_DOWNLOAD_VAE_FLUX): ${ENABLE_DOWNLOAD_VAE_FLUX}" && \
    echo "  - 下载 TE FLUX        (ENABLE_DOWNLOAD_TE_FLUX): ${ENABLE_DOWNLOAD_TE_FLUX}" && \
    echo "  - 下载 ControlNet SD1.5 (ENABLE_DOWNLOAD_CNET_SD15): ${ENABLE_DOWNLOAD_CNET_SD15}" && \
    echo "  - 下载 ControlNet SDXL  (ENABLE_DOWNLOAD_CNET_SDXL): ${ENABLE_DOWNLOAD_CNET_SDXL}" && \
    echo "  - 下载 ControlNet FLUX  (ENABLE_DOWNLOAD_CNET_FLUX): ${ENABLE_DOWNLOAD_CNET_FLUX}" && \
    echo "  - 下载 通用 VAE     (ENABLE_DOWNLOAD_VAE): ${ENABLE_DOWNLOAD_VAE}" && \
    echo "  - 下载 LoRAs/LyCORIS (ENABLE_DOWNLOAD_LORAS): ${ENABLE_DOWNLOAD_LORAS}" && \
    echo "  - 下载 Embeddings   (ENABLE_DOWNLOAD_EMBEDDINGS): ${ENABLE_DOWNLOAD_EMBEDDINGS}" && \
    echo "  - 下载 Upscalers    (ENABLE_DOWNLOAD_UPSCALERS): ${ENABLE_DOWNLOAD_UPSCALERS}" && \
    echo "  - 是否使用 HF 镜像  (USE_HF_MIRROR): ${USE_HF_MIRROR}" && \
    echo "  - 是否使用 Git 镜像 (USE_GIT_MIRROR): ${USE_GIT_MIRROR}" && \
    echo "  - 禁用的 TCMalloc (NO_TCMALLOC): ${NO_TCMALLOC}" && \
    echo "  - pip 额外索引 (PIP_EXTRA_INDEX_URL): ${PIP_EXTRA_INDEX_URL} (用于 PyTorch Nightly cu128)"

# ================================================================
# 🧱 3.1 网络连通性测试
# ================================================================
RUN echo "🌐 [8] 网络连通性测试..." && \
    NET_OK=false && \
    if curl -fsS --connect-timeout 5 https://huggingface.co > /dev/null; then \
        NET_OK=true; \
        echo "  - ✅ 网络连通 (huggingface.co 可访问)"; \
    else \
        if curl -fsS --connect-timeout 5 https://github.com > /dev/null; then \
            NET_OK=true; \
            echo "  - ⚠️ huggingface.co 无法访问，但 github.com 可访问。部分模型下载可能受影响。"; \
        else \
            echo "  - ❌ 网络不通 (无法访问 huggingface.co 和 github.com)。资源下载和插件更新将失败！"; \
        fi \
    fi

# ================================================================
# 🧱 3.2 资源下载处理
# ================================================================
RUN echo "📦 [9] 处理资源下载..." && \
    RESOURCE_PATH="/app/webui/resources.txt" && \
    if [ ! -f "$RESOURCE_PATH" ]; then \
        DEFAULT_RESOURCE_URL="https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt"; \
        echo "  - 未找到本地 resources.txt，尝试从 ${DEFAULT_RESOURCE_URL} 下载..."; \
        curl -fsSL -o "$RESOURCE_PATH" "$DEFAULT_RESOURCE_URL"; \
        if [ $? -eq 0 ]; then \
            echo "  - ✅ 默认 resources.txt 下载成功。"; \
        else \
            echo "  - ❌ 下载默认 resources.txt 失败。"; \
            touch "$RESOURCE_PATH"; \
        fi; \
    else \
        echo "  - ✅ 使用本地已存在的 resources.txt: ${RESOURCE_PATH}"; \
    fi

# ================================================================
# 🧱 3.0 克隆或更新 Git 仓库 / 下载文件
# ================================================================
RUN echo "🔧 [3.0] 函数: 克隆仓库/下载文件..." && \
    # 定义函数：克隆或更新 Git 仓库 (支持独立 Git 镜像开关)
    clone_or_update_repo() { \
        local dir="$1" repo_original="$2"; \
        local dirname; \
        local repo_url; \
        dirname=$(basename "$dir"); \
        if [[ "$USE_GIT_MIRROR" == "true" && "$repo_original" == "https://github.com/"* ]]; then \
            local git_mirror_host; \
            git_mirror_host=$(echo "$GIT_MIRROR_URL" | sed 's|https://||; s|http://||; s|/.*||'); \
            repo_url=$(echo "$repo_original" | sed "s|github.com|$git_mirror_host|"); \
            echo "    - 使用镜像转换 (Git): $repo_original -> $repo_url"; \
        else \
            repo_url="$repo_original"; \
        fi; \
        if [[ "$ENABLE_DOWNLOAD_EXTS" != "true" ]]; then \
            if [ -d "$dir" ]; then \
                echo "    - ⏭️ 跳过更新扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"; \
            else \
                echo "    - ⏭️ 跳过克隆扩展/仓库 (ENABLE_DOWNLOAD_EXTS=false): $dirname"; \
            fi; \
            return; \
        fi; \
        if [ -d "$dir/.git" ]; then \
            echo "    - 🔄 更新扩展/仓库: $dirname (from $repo_url)"; \
            (cd "$dir" && git pull --ff-only) || echo "      ⚠️ Git pull 失败: $dirname"; \
        elif [ ! -d "$dir" ]; then \
            echo "    - 📥 克隆扩展/仓库: $repo_url -> $dirname (完整克隆)"; \
            git clone --recursive "$repo_url" "$dir" || echo "      ❌ Git clone 失败: $dirname"; \
        else \
            echo "    - ✅ 目录已存在但非 Git 仓库，跳过 Git 操作: $dirname"; \
        fi; \
    }; \
    # 定义函数：下载文件 (支持独立 HF 镜像开关)
    download_with_progress() { \
        local output_path="$1" url_original="$2" type="$3" enabled_flag="$4"; \
        local filename; \
        local download_url; \
        filename=$(basename "$output_path"); \
        if [[ "$enabled_flag" != "true" ]]; then \
            echo "    - ⏭️ 跳过下载 ${type} (开关 '$enabled_flag' != 'true'): $filename"; \
            return; \
        fi; \
        if [[ "$NET_OK" != "true" ]]; then \
            echo "    - ❌ 跳过下载 ${type} (网络不通): $filename"; \
            return; \
        fi; \
        if [[ "$USE_HF_MIRROR" == "true" && "$url_original" == "https://huggingface.co/"* ]]; then \
            download_url=$(echo "$url_original" | sed "s|https://huggingface.co|$HF_MIRROR_URL|"); \
            echo "    - 使用镜像转换 (HF): $url_original -> $download_url"; \
        else \
            download_url="$url_original"; \
        fi; \
        if [ ! -f "$output_path" ]; then \
            echo "    - ⬇️ 下载 ${type}: $filename (from $download_url)"; \
            mkdir -p "$(dirname "$output_path")"; \
            wget --progress=bar:force:noscroll --timeout=120 -O "$output_path" "$download_url"; \
            if [ $? -ne 0 ]; then \
                echo "      ❌ 下载失败: $filename from $download_url"; \
                rm -f "$output_path"; \
            else \
                echo "      ✅ 下载完成: $filename"; \
            fi; \
        else \
            echo "    - ✅ 文件已存在，跳过下载 ${type}: $filename"; \
        fi; \
    }

# ================================================================
# 🧱 3.1 继续处理资源下载
# ================================================================
RUN echo "📦 [9] 处理资源下载..." && \
    RESOURCE_PATH="/app/webui/resources.txt" && \
    if [ ! -f "$RESOURCE_PATH" ]; then \
        DEFAULT_RESOURCE_URL="https://raw.githubusercontent.com/chuan1127/SD-webui-forge/main/resources.txt"; \
        echo "  - 未找到本地 resources.txt，尝试从 ${DEFAULT_RESOURCE_URL} 下载..."; \
        curl -fsSL -o "$RESOURCE_PATH" "$DEFAULT_RESOURCE_URL"; \
        if [ $? -eq 0 ]; then \
            echo "  - ✅ 默认 resources.txt 下载成功。"; \
        else \
            echo "  - ❌ 下载默认 resources.txt 失败。"; \
            touch "$RESOURCE_PATH"; \
        fi; \
    else \
        echo "  - ✅ 使用本地已存在的 resources.txt: ${RESOURCE_PATH}"; \
    fi && \
    echo "  - 开始处理 resources.txt 中的条目..." && \
    while IFS=, read -r target_path source_url || [[ -n "$target_path" ]]; do \
        target_path=$(echo "$target_path" | xargs) && \
        source_url=$(echo "$source_url" | xargs) && \
        [[ "$target_path" =~ ^#.*$ || -z "$target_path" || -z "$source_url" ]] && continue && \
        if should_skip "$target_path"; then \
            echo "    - ⛔ 跳过黑名单条目: $target_path"; \
            continue; \
        fi && \
        case "$target_path" in \
            extensions/*) \
                clone_or_update_repo "$target_path" "$source_url"; \
                ;; \
            models/Stable-diffusion/SD1.5/*) \
                download_with_progress "$target_path" "$source_url" "SD 1.5 Checkpoint" "$ENABLE_DOWNLOAD_MODEL_SD15"; \
                ;; \
            models/Stable-diffusion/XL/*) \
                download_with_progress "$target_path" "$source_url" "SDXL Checkpoint" "$ENABLE_DOWNLOAD_MODEL_SDXL"; \
                ;; \
            models/Stable-diffusion/flux/*) \
                download_with_progress "$target_path" "$source_url" "FLUX Checkpoint" "$ENABLE_DOWNLOAD_MODEL_FLUX"; \
                ;; \
            models/Stable-diffusion/*) \
                echo "    - ❓ 处理未分类 Stable Diffusion 模型: $target_path (默认使用 SD1.5 开关)"; \
                download_with_progress "$target_path" "$source_url" "SD 1.5 Checkpoint (Fallback)" "$ENABLE_DOWNLOAD_MODEL_SD15"; \
                ;; \
            models/VAE/flux-*.safetensors) \
                download_with_progress "$target_path" "$source_url" "FLUX VAE" "$ENABLE_DOWNLOAD_VAE_FLUX"; \
                ;; \
            models/VAE/*) \
                download_with_progress "$target_path" "$source_url" "VAE Model" "$ENABLE_DOWNLOAD_VAE"; \
                ;; \
            models/text_encoder/*) \
                download_with_progress "$target_path" "$source_url" "Text Encoder (FLUX)" "$ENABLE_DOWNLOAD_TE_FLUX"; \
                ;; \
            models/ControlNet/*) \
                if [[ "$target_path" == *sdxl* || "$target_path" == *SDXL* ]]; then \
                    download_with_progress "$target_path" "$source_url" "ControlNet SDXL" "$ENABLE_DOWNLOAD_CNET_SDXL"; \
                elif [[ "$target_path" == *flux* || "$target_path" == *FLUX* ]]; then \
                    download_with_progress "$target_path" "$source_url" "ControlNet FLUX" "$ENABLE_DOWNLOAD_CNET_FLUX"; \
                elif [[ "$target_path" == *sd15* || "$target_path" == *SD15* || "$target_path" == *v11p* || "$target_path" == *v11e* || "$target_path" == *v11f* ]]; then \
                    download_with_progress "$target_path" "$source_url" "ControlNet SD 1.5" "$ENABLE_DOWNLOAD_CNET_SD15"; \
                else \
                    echo "    - ❓ 处理未分类 ControlNet 模型: $target_path (默认使用 SD1.5 ControlNet 开关)"; \
                    download_with_progress "$target_path" "$source_url" "ControlNet SD 1.5 (Fallback)" "$ENABLE_DOWNLOAD_CNET_SD15"; \
                fi \
                ;; \
            models/Lora/* | models/LyCORIS/* | models/LoCon/*) \
                download_with_progress "$target_path" "$source_url" "LoRA/LyCORIS" "$ENABLE_DOWNLOAD_LORAS"; \
                ;; \
            models/TextualInversion/* | embeddings/*) \
                download_with_progress "$target_path" "$source_url" "Embedding/Textual Inversion" "$ENABLE_DOWNLOAD_EMBEDDINGS"; \
                ;; \
            models/Upscaler/* | models/ESRGAN/*) \
                download_with_progress "$target_path" "$source_url" "Upscaler Model" "$ENABLE_DOWNLOAD_UPSCALERS"; \
                ;; \
            *) \
                if [[ "$source_url" == *.git ]]; then \
                    echo "    - ❓ 处理未分类 Git 仓库: $target_path"; \
                    clone_or_update_repo "$target_path" "$source_url"; \
                elif [[ "$source_url" == http* ]]; then \
                    echo "    - ❓ 处理未分类文件下载: $target_path"; \
                    download_with_progress "$target_path" "$source_url" "Unknown Model/File" "$ENABLE_DOWNLOAD_MODEL_SD15"; \
                else \
                    echo "    - ❓ 无法识别的资源类型或无效 URL: target='$target_path', source='$source_url'"; \
                fi; \
                ;; \
        esac; \
    done < "$RESOURCE_PATH" && \
    echo "✅ 资源下载处理完成。"


# Copy the rest of the application files
COPY . .

# Set environment variables to streamline application performance
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Expose the port the application will run on
EXPOSE 7860

# Set the default command to run the application
CMD ["python", "webui.py", "--skip-python-version-check" , "--skip-version-check", "--skip-torch-cuda-test", "--xformers", "--cuda-stream", "--cuda-malloc", "--no-half-vae", "--no-hashing", "--upcast-sampling", "--disable-nan-check", "--listen", "--port=7860"]
