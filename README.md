# 旋转设备多维状态感知与故障识别

基于 EGO1 / Artix-7 FPGA 的旋转设备监测演示工程，结合三轴振动采集、编码器转速测量、FPGA 信号处理和 Python 可视化，实现状态监测与疑似故障提示。

## 项目概览

- **硬件**：EGO1（工程器件配置为 `xa7a35tcsg324-1I`）、ADXL345 三轴加速度传感器、MS42CG 编码器、D36A 电机驱动器。
- **FPGA**：传感器采集、数字滤波、256 点定点 FFT、振动特征、编码器计数、规则健康评分、电机控制及 UART 通信。
- **上位机**：Python 界面展示波形、频谱、转速和特征，支持记录、回放、模拟演示和控制命令。
- **识别输出**：基于同工况基线的规则评分和不平衡、松动等**疑似**标签，不能作为故障根因的确定结论。

## 系统流程

```text
ADXL345 / 编码器 → FPGA 采集、滤波、FFT、特征与基线
                         ↓ UART（230400，8N1）
                 Python 显示、记录与规则分析
                         ↓ 控制命令
                   FPGA → D36A 电机驱动
```

ADXL345 标称采样率为 200 Hz；FFT 为 256 点、频率间隔 0.78125 Hz。1×/2× 阶次分析使用编码器相位。电机转速命令为开环控制，编码器用于实测反馈，**未实现 PID 闭环调速**。

## 仓库内容

| 路径 | 内容 |
| --- | --- |
| [rotating_health/rtl](rotating_health/rtl/) | Verilog 采集、处理、控制与顶层模块 |
| [rotating_health/constraints](rotating_health/constraints/) | EGO1 引脚约束 |
| [rotating_health/host](rotating_health/host/) | 上位机、协议和分析程序 |
| [rotating_health/sim](rotating_health/sim/) | 仿真测试与部分结果 |
| [rotating_health/scripts](rotating_health/scripts/) | 构建、仿真及数值检查脚本 |
| [docs](docs/) | 技术文档 PDF |
| [archive](archive/) | 原始完整 ZIP，包括位流、Vivado 工程、构建报告、依赖和全部原始文件 |

仓库中展开的 `rotating_health/` 便于浏览，**不是完整可运行发行包**；使用和重建时请先下载并解压 `archive/` 中的原始 ZIP。详细接线、操作、限制和排查见包内 [项目说明](rotating_health/README.md) 与 [验证记录](rotating_health/VALIDATION.md)。

## 快速体验

无需连接开发板：解压完整 ZIP 后运行 `start_demo.bat`，在界面中先选择正常基线，再体验模拟状态。演示使用合成数据，不能代表实际故障识别效果。

上位机依赖 Python、NumPy、Matplotlib、Tk 和 pyserial。项目原环境记录为 Python 3.11.9；其他电脑可根据 `requirements.txt` 安装依赖，并检查启动脚本中的 Python 路径。

## 构建与验证

项目记录使用 Vivado 2025.2 完成综合、布局布线和比特流生成。构建与仿真入口分别为 `scripts/build.bat`、`scripts/simulate.ps1`；脚本中的工具安装路径需根据本机环境调整。记录显示 50 MHz 内部时钟的 WNS 为 +1.828 ns、WHS 为 +0.035 ns，且默认 DRC 无 Error；详细报告和警告请以原始压缩包内文件为准。

记录中的仿真覆盖 FFT、I²C、编码器、UART、电机控制及数值检查。新增控制版本**尚未在实物板卡、电机和真实故障样本上验证**；不能据此推断现场识别准确率。编码器一圈计数需实测确认，传感器量程、接线及驱动设置需按完整说明核对。

## 安全与使用边界

连接和下载前请断开电机驱动动力电源，并核对接线、供电及机械固定。上位机控制和 FPGA 逻辑不是经过安全认证的机械保护系统。实际运行前请阅读完整项目说明，并按现场条件验证停止方式和外部接口。

## 参考资料

- [ADXL345 数据手册](https://www.analog.com/media/en/technical-documentation/data-sheets/ADXL345.pdf)
- [EGO1 用户手册](https://e-elements.readthedocs.io/zh/ego1_v2.2/EGo1.html)
