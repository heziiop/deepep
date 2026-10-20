#!/bin/bash
set -e

# 切换目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/../tests" || { echo "目录不存在"; exit 1; }

# 设置参数范围
indexes=(0 1 2 3 4)
H_LIST=(7168 6144 2048 4096 6144)
GMM1_HIDDEN_LIST=(4096 4096 1536 3072 5120)
SCRIPT="test_fused_deep_moe.py"

# 执行测试
for index in "${indexes[@]}";do

    echo "Running: python $SCRIPT --hidden ${H_LIST[$index]} --moe-intermediate-size ${GMM1_HIDDEN_LIST[$index]}"
    if python "$SCRIPT" --hidden "${H_LIST[$index]}" --moe-intermediate-size "${GMM1_HIDDEN_LIST[$index]}"; then
        echo "测试 hidden=${H_LIST[$index]} moe_intermediate_size=${GMM1_HIDDEN_LIST[$index]} 成功"
    else
        echo "测试 hidden=${H_LIST[$index]} moe_intermediate_size=${GMM1_HIDDEN_LIST[$index]} 失败，退出码: $?"
        exit 1
    fi

    echo "-------------------------------------"
done

cd ./
