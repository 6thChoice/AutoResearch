# 科研智能体系统 - 工具函数清单

## 1. 概述

本文档定义科研智能体系统中所有可用的工具函数，供各模块（特别是规划层 Agent 和 Coding Agent）调用。

### 1.1 工具分类

| 类别 | 说明 | 主要使用者 |
|------|------|-----------|
| **沙盒管理** | Docker 容器生命周期管理 | 规划层 Agent |
| **代码执行** | 代码编写、调试、运行 | Coding Agent |
| **实验追踪** | MLflow 等实验管理 | 规划层 Agent |
| **文献检索** | arXiv、论文数据库查询 | Idea 规范化模块 |
| **数据处理** | 数据集下载、预处理 | Coding Agent |
| **评估计算** | 指标计算、结果对比 | 结果分析模块 |
| **外部服务** | GitHub、云存储等 | 各模块 |

### 1.2 工具调用格式

```json
{
  "tool": "tool_name",
  "parameters": {
    "param1": "value1",
    "param2": "value2"
  },
  "timeout": 300,
  "callback": "optional_callback_id"
}
```

---

## 2. 沙盒管理工具

### 2.1 容器生命周期管理

#### `sandbox_create`

**功能**：创建新的实验沙盒

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 沙盒名称 |
| `image` | string | 否 | 基础镜像，默认 "opencode-research:latest" |
| `resources.cpus` | number | 否 | CPU 核心数，默认 4 |
| `resources.memory` | string | 否 | 内存限制，默认 "16g" |
| `resources.gpus` | number | 否 | GPU 数量，默认 0 |
| `volumes` | object | 否 | 挂载卷配置 |
| `environment` | object | 否 | 环境变量 |

**返回值**：

```json
{
  "sandbox_id": "sb_001",
  "status": "created",
  "container_id": "abc123",
  "endpoint": "http://localhost:8081"
}
```

**示例**：

```python
result = sandbox_create(
    name="transformer_baseline",
    resources={"cpus": 8, "memory": "32g", "gpus": 1},
    volumes={
        "/data": "/mnt/datasets:ro",
        "/results": "/mnt/results"
    }
)
```

---

#### `sandbox_load_from_image`

**功能**：从保存的镜像加载沙盒

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `image_name` | string | 是 | 镜像名称 |
| `new_name` | string | 是 | 新沙盒名称 |
| `resources` | object | 否 | 资源覆盖配置 |

**返回值**：

```json
{
  "sandbox_id": "sb_002",
  "source_image": "baseline_transformer_v1",
  "status": "loaded"
}
```

**示例**：

```python
result = sandbox_load_from_image(
    image_name="baseline_transformer_v1",
    new_name="transformer_idea_variant_a"
)
```

---

#### `sandbox_save_as_image`

**功能**：将沙盒保存为镜像

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `image_name` | string | 是 | 镜像名称 |
| `tags` | array | 否 | 标签列表 |
| `description` | string | 否 | 镜像描述 |

**返回值**：

```json
{
  "image_id": "img_001",
  "image_name": "baseline_transformer_v1",
  "size": "2.5GB",
  "saved_at": "2024-02-19T12:00:00Z"
}
```

**示例**：

```python
result = sandbox_save_as_image(
    sandbox_id="sb_001",
    image_name="baseline_transformer_v1",
    tags=["baseline", "transformer", "wmt14"],
    description="Standard Transformer baseline on WMT14"
)
```

---

#### `sandbox_destroy`

**功能**：销毁沙盒

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `force` | boolean | 否 | 是否强制删除，默认 false |
| `save_before_destroy` | boolean | 否 | 销毁前是否保存，默认 false |

**返回值**：

```json
{
  "sandbox_id": "sb_001",
  "status": "destroyed",
  "image_saved": false
}
```

---

#### `sandbox_list`

**功能**：列出所有活跃沙盒

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `status` | string | 否 | 过滤状态 |
| `tags` | array | 否 | 标签过滤 |

**返回值**：

```json
{
  "sandboxes": [
    {
      "sandbox_id": "sb_001",
      "name": "transformer_baseline",
      "status": "running",
      "resources": {"cpus": 8, "memory": "32g"},
      "created_at": "2024-02-19T10:00:00Z"
    }
  ]
}
```

---

### 2.2 沙盒操作

#### `sandbox_execute`

**功能**：在沙盒内执行命令

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `command` | string | 是 | 要执行的命令 |
| `workdir` | string | 否 | 工作目录，默认 "/workspace" |
| `timeout` | number | 否 | 超时时间（秒），默认 300 |
| `env` | object | 否 | 环境变量 |

**返回值**：

