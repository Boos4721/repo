# ANT BMS · Rust + Flutter · v0.4.1

第三方蚂蚁保护板手机客户端，面向 Android / iOS。UI 延续已确认的四页设计。
这是第四轮开发源码包，**不是可直接安装的 APK / IPA**。

## v0.4.1 蓝牙连接修复

- Bluetooth 短/长 UUID 统一匹配，修正 iOS 短 UUID 被判定为缺少 FFE0 的路径。
- 显式发现服务后获取服务对象，短暂空结果最多重试三次；每次记录实际服务和特征属性。
- 直接使用已发现的特征对象收发，保留真实实例信息，不用构造 UUID 重新解析特征。
- FFE0 优先；仅允许已知 ANT 特征对在实际服务中匹配，不选择任意可写特征，不自动切换备用接口。
- 发送请求增加超时，首次通知长度进入诊断日志，未收到合法协议帧仍不显示已连接。
- 新增 14 项 UUID/通道匹配回归。截图只能确认服务匹配失败；此修复仍需用户设备验证。

## v0.4 新增

- 记录恢复校验格式与时间字段，损坏文件保留为 `.corrupt.<时间>`；无效记录跳过，保存队列在 I/O 失败后可继续工作。
- 会话筛选与 CSV 导出一致，时间轴随筛选更新；会话使用可读日期与来源标签。
- 趋势曲线使用真实采样时间，同一图内不同会话之间断开，避免跨骑行连接；固定数值曲线居中显示。
- Android 12+ 只请求附近设备权限，Android 11及以下请求扫描所需定位权限，不再强求两组互斥权限同时获批。
- 移除关于页的技术栈说明，使用产品文案；源码许可声明仍保留。
- CI 固定 Flutter 3.47.7，新增 9 项本地记录/导出回归。

## v0.3 新增

- 移除应用“关于”页的协议参考展示；源码 NOTICE 与 MIT 许可证保留。
- 记录使用应用私有目录 JSON 原子替换保存；启动自动恢复最近 7200 点，停止记录、断开和进入后台触发保存，采集中约每 3 秒保存一次。
- 新增会话编号、会话筛选，电流 / 电压 / 功率 / 电量趋势选择，CSV 包含时间、会话、电量、压差与来源，使用 UTF-8 BOM 与字段转义。
- 记录清空前确认；设备页显示最后更新、数据状态、立即刷新和最多 200 条会话诊断日志，支持系统分享。
- 每秒刷新过期状态；回到前台时允许失联设备重新连接；权限不足显示错误。
- 数据仍有 7200 点上限；突然结束进程可能丢失最后约 3 秒。历史记录跨设备保留，CSV 来源和会话字段区分采样。

v0.3 当时验证：Dart 格式/语法检查通过，Rust 协议回归 15 项通过。
v0.3 当时未完成 Flutter analyze、手机端编译与持久保存实测；v0.4 将通过 macOS CI 检查新增依赖。

## v0.2 新增

- 首个适配目标：ANT@BLE24CBUB-5P4P；截图参考版本 24ZHE6TB420A / 24CBUB00-241008A。
- 档案来源明确标记为截图，名称匹配不冒充固件验证；串数/容量不符时显示差异，实时值始终来自设备。
- 温度分别显示均衡、MOS、T1–T4；-40℃ 标记为疑似未接并保留读数。
- BMS 剩余时间区分字段缺失、零估算和有效分钟数；1561 分钟展示为 1天 2小时 1分钟。
- Rust 扩展段新增可选高速电流、充电器数据，逐字段检查长度，不用零代替未返回值。
- 修复数据过期后无法点击停止记录的问题。

## 已有能力

- Rust：CRC16-Modbus、短帧/长帧组帧、跨通知分包重组、组合帧、噪声与 CRC 错误恢复、会话重置。
- 实时解码：动态串数与温度数、单体电压高位标志、有符号电流/温度、u32 容量、SOC/SOH、MOS 状态、保护/告警原始位域、运行秒数与可选扩展字段。
- 原生桥接：Rust C ABI + Dart FFI，明确释放引擎与返回字符串。暂未使用 flutter_rust_bridge 代码生成；保持桥接小且可独立验证，后续可替换而不改变协议模块。
- Flutter：总览、单体、记录、设备四页；跟随系统深浅色；无数据显示 `--`；断线显示过期数据；切换设备清除旧快照。
- BLE 源码：ANT 设备扫描、FFE0 服务发现、默认/备用通道手动选择、有效实时帧后才显示已连接、500ms 前台轮询、5s 无应答检测、最多三次退避重连。
- 演示模式：根据截图构造的 21S / 170Ah、78.22V、56% 的模拟报文通过同一套 Rust 解析器和 FFI，不是界面写死数据。
- 记录：本地持久采样、多指标曲线、系统分享 CSV（包含 demo 或设备标识）。最多 7200 点；采用 JSON 原子文件保存，尚未接入 SQLite。

