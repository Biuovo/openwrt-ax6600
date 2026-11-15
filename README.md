# 京东云太乙 ER1 OpenWrt 固件

适配京东云太乙 `RE-CS-07`（IPQ6018），纯有线设备：1 个 WAN、3 个 LAN，无 Wi-Fi。

## 固件内容

基于 `ones20250/immortalwrt_ipq` 的 `owrt` 分支，保留原仓库 PLUS 插件组合，集成：

- Qualcomm PPE 开源硬件加速
- Linux 原生 Flowtable 硬件卸载
- SONiC FullCone NAT
- Docker / Dockerman
- OpenClash、PassWall2、AdGuard Home 等原 PLUS 插件
- daeuniverse 官方 Honk、LuCI 和 Doona 面板

## 云编译

Actions → `QCA-ALL` → Run workflow。

当前只生成一个 ER1 固件，`PACKAGE` 留空，`TEST=false`。配置验证使用 `WRT-TEST`，选择 `IPQ60XX-ER1` 并保持 `TEST=true`。

## 重要说明

- 不包含 Wi-Fi 驱动、无线配置或雅典娜 LED 插件。
- 不使用雅典娜的 QCA8081 2.5G 端口补丁、U-Boot、分区表和刷机附件。
- 管理地址：`192.168.10.1`。
- ER1 的 PPE/Flowtable、Honk 和分区布局尚未完成实机验收。刷机前请备份原厂固件并确认 ER1 专用恢复方案。
- Honk 仍是试验阶段组件，首次启动需在 LuCI 中完成服务配置。