```json
{
  "exit_code": 0,
  "stdout": "...",
  "stderr": "...",
  "duration": 45.2
}
```

**示例**：

```python
result = sandbox_execute(
    sandbox_id="sb_001",
    command="python train.py --epochs 10",
    timeout=7200
)
```

---

#### `sandbox_copy_to`

**功能**：复制文件到沙盒

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `src` | string | 是 | 源文件路径（宿主机） |
| `dest` | string | 是 | 目标路径（沙盒内） |

**返回值**：

```json
{
  "success": true,
  "bytes_copied": 1024000
}
```

---

#### `sandbox_copy_from`

**功能**：从沙盒复制文件

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `src` | string | 是 | 源文件路径（沙盒内） |
| `dest` | string | 是 | 目标路径（宿主机） |

---

#### `sandbox_checkpoint`

**功能**：创建沙盒检查点

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `tag` | string | 是 | 检查点标签 |
| `description` | string | 否 | 描述 |

**返回值**：

```json
{
  "checkpoint_id": "cp_001",
  "tag": "after_baseline_training",
  "created_at": "2024-02-19T12:00:00Z"
}
```

---

#### `sandbox_rollback`

**功能**：回滚到检查点

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `checkpoint_id` | string | 是 | 检查点 ID |

---

#### `sandbox_get_metrics`

**功能**：获取沙盒资源使用指标

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |

**返回值**：

```json
{
  "cpu_usage_percent": 85.5,
  "memory_usage_mb": 8192,
  "memory_limit_mb": 32768,
  "gpu_usage_percent": 92.0,
  "gpu_memory_mb": 10240,
  "network_io": {"in": 1024000, "out": 512000}
}
```

---

### 2.3 批量沙盒操作

#### `sandbox_batch_create`

**功能**：批量创建沙盒（用于并行实验）

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `base_image` | string | 是 | 基础镜像 |
| `count` | number | 是 | 创建数量 |
| `name_prefix` | string | 是 | 名称前缀 |
| `resources` | object | 是 | 资源配置 |

**返回值**：

```json
{
  "created": [
    {"sandbox_id": "sb_001", "name": "exp_variant_1"},
    {"sandbox_id": "sb_002", "name": "exp_variant_2"}
  ]
}
```

---

## 3. 代码操作工具

### 3.1 文件操作

#### `file_read`

**功能**：读取文件内容

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `path` | string | 是 | 文件路径 |
| `limit` | number | 否 | 读取行数限制 |
| `offset` | number | 否 | 起始行号 |

---

#### `file_write`

**功能**：写入文件

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `path` | string | 是 | 文件路径 |
| `content` | string | 是 | 文件内容 |
| `append` | boolean | 否 | 是否追加，默认 false |

---

#### `file_edit`

**功能**：编辑文件（查找替换）

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `path` | string | 是 | 文件路径 |
| `old_string` | string | 是 | 旧字符串 |
| `new_string` | string | 是 | 新字符串 |

---

#### `file_glob`

**功能**：文件搜索

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `pattern` | string | 是 | Glob 模式 |
| `path` | string | 否 | 搜索路径 |

---

#### `file_grep`

**功能**：代码搜索

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `pattern` | string | 是 | 正则表达式 |
| `path` | string | 否 | 搜索路径 |
| `output_mode` | string | 否 | 输出模式 |

---

### 3.2 代码执行

#### `python_execute`

**功能**：执行 Python 代码

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `code` | string | 是 | Python 代码 |
| `timeout` | number | 否 | 超时时间 |

---

#### `bash_execute`

**功能**：执行 Bash 命令

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `command` | string | 是 | Bash 命令 |
| `timeout` | number | 否 | 超时时间 |
| `workdir` | string | 否 | 工作目录 |

---

#### `jupyter_execute`

**功能**：执行 Jupyter Notebook 单元格

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `notebook_path` | string | 是 | Notebook 路径 |
| `cell_index` | number | 否 | 指定单元格 |

---

## 4. 实验追踪工具

### 4.1 MLflow 集成

#### `mlflow_log_params`

**功能**：记录实验参数

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `experiment_id` | string | 是 | 实验 ID |
| `run_id` | string | 是 | Run ID |
| `params` | object | 是 | 参数字典 |

---

#### `mlflow_log_metrics`

**功能**：记录实验指标

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `experiment_id` | string | 是 | 实验 ID |
| `run_id` | string | 是 | Run ID |
| `metrics` | object | 是 | 指标字典 |
| `step` | number | 否 | 训练步数 |

---

#### `mlflow_log_artifact`

**功能**：记录实验产物

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `experiment_id` | string | 是 | 实验 ID |
| `run_id` | string | 是 | Run ID |
| `local_path` | string | 是 | 本地文件路径 |
| `artifact_path` | string | 否 | 产物路径 |

