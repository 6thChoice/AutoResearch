---
title: 开发规范
level: global
enabled: true
updated_at: 2026-02-23T04:19:06Z
---

项目目标：复现论文工作 https://github.com/vivva/DLinear

执行计划：
  1. 研究论文和代码库: 仔细阅读DLinear论文（标题：'DLinear: Decomposition Linear Model for Long-term Time Series 
  2. 设置实验环境: 根据GitHub仓库中的requirements.txt或环境配置说明，创建并激活一个Python虚拟环境（推荐使用conda或venv）。安装所有依赖包，特别
  3. 准备数据集: 下载论文中使用的数据集（如ETT、Weather、Electricity等）。数据源通常在代码库的README或data目录下指定。将下载的数据集文件按照代码要
  4. 运行训练脚本: 根据代码库提供的训练脚本（如train.py）和论文中的实验设置，配置训练参数（如学习率、批量大小、epoch数、序列长度等）。如果代码库提供配置文件，则修改配
  5. 模型评估: 使用训练好的模型权重，在测试集上进行评估。运行评估脚本（如test.py）或使用训练脚本中的评估模式。计算测试集上的预测指标，如MSE、MAE等，并保存预测结果
  6. 结果对比与分析: 将测试集上得到的性能指标与论文中报告的结果进行对比，特别是论文表格中的数值。如果存在差异，分析可能的原因，如随机种子、数据预处理细节、超参数设置、模型初始化等。
当前日期：<method 'date' of 'datetime.datetime' objects>
当前时间：<attribute 'hour' of 'datetime.datetime' objects>
