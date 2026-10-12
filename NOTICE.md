# 第三方来源

协议参考项目：https://github.com/lswlc33/maibms
参考提交：adfce30d5bee53827058041558a76622c7513c0b（2026-10-12 读取）。
许可：MIT，原版权声明完整保留于 docs/maibms-MIT-LICENSE。

本项目的 Rust 实现根据上游 Frame.kt、RealtimeDecoder.kt 与 docs/03、docs/05 的协议说明重写；
真实回归向量 rust/tests/real-frame.hex 来自上游 RealFrameTest.kt。
不包含官方小程序解包包、图标、上游应用签名或用户密码。

本项目是独立第三方客户端，不代表 ANT 厂商或麻衣 BMS 作者。

v0.5 的蓝宝帧、CRC、表字段/换算、设备识别与均衡/重启命令参考同一提交的
LanBaoProtocol.kt、DeviceFamily.kt、BmsTransport.kt、Params.kt 与 docs/07、09、13。
蓝宝报文回归为合成向量，均衡/重启的上游文档也未声明在用户设备上实测。
