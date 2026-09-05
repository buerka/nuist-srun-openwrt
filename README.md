# 南京信息工程大学校园网自动登录 · OpenWrt / SRun

`nuist-srun-openwrt` 是面向**南京信息工程大学（南信大 / NUIST）校园网**的 OpenWrt 路由器自动登录工具，支持深澜 SRun 认证、开机自启和断线重连（掉线自动重登）。使用 Lua 和 curl，正常在线时每分钟查询一次状态，离线后自动获取新的 challenge 并登录。

Lightweight OpenWrt campus network auto-login client for Nanjing University of Information Science and Technology (NUIST), using SRun authentication with automatic reconnection.

源自南京信息工程大学校园网的实际使用需求，非学校或深澜官方项目。仓库不包含任何真实账号、密码、认证记录或部署配置。

## 特点

- **轻量**：程序约 15 KB。检查完成后 Lua 进程退出，空闲时仅保留 shell 和 sleep。
- **按需登录**：只有服务端明确返回 `not_online_error` 才认证；在线时不重复登录，其他账号在线时不强制注销。
- **动态地址**：使用认证服务器返回的当前 IPv4 地址，适应 DHCP 地址变化。
- **失败退避**：默认 60 秒检查一次；失败后按 120、240、480 秒等间隔重试，最长 30 分钟。
- **系统集成**：procd 管理进程，支持开机自启和指定网络接口事件触发检查。
- **减少信息暴露**：密码配置权限为 `600`；认证 URL 不出现在 curl 命令行中；临时文件位于 RAM，日志不输出账号、密码、challenge 或密文。

## 适用范围

支持采用 `get_challenge`、`srun_portal` 和 `{SRBX1}` 信息编码的 **SRun IPv4 账号密码认证**。不同学校可能使用不同后缀、接入点编号和接口，不能保证所有深澜部署都适用。不支持验证码、短信、单点登录、IPv6 双栈或强制客户端认证。

Lua 认证核心曾在 Xiaomi AX3000T / Kwrt 24.10 环境验证登录和自动恢复。本公开版本增加了可配置认证地址、安装工具和离线测试；其他固件需要自行验证。

已有运行环境：

- `lua`（5.1 兼容语法）
- `nixio`、`luci.jsonc` Lua 模块
- `curl`、`logger` 和 procd

某些固件没有上述组件。安装器会先检查，不会替你安装依赖或修改软件源。支持 HTTPS 认证地址时，需要固件有可用的 CA 证书。

## 安装

从 GitHub 下载源码 ZIP，解压后通过 LuCI 文件管理器或 SCP 上传到路由器的 `/tmp/`。在**路由器终端**进入解压目录运行：

```sh
sh install.sh
```

初次安装只放置程序与空配置，不会启动服务。已有配置会保留；如果是升级且服务原先正在运行，安装完成后会恢复运行。

编辑路由器上的 `/etc/nuist-srun.json`：

```json
{
  "portal": "http://192.0.2.1",
  "ac_id": "1",
  "username": "",
  "password": "",
  "interface": "wan",
  "interval": 60
}
```

`192.0.2.1` 是文档示例地址，不能用于真实认证。请按自己的认证页面填写：

| 配置 | 如何确定 |
| --- | --- |
| `portal` | 认证页地址栏的协议、主机和可选端口；不带页面路径、参数、账号或密码。 |
| `ac_id` | 认证页 URL 或登录请求中的接入点编号。 |
| `username` | 实际登录请求的完整账号，包含需要的 `@campus` 等后缀。 |
| `password` | 你自己的校园网密码，直接在路由器配置文件里填写。 |
| `interface` | OpenWrt 的逻辑网络接口名，通常为 `wan`；不是物理网卡名。 |
| `interval` | 正常检查间隔（秒），范围 30–1800，默认 60。 |

JSON 字符串内的双引号和反斜杠需要转义。配置完成后：

```sh
chmod 600 /etc/nuist-srun.json
lua /usr/lib/nuist-srun/srun.lua check
lua /usr/lib/nuist-srun/srun.lua once

/etc/init.d/nuist-srun enable
/etc/init.d/nuist-srun start
```

`check` 仅验证本地配置；`once` 先查在线状态，只有离线才登录。看到 `online` 或 `login_verified` 表示检查成功。不要在仓库工作目录里填写真实密码。

## 管理与排查

```sh
# 当前认证状态、服务状态、脱敏日志
lua /usr/lib/nuist-srun/srun.lua status
/etc/init.d/nuist-srun status
logread -e nuist-srun

# 修改配置后重启
/etc/init.d/nuist-srun restart

# 停止，并取消开机启动
/etc/init.d/nuist-srun stop
/etc/init.d/nuist-srun disable
```

如果想注销后保持离线，先停止服务。程序以认证服务器的在线状态为准，不把任意公网网站访问失败直接当作需要重新登录。

| 日志 | 处理方式 |
| --- | --- |
| `credentials_missing` | 填写账号和密码，确认账号后缀。 |
| `config_requires_mode_0600` | 检查配置路径与权限，执行 `chmod 600 /etc/nuist-srun.json`。 |
| `invalid_portal_origin` | 只填写 HTTP(S) 源地址，不附带页面路径或查询参数。 |
| `portal_unreachable` | 检查 WAN、校园网路由和服务器可达性。代理环境变量不会用于认证请求。 |
| `other_account; login_skipped` | 当前出口已被其他账号认证；程序不会把它踢下线。 |
| `login_rejected; code=…` | 检查账号、密码、接入点编号和学校限制。 |
| `another_check_running` | 有另一个检查正在执行，稍后重试。 |

卸载时在源码目录运行 `sh uninstall.sh`，默认保留私有配置。明确需要连配置一起删除时使用 `sh uninstall.sh --purge`。

## 认证原理

1. 请求 `/cgi-bin/rad_user_info` 判断在线状态。
2. 离线时请求 `/cgi-bin/get_challenge`，取得一次性 challenge 与当前 IP。
3. 用 challenge 计算 HMAC-MD5、SRun 信息密文以及 SHA-1 校验值。
4. 请求 `/cgi-bin/srun_portal?action=login`。
5. 再次查询在线状态，确认成功后记录 `login_verified`。

`srun_crypto.lua` 实现协议所需算法，并处理 Lua/nixio 与 JavaScript 的 32 位运算差异。它不是通用密码库，不应拿来保护其他应用的数据。

## 测试

开发机需要 Python 3 和 Lua（5.1 配合 LuaBitOp，或带原生位运算的 5.3+）：

```sh
python3 tests/run.py
```

测试仅使用合成账号与文档保留地址，不联网、不注销、不读取真实配置。包括算法已知向量、认证流程模拟、失败与敏感日志检查，以及安装升级时保留配置和卸载行为。GitHub Actions 会在推送和 PR 时运行相同检查。

## 隐私与安全

请勿将配置、HAR、PCAP、登录 URL、challenge、`info` 或访问令牌提交到 GitHub。**完整的 challenge 与 info 可能还原密码**，仅遮住名为 `password` 的字段并不足够。HTTP 认证也不具备 HTTPS 的传输保护。

本仓库的 `.gitignore` 和 CI 隐私检查用于减少误提交，不能替代人工检查。提交问题时只提供固件版本、已脱敏错误码和复现步骤。详见 [SECURITY.md](SECURITY.md)。

## 许可证

[MIT](LICENSE)。项目仅供本人获授权的网络账号使用；没有附带学校页面资源或第三方打包库。