---

#### `mlflow_create_experiment`

**功能**：创建实验

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 实验名称 |
| `tags` | object | 否 | 标签 |

---

#### `mlflow_search_runs`

**功能**：搜索实验 Run

**调用者**：结果分析模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `experiment_ids` | array | 是 | 实验 ID 列表 |
| `filter_string` | string | 否 | 过滤条件 |
| `order_by` | array | 否 | 排序条件 |

---

### 4.2 结果收集

#### `experiment_collect_results`

**功能**：收集实验结果

**调用者**：结果分析模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `result_paths` | array | 是 | 结果文件路径列表 |
| `format` | string | 否 | 结果格式 |

**返回值**：

```json
{
  "results": {
    "metrics": {"accuracy": 0.95, "f1": 0.94},
    "logs": "...",
    "artifacts": ["model.pt", "config.json"]
  }
}
```

---

## 5. 文献检索工具

### 5.1 arXiv 集成

#### `arxiv_search`

**功能**：搜索 arXiv 论文

**调用者**：Idea 规范化模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `query` | string | 是 | 搜索查询 |
| `max_results` | number | 否 | 最大结果数 |
| `sort_by` | string | 否 | 排序方式 |
| `sort_order` | string | 否 | 排序顺序 |

**返回值**：

```json
{
  "papers": [
    {
      "id": "2401.12345",
      "title": "...",
      "authors": [...],
      "summary": "...",
      "pdf_url": "...",
      "published": "2024-01-15"
    }
  ]
}
```

---

#### `arxiv_download`

**功能**：下载 arXiv 论文

**调用者**：Idea 规范化模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `paper_id` | string | 是 | 论文 ID |
| `download_path` | string | 否 | 下载路径 |

---

### 5.2 论文解析

#### `paper_extract_text`

**功能**：提取论文文本

**调用者**：Idea 规范化模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pdf_path` | string | 是 | PDF 路径 |
| `pages` | string | 否 | 指定页数 |

---

#### `paper_extract_tables`

**功能**：提取论文表格

**调用者**：Idea 规范化模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pdf_path` | string | 是 | PDF 路径 |

---

## 6. 数据处理工具

### 6.1 数据集管理

#### `dataset_download`

**功能**：下载数据集

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `dataset_name` | string | 是 | 数据集名称 |
| `source` | string | 是 | 数据来源 |
| `version` | string | 否 | 版本 |
| `target_path` | string | 否 | 目标路径 |

---

#### `dataset_preprocess`

**功能**：预处理数据集

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `input_path` | string | 是 | 输入路径 |
| `output_path` | string | 是 | 输出路径 |
| `preprocessing_steps` | array | 是 | 预处理步骤 |

---

## 7. 评估计算工具

### 7.1 指标计算

#### `compute_metrics`

**功能**：计算评估指标

**调用者**：结果分析模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `predictions` | array | 是 | 预测结果 |
| `references` | array | 是 | 真实标签 |
| `metrics` | array | 是 | 要计算的指标 |

**返回值**：

```json
{
  "accuracy": 0.95,
  "precision": 0.94,
  "recall": 0.96,
  "f1": 0.95
}
```

---

#### `compare_results`

**功能**：对比实验结果

**调用者**：结果分析模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `baseline_result` | object | 是 | 基线结果 |
| `experiment_result` | object | 是 | 实验结果 |
| `metrics` | array | 是 | 对比指标 |

**返回值**：

```json
{
  "comparisons": [
    {
      "metric": "accuracy",
      "baseline": 0.90,
      "experiment": 0.95,
      "improvement": 0.05,
      "improvement_percent": 5.56,
      "is_significant": true
    }
  ],
  "overall_assessment": "significant_improvement"
}
```

---

### 7.2 统计分析

#### `statistical_test`

**功能**：执行统计显著性检验

**调用者**：结果分析模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `samples_a` | array | 是 | 样本 A |
| `samples_b` | array | 是 | 样本 B |
| `test_type` | string | 是 | 检验类型 |

---

## 8. 外部服务工具

### 8.1 GitHub 集成

#### `github_clone`

**功能**：克隆 GitHub 仓库

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `repo_url` | string | 是 | 仓库 URL |
| `branch` | string | 否 | 分支 |
| `target_path` | string | 否 | 目标路径 |

---

#### `github_get_file`

**功能**：获取 GitHub 文件

**调用者**：Coding Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `repo_url` | string | 是 | 仓库 URL |
| `file_path` | string | 是 | 文件路径 |
| `ref` | string | 否 | 分支或 commit |

---