## 已验证与未验证

已执行：15 项 Rust 协议回归 + 16 项纯 Dart 展示逻辑验证、Rust clippy、Dart ↔ Rust FFI 调用与内存释放流程冒烟、Dart 语法格式检查。
真实报文测试使用上游抓包，**不等于已在用户保护板上实测**。

本机执行器是 Linux，不能直接编译 iOS；GitHub macOS CI 已在 v0.2 成功生成未签名 IPA。
v0.4 本地已通过 15 项 Rust 回归、16 项展示逻辑和 9 项文件/CSV 检查；完整 Flutter 检查与 IPA 以本次 CI 结果为准。
未执行手机启动、真实保护板联调和实机文件保存验证。

当前只发送实时读取请求；**没有参数写入、控制 MOS、密码验证、OTA、自动升权或后台持续采集**。
备用 A/B 分别共享蓝牙屏/充电器接口，选用时界面提示确认。当前不做自动通道切换。
ANT 地址暂定 A1；其他地址、老 ANT 协议、电量计中继器暂未支持。

## 目录

- `rust/`：独立协议核心、C ABI、真实报文回归。
- `app/lib/`：Flutter 界面、BLE 控制器、Dart FFI。
- `scripts/`：本机生成平台壳、配置权限、编译手机 Rust 库。
- `tools/`：不依赖 Flutter 的 Dart FFI 冒烟程序。
- `preview/ui.html`：已确认的交互 UI 参考（聊天内片段，非独立网页）。
- `docs/`：设备验证步骤、来源与许可证。

## 本机开发准备

安装 Flutter 稳定版、Rust、Python 3；Android 另需 SDK/NDK/JDK，iOS 必须 macOS + Xcode。
在自己的开发机运行以下命令，不要在受上述审批限制的环境重试 Flutter 初始化。

```bash
bash scripts/bootstrap.sh
```

生成平台外壳、写入蓝牙权限、Android minSdk 26、iOS 蓝牙用途说明并拉取依赖。
脚本更改应在首次编译前检查；源包不包含用户凭证和签名文件。

### Android

```bash
cargo install cargo-ndk --locked
export ANDROID_NDK_HOME=/your/android/sdk/ndk/version
bash scripts/build_android_rust.sh
cd app
flutter analyze
flutter run
# 实机读取稳定后再打包
flutter build apk --release
```

最终版本须单独设置 applicationId、图标、生产签名和安装渠道。本包不包含发布签名。

### iOS

```bash
bash scripts/build_ios_rust.sh
cd app
flutter analyze
flutter run
```

脚本编译 arm64 真机与 arm64/x86_64 模拟器静态库，通过 xcconfig force_load 和符号导出供 Dart FFI 访问。
在 Xcode 选择自己的开发团队；安装与发行的签名需要在本机完成。

### 协议与 FFI 自检

```bash
cargo test --manifest-path rust/Cargo.toml --locked
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo build --manifest-path rust/Cargo.toml --locked
cd tools
dart pub get
dart run profile_smoke.dart
# Linux 示例；macOS 改成 .dylib，Windows 改成 .dll
ANT_CORE_LIBRARY="$PWD/../rust/target/debug/libant_core.so" dart run ffi_smoke.dart
```

## 下一轮顺序

1. 在 macOS CI 完成当前版本的 Flutter 检查与 iOS 编译。
2. 用实际保护板核对蓝牙名称、固件、服务/特征、电压与电流方向；验证断线、重连、切换设备和系统权限。
3. SQLite 持久记录、会话区分、参数只读页、设备身份读取、应用内分级日志。
4. 独立开发权限与写入事务：响应匹配、迟到应答处理、u32 拆写、结果段确认、回读对比和保存。
5. 再评估控制指令、后台能力和分发。

协议与真实向量参考 MIT 项目 maibms；完整来源见 NOTICE.md。
