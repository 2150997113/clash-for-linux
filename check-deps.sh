#!/usr/bin/env bash
# =========================
# 依赖检查脚本
# 检查 make 和 just 是否安装
# =========================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

check_make() {
    if command -v make &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} make 已安装: $(make --version | head -1)"
        return 0
    else
        echo -e "${YELLOW}[MISS]${NC} make 未安装"
        return 1
    fi
}

check_just() {
    if command -v just &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} just 已安装: $(just --version)"
        return 0
    else
        echo -e "${YELLOW}[MISS]${NC} just 未安装"
        return 1
    fi
}

install_make() {
    echo ""
    echo "正在安装 make..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y make
    elif command -v yum &> /dev/null; then
        sudo yum install -y make
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y make
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm make
    else
        echo -e "${RED}[ERROR]${NC} 无法自动安装，请手动安装 make"
        return 1
    fi
}

install_just() {
    echo ""
    echo "正在安装 just..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y just
    elif command -v yum &> /dev/null; then
        sudo yum install -y just
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y just
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm just
    elif command -v brew &> /dev/null; then
        brew install just
    else
        echo -e "${RED}[ERROR]${NC} 无法自动安装，请手动安装 just"
        echo "  参考: https://github.com/casey/just#installation"
        return 1
    fi
}

main() {
    local need_make=false
    local need_just=false

    echo "▶ 检查依赖"
    echo "────────────────────────────────────────"

    check_make || need_make=true
    check_just || need_just=true

    if [ "$need_make" = false ] && [ "$need_just" = false ]; then
        echo ""
        echo -e "${GREEN}所有依赖已满足${NC}"
        return 0
    fi

    echo ""
    echo "▶ 安装缺失依赖"
    echo "────────────────────────────────────────"

    if [ "$need_make" = true ]; then
        install_make
    fi

    if [ "$need_just" = true ]; then
        install_just
    fi

    echo ""
    echo "▶ 再次检查"
    echo "────────────────────────────────────────"
    check_make
    check_just
    echo ""
    echo -e "${GREEN}依赖安装完成${NC}"
}

main "$@"
