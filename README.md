# 玩转三段式 · oneplus_tri_key_remapper

> 一个面向欧加系（一加 / OPPO）带三段式物理按键机型的 Magisk 模块：把吃灰的「静音 / 振动 / 响铃」三段式开关，重映射成你真正会用的快捷功能。

![最新版本](https://img.shields.io/github/v/release/pumu21600-boop/three-act-structure?label=最新版本&style=flat-square)
![license](https://img.shields.io/github/license/pumu21600-boop/three-act-structure?style=flat-square)

## 这是什么

一加手机的三段式按键平时只能切换静音 / 振动 / 响铃。如果你根本用不到这个系统切换，这个模块可以**接管三段式按键**，让上拨、中拨、下拨各自触发一个自定义动作（微信扫码、支付宝付款、手电筒、AI 实景对话……），并通过 **WebUI 可视化配置**，随时改随时生效。

## 功能特性

- **三档独立映射**：上拨 / 中拨 / 下拨各绑定一个动作，互不影响
- **15+ 快捷动作**：
  - 后台录音、录屏、截屏
  - AI 实景对话（小布）、音乐识别、小布识屏、小布闪记、AI 语音摘记
  - 手电筒、打开相机、计算器
  - 微信扫一扫、微信付款码、支付宝扫一扫、支付宝付款码
  - 关闭 / 清理当前动作
- **干掉原三段式**：一键屏蔽系统静音 / 振动 / 响铃切换（可选，开关随时可逆）
- **WebUI 可视化配置**：Magisk / KernelSU 模块页直接打开，深色 / 浅色主题，可调节界面模糊与透明度
- **运行日志窗口**：保存配置、每次按键动作都有记录，可在 WebUI 内实时查看
- **稳如老狗**：独立看门狗进程 + OOM 保护 + cgroup 逃逸 + 服务区启动机制，尽量保证脚本不被系统杀死
- **干净卸载**：自带清理脚本，卸载后完整恢复三段式原功能

## 版本更迭

| 版本 | Tag | 说明 |
| --- | --- | --- |
| v4.2 | [`v4.2`](https://github.com/pumu21600-boop/three-act-structure/tree/v4.2) | 初版发布：三段式按键重映射，适用于欧加有三段式按键的机型 |
| v7.3.0 | [`v7.3.0`](https://github.com/pumu21600-boop/three-act-structure/tree/v7.3.0) | 1. 新增界面样式调节功能<br>2. 新增模块运行日志窗口<br>3. 修复部分功能容易挂的 bug<br>4. 新增模块服务区机制，确保脚本运行 |

> 仓库 tag 与 Releases 一一对应：`v4.2`、`v7.3.0` 两个 tag 分别指向该版本的完整源码，想看某个版本的代码直接切 tag 即可。

## 兼容性

- **机型**：欧加系（一加 / OPPO 等）带三段式物理按键、内核提供 `/proc/tristatekey/tri_state` 节点的机型
- **系统**：ColorOS / OxygenOS（快捷动作依赖 `com.coloros.*`、`com.oplus.*`、`com.heytap.*` 等系统组件）
- **Root**：Magisk / KernelSU（支持 WebUI 的版本）均可

> 如何确认适配：在 root 下执行 `cat /proc/tristatekey/tri_state`，能读到 1 / 2 / 3 即代表节点存在。

## 安装与使用

1. 到 [Releases](https://github.com/pumu21600-boop/three-act-structure/releases) 下载最新 zip（如 `V7.3.0.zip`）
2. 在 Magisk / KernelSU 中刷入模块，**重启手机**
3. 打开 Magisk / KernelSU 的模块页面，点击本模块的 **WebUI** 进入配置界面
4. 分别为上拨 / 中拨 / 下拨选择动作 → **保存配置**，等几秒即生效

### 常用设置

- 勾选「**干掉原三段式**」可屏蔽系统静音 / 振动 / 响铃切换；取消勾选即恢复
- 菜单（左上角）可切换主题、调节界面样式、查看运行日志
- 配置保存在 `/data/local/tmp/tri_key/tri_key_config.sh`，日志在 `/data/local/tmp/tri_key/tri_key.log`

## 故障排查

| 现象 | 处理 |
| --- | --- |
| WebUI 显示「模块未激活」 | 模块未启用或未重启，先重启手机 |
| WebUI 显示「监控未运行」 | 查看日志：`cat /data/local/tmp/tri_key/tri_key.log` |
| 按键动作无反应 | 确认机型存在 `/proc/tristatekey/tri_state` 节点；不同机型的手电筒 LED 节点可能不同 |
| 想恢复原三段式 | WebUI 里关闭「干掉原三段式」，或直接卸载模块 |

手动清理残留（可选）：`su -c sh /data/adb/modules/oneplus_tri_key_remapper/cleanup.sh`

## 项目结构

```
.
├── module.prop          # 模块元信息（id: oneplus_tri_key_remapper）
├── service.sh           # 开机自启，拉起监控脚本
├── tri_key_monitor.sh   # 核心：轮询三段式状态 + 动作执行
├── tri_watchdog.sh      # 看门狗：主进程挂了自动拉起
├── save_config.sh       # WebUI 保存配置的辅助脚本
├── cleanup.sh           # 手动清理残留
├── uninstall.sh         # 卸载时彻底清理
└── webroot/             # WebUI 配置页面（index.html）
```

## 许可证

[MIT](LICENSE) © 2026 袅