## 9. 监控和日志工具

### 9.1 日志记录

#### `log_event`

**功能**：记录系统事件

**调用者**：各模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `event_type` | string | 是 | 事件类型 |
| `message` | string | 是 | 事件消息 |
| `metadata` | object | 否 | 元数据 |

---

#### `log_metric`

**功能**：记录系统指标

**调用者**：各模块

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `metric_name` | string | 是 | 指标名称 |
| `value` | number | 是 | 指标值 |
| `tags` | object | 否 | 标签 |

---

### 9.2 监控告警

#### `check_resource_usage`

**功能**：检查资源使用

**调用者**：规划层 Agent

**参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sandbox_id` | string | 是 | 沙盒 ID |
| `thresholds` | object | 是 | 阈值配置 |

**返回值**：

```json
{
  "alerts": [
    {
      "type": "memory_high",
      "current": 95,
      "threshold": 90,
      "severity": "warning"
    }
  ]
}
```

---

## 10. 工具调用示例

### 10.1 Baseline 复现工作流

```python
# 1. 创建沙盒
sb = sandbox_create(
    name="transformer_baseline",
    resources={"cpus": 8, "memory": "32g", "gpus": 1}
)

# 2. 克隆代码仓库
bash_execute(
    sandbox_id=sb.sandbox_id,
    command="git clone https://github.com/example/transformer.git /workspace/code"
)

# 3. 下载数据集
dataset_download(
    sandbox_id=sb.sandbox_id,
    dataset_name="wmt14",
    source="huggingface",
    target_path="/workspace/data"
)

# 4. 安装依赖
bash_execute(
    sandbox_id=sb.sandbox_id,
    command="pip install -r /workspace/code/requirements.txt"
)

# 5. 修改配置
file_edit(
    sandbox_id=sb.sandbox_id,
    path="/workspace/code/config.yaml",
    old_string="epochs: 100",
    new_string="epochs: 10"
)

# 6. 运行训练
result = bash_execute(
    sandbox_id=sb.sandbox_id,
    command="cd /workspace/code && python train.py",
    timeout=7200
)

# 7. 检查是否达到文献性能
results = experiment_collect_results(
    sandbox_id=sb.sandbox_id,
    result_paths=["/workspace/code/output/results.json"]
)

# 8. 保存镜像
if results.results.metrics.bleu >= 27.0:  # 文献报告的性能
    sandbox_save_as_image(
        sandbox_id=sb.sandbox_id,
        image_name="baseline_transformer_v1"
    )
```

### 10.2 Idea 实现工作流

```python
# 1. 从 baseline 镜像加载
sb = sandbox_load_from_image(
    image_name="baseline_transformer_v1",
    new_name="transformer_idea_v1"
)

# 2. 修改代码实现 Idea
file_edit(
    sandbox_id=sb.sandbox_id,
    path="/workspace/code/model.py",
    old_string="# Standard attention",
    new_string="# Dynamic sparse attention\n..."
)

# 3. 运行实验
bash_execute(
    sandbox_id=sb.sandbox_id,
    command="python train.py --experiment idea_v1"
)

# 4. 收集结果
results = experiment_collect_results(
    sandbox_id=sb.sandbox_id,
    result_paths=["/workspace/code/output/results.json"]
)
```

---

## 11. 工具权限矩阵

| 工具 | 规划层 | Coding Agent | Idea 模块 | 实验计划 | 分析模块 |
|------|--------|--------------|-----------|----------|----------|
| sandbox_create | ✅ | ❌ | ❌ | ✅ | ❌ |
| sandbox_execute | ✅ | ✅ | ❌ | ❌ | ❌ |
| file_read | ✅ | ✅ | ❌ | ❌ | ❌ |
| file_write | ❌ | ✅ | ❌ | ❌ | ❌ |
| mlflow_log | ✅ | ✅ | ❌ | ✅ | ✅ |
| arxiv_search | ❌ | ❌ | ✅ | ✅ | ❌ |
| compute_metrics | ❌ | ❌ | ❌ | ❌ | ✅ |
| github_clone | ✅ | ✅ | ❌ | ❌ | ❌ |

---

## 12. 附录

### 12.1 工具实现规范

所有工具应遵循以下规范：

1. **接口一致性**：统一使用 JSON 格式的输入输出
2. **错误处理**：返回结构化的错误信息
3. **超时控制**：支持超时参数，默认 300 秒
4. **日志记录**：自动记录工具调用日志
5. **幂等性**：尽可能实现幂等操作

### 12.2 新增工具流程

1. 在本文档中添加工具定义
2. 实现工具函数
3. 更新权限矩阵
4. 添加调用示例
5. 更新相关模块文档
