# 玩转三段式 · oneplus_tri_key_remapper

> 面向欧加系（一加 / OPPO）三段式物理按键机型的模块：把吃灰的「静音 / 振动 / 响铃」开关，重映射成你真正会用的快捷动作。

![最新版本](https://img.shields.io/github/v/release/pumu21600-boop/three-act-structure?label=最新版本&style=flat-square)
![license](https://img.shields.io/github/license/pumu21600-boop/three-act-structure?style=flat-square)

## 这是什么

一加 / OPPO 的三段式按键平时只能切换静音 / 振动 / 响铃。如果你根本用不到这个切换，本模块可以**接管三段式按键**，让上拨、中拨、下拨各触发一个自定义动作（微信扫码、支付宝付款、手电筒、AI 对话……），并通过 **WebUI 可视化配置**实时生效。

## 功能特性

- **三档独立映射**：上拨 / 中拨 / 下拨各绑一个动作，互不影响
- **13 种快捷动作**：后台录音、录屏、截屏、AI 实景对话、音乐识别、小布识屏、小布闪记、AI 语音摘记、手电筒、相机、计算器、微信扫一扫/付款码、支付宝扫一扫/付款码、自定义 Shell 命令
- **下拨自动关闭**：上拨触发的动作，下拨时自动关掉（含 App 强停与手电筒关闭）
- **干掉原三段式**：彻底屏蔽系统静音/振动/响铃切换，随时可逆
- **WebUI 可视化配置**：模块页直接打开，深浅主题、界面模糊与透明度可调
- **运行日志窗口**：保存配置、按键动作全记录，WebUI 内实时查看
- **多重保活**：独立看门狗 + OOM 保护 + cgroup 逃逸 + 进程自重启
- **干净卸载**：卸载脚本完整恢复原功能，不留进程与文件

## 「干掉原三段式」原理

原生功能通过 `/dev/input/event5`（`oplus,hall_tri_state_key`）上报 `KEY_F3` 给 `system_server`。模块内置 `tri_grab` 对该设备做 `EVIOCGRAB` 独占，系统收不到事件，静音/振动/响铃切换即失效。模块自身仍从 `/proc/tristatekey/tri_state` 读状态，功能不受影响。

主脚本会周期检查 `tri_grab` 存活，挂掉立即重启；关掉开关则释放独占，原生功能恢复。

## 兼容性

- **机型**：欧加系（一加 / OPPO / realme）带三段式物理按键、内核提供 `/proc/tristatekey/tri_state` 节点的机型
- **系统**：ColorOS / OxygenOS（部分动作依赖 `com.coloros.*`、`com.oplus.*`、`com.heytap.*` 系统组件）
- **Root**：Magisk / KernelSU / SukiSU（支持 WebUI 的版本）
- **架构**：arm64-v8a（`tri_grab` 为静态编译的 ARM64 二进制）

适配自检：root 下执行 `cat /proc/tristatekey/tri_state` 能读到 1/2/3，且 `getevent -pl` 能看到设备 `oplus,hall_tri_state_key`。

## 安装与使用

1. 到 [Releases](https://github.com/pumu21600-boop/three-act-structure/releases) 下载最新 zip
2. 在 Magisk / KernelSU 中刷入，**重启手机**
3. 打开模块页的 **WebUI** 进入配置
4. 分别为上拨 / 中拨 / 下拨选择动作 → **保存配置**，热重载即时生效（无需重启）

### 常用位置

| 用途 | 路径 |
|------|------|
| 配置文件 | `/data/local/tmp/tri_key/tri_key_config.sh` |
| 运行日志 | `/data/local/tmp/tri_key/tri_key.log` |
| 独占进程日志 | `/data/local/tmp/tri_key/grab.log` |

## 故障排查

| 现象 | 处理 |
|------|------|
| WebUI 显示「模块未激活」 | 模块未启用或未重启 |
| WebUI 显示「监控未运行」 | `cat /data/local/tmp/tri_key/tri_key.log` 看日志 |
| 开关原三段式无效 | `cat /data/local/tmp/tri_key/grab.log`，应看到 `OK grabbed` |
| 按键动作无反应 | 确认节点存在；手电筒 LED 路径因机型而异 |
| 想恢复原三段式 | WebUI 关闭「干掉原三段式」，或卸载模块 |

手动清理：`su -c sh /data/adb/modules/oneplus_tri_key_remapper/cleanup.sh`

## 项目结构

```
.
├── module.prop            # 模块元信息
├── service.sh             # 开机自启
├── tri_key_monitor.sh     # 核心：状态轮询 + 动作执行 + 屏蔽控制
├── tri_watchdog.sh        # 看门狗：主进程挂了自动拉起
├── tri_grab.c             # 源码：EVIOCGRAB 独占 event5
├── tri_grab               # 编译产物：ARM64 静态二进制
├── save_config.sh         # WebUI 保存配置（触发热重载）
├── cleanup.sh             # 手动清理残留
├── uninstall.sh           # 卸载时彻底清理
├── tri_key_config.sh      # 默认配置
└── webroot/               # WebUI 页面
```

### 重新编译 tri_grab

```bash
# 在 arm64 Linux 上（或安装 gcc-aarch64-linux-gnu 交叉工具链）
gcc -O2 -static -o tri_grab tri_grab.c
```

## 版本

当前 **v7.4.0**。历史 tag 可在 [Releases](https://github.com/pumu21600-boop/three-act-structure/releases) 查看。

## 许可证

[MIT](LICENSE) © 2026 袅
