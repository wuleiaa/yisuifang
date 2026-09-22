# HTTPS 配置与续期（yisuifang.work）

> 更新：2026-09-22
> 面向：在服务器上执行安装的人
> 目标：把 `http://43.129.75.228/` 变成 `https://yisuifang.work/`，并且自动续期

---

## 一、状态：2026-09-22 已上线 ✅

```
https://yisuifang.work/            医护端        200（证书链校验通过）
https://yisuifang.work/patient/    患者端        200
https://yisuifang.work/admin/      管理后台      200
https://yisuifang.work/health      接口健康检查  200
http://yisuifang.work/  →  301  https://yisuifang.work/
http://43.129.75.228/   →  301  https://yisuifang.work/
```

证书：Let's Encrypt 签发，`CN=yisuifang.work`，
SAN = `yisuifang.work` + `www.yisuifang.work`，有效期 **2026-09-22 → 2026-12-21**。
每周一 03:17 自动续期（`/etc/cron.d/followup-cert-renew`），
续期通道已用 `certbot renew --dry-run` 实测通过。

当时的原始状态（留作对照）：

| 检查项 | 结果 |
|---|---|
| 域名解析 | `yisuifang.work`、`www.yisuifang.work` 都已指向 `43.129.75.228` ✅ |
| 服务器 80 端口 | 通，`http://43.129.75.228/health` 返回 `{"status":"UP"}` ✅ |
| 服务器 443 端口 | **云防火墙已放行，但服务器上没人监听**（连接被"积极拒绝"，不是超时） |
| 证书 | 安装前没有 |
| fix3（改密入口） | 已经部署上线 ✅（线上资源指纹与 `dist-deploy/patch3` 一致） |

---

## 二、安装步骤（已于 2026-09-22 20:37 执行完成，留档备用）

### 1. 把安装包传上去

在自己电脑上（PowerShell）：

```powershell
scp "F:\医院回访小程序\dist-deploy\followup-https1.zip" ubuntu@43.129.75.228:/home/ubuntu/
```

> 平时用哪个账号登录服务器就写哪个（`ubuntu` 或 `root`）。

### 2. 解包、运行安装脚本

```bash
cd /opt/followup
unzip -o /home/ubuntu/followup-https1.zip
sudo bash https/install-https.sh      # 用 root 登录的话去掉 sudo
```

脚本是**幂等**的，可以反复跑；中途失败也不会把网站弄挂（见第四节）。
脚本必须以 root 身份运行（要写 `/etc/cron.d/`、要 `docker`），用 ubuntu 账号就先 `sudo -i`。

### 3. 看到这些就说明成功了

```
=== 4/6 request the certificate from Let's Encrypt
Successfully received certificate.
=== 5/6 switch nginx to https
  https /         -> 200
  https /patient/ -> 200
  https /admin/   -> 200
  https /health   -> 200
  http  /         -> 301   (expect 301)
=== 6/6 install the weekly renewal cron job
```

然后再在自己电脑的浏览器里打开 `https://yisuifang.work/`，地址栏应该有一把小锁。

---

## 三、这次动了哪些文件

**原则：原来的 `docker-compose.yml` 一个字都没改**，HTTPS 的部分全部放进
`docker-compose.override.yml`（docker compose 会自动把两个文件合并）。
好处是撤销 HTTPS 只要删掉这一个文件，而且以后改主 compose 也不会冲突。

```
/opt/followup/
├── docker-compose.yml              ← 原样不动
├── docker-compose.override.yml     ← 新增：给 nginx 加 443 端口 + 两个挂载
├── nginx/
│   ├── followup.conf               ← 当前生效的配置（脚本在引导版/正式版之间切换）
│   ├── followup-https.conf         ← 新增：HTTPS 正式版（脚本的"回装"来源）
│   ├── followup-http-only.conf     ← 新增：HTTP 引导版（只在第一次签证书时顶几分钟）
│   ├── letsencrypt/                ← 新增：certbot 写的证书（只读挂进 nginx）
│   └── www/                        ← 新增：ACME 校验文件目录
└── https/
    ├── install-https.sh            ← 安装脚本
    └── renew-cert.sh               ← 续期脚本（安装时自动加进 cron）
```

原来那份 `nginx/followup.conf` 的内容仍有备份（在 `backup/https-<时间戳>/` 里），
新的 `followup.conf` 内容 = `followup-https.conf`，两者保持一致。

改 nginx 配置时记住：**`followup.conf` 和 `followup-https.conf` 要同时改**
（`cp nginx/followup-https.conf nginx/followup.conf`），否则下次重装会把改动冲掉。

---

## 四、为什么脚本要"先用 HTTP 引导版顶一下"

nginx 有个硬规矩：**配置里写了 `ssl_certificate`，启动时那个文件必须存在**。
不存在的话不是"那个站点起不来"，而是**整个 nginx 起不来**（三端全挂）。

而第一次装的时候证书还没签出来，所以顺序必须是：

```
把 HTTP 引导版覆盖到 nginx/followup.conf
   ↓  启动 nginx（只有 80 端口，网站照常能用）
certbot 通过 80 端口校验、签发证书
   ↓  把 HTTPS 正式版覆盖回 nginx/followup.conf
nginx -t 检查 → reload 生效（80 跳转 + 443 业务）
```

**关键点**：中间任何一步失败（DNS 没生效、80 被挡、Let's Encrypt 限流……），
网站都会**保持原来的 HTTP 可用状态**，不会出现"配置改坏了整站打不开"。

> 细节：脚本用 `cp` 覆盖文件，而不是 `mv`。因为 compose 是"单文件挂载"，
> 挂载跟的是文件 inode，用 `mv` 换掉文件后容器里读到的还是旧内容。

---

## 五、证书续期

Let's Encrypt 证书**有效期 90 天**，安装脚本加了每周一 03:17 的定时任务：

```bash
# /etc/cron.d/followup-cert-renew
17 3 * * 1 root /opt/followup/https/renew-cert.sh >> /var/log/followup-cert-renew.log 2>&1
```

`renew-cert.sh` 做的事：`certbot renew`（离到期还有 30 天以上会自动跳过，不浪费次数）
→ 续到新证书后 `nginx -s reload`。整个过程零停机。

手工检查 / 手工续期：

```bash
cat /var/log/followup-cert-renew.log        # 看有没有报错
bash /opt/followup/https/renew-cert.sh      # 想立刻续一次
docker run --rm -v /opt/followup/nginx/letsencrypt:/etc/letsencrypt \
  certbot/certbot:latest certificates       # 看证书到期时间
```

---

## 六、验证清单（装完照着敲一遍）

在自己电脑上（PowerShell）：

```powershell
# 1) http 自动跳 https
curl.exe -I http://yisuifang.work/          # 期望 301，Location: https://yisuifang.work/

# 2) 证书是谁签的、什么时候到期
curl.exe -vI https://yisuifang.work/ 2>&1 | Select-String "issuer|expire|subject"

# 3) 三端页面 + 接口
curl.exe -s -o NUL -w "%{http_code}`n" https://yisuifang.work/
curl.exe -s -o NUL -w "%{http_code}`n" https://yisuifang.work/patient/
curl.exe -s -o NUL -w "%{http_code}`n" https://yisuifang.work/admin/
curl.exe -s https://yisuifang.work/health

# 4) 三套接口冒烟测试（跑一遍才算数）
powershell -File .\tools\api-smoke-test.ps1    -BaseUrl https://yisuifang.work
powershell -File .\tools\portal-smoke-test.ps1 -BaseUrl https://yisuifang.work
powershell -File .\tools\admin-smoke-test.ps1  -BaseUrl https://yisuifang.work
```

还要人工看一眼（脚本看不到的部分）：

| 看什么 | 期望 |
|---|---|
| 地址栏 | 有小锁，点开显示"连接安全" |
| 医护端登录 | 能登录、能进待办 |
| 患者端 | 手机号 + 验证码能进 |
| 管理后台 | 能进账号管理 |
| 手机浏览器 | 用手机关掉 WiFi 用 4G 打开 `https://yisuifang.work/`，能开说明公网真的通了 |

---

## 七、出问题怎么办

### 1. 整体回滚（回到只有 HTTP 的状态）

```bash
cd /opt/followup
rm -f docker-compose.override.yml
cp -f backup/https-<时间戳>/followup.conf.before nginx/followup.conf
docker compose up -d nginx
```

回滚后网站回到 `http://43.129.75.228/`，可用，但仍是明文传输。

### 2. 常见报错

| 报错 | 原因 | 怎么办 |
|---|---|---|
| `dry run failed` / 校验返回 404 | 80 端口没通，或 acme location 被文件末尾的 `location ~ /\.` 正则拦了 | 确认配置里 acme 用的是 `^~` 前缀；`curl -I http://yisuifang.work/.well-known/acme-challenge/x` 不该是 404 |
| `Domain name does not resolve` | DNS 没生效 | `nslookup yisuifang.work`，应返回 43.129.75.228 |
| `Timeout during connect` | 云控制台防火墙没放行 80/443 | 腾讯云控制台 → 轻量应用服务器 → 防火墙，加 TCP 80、443 |
| `port 443 is not published`（脚本自己的报错） | `docker-compose.override.yml` 没放对位置 | 确认文件在 `/opt/followup/` 下，`docker compose config` 能看到 443 |
| `too many failed authorizations` | 失败次数太多被限流 | 等 1 小时再跑，先修好根因 |
| nginx 起不来，日志里 `cannot load certificate` | 证书文件丢了（手工换过配置等） | 先把 `nginx/followup-http-only.conf` 覆盖回 `nginx/followup.conf` 让网站先活，再跑一次 `bash https/install-https.sh` |
| 浏览器证书告警但也能打开 | 用的是 IP 访问，或访问了别的子域 | 证书只覆盖 `yisuifang.work` 和 `www.yisuifang.work`，换地址访问 |

### 3. 看日志的老三样

```bash
cd /opt/followup
docker compose ps
docker compose logs nginx | tail -30
docker compose exec -T nginx nginx -t
```

---

## 八、这次绕开的三个坑（写给下一个改配置的人）

1. **acme 校验目录必须用 `^~` 前缀**
   nginx 的匹配顺序是"最长前缀 → 正则"。配置末尾那条 `location ~ /\. { deny all }`
   是正则，会抢先命中 `/.well-known/acme-challenge/...`，导致校验永远 404。
   `location ^~ /.well-known/acme-challenge/` 才是"命中前缀后不再试正则"。

2. **`add_header` 在 location 里是"全有或全无"**
   server 块里写的 `X-Robots-Tag: noindex` 等安全头，只要某个 location 里出现一条
   `add_header`，这个 location 就**不再继承** server 级的全部头部。
   所以本配置在任何 location 内都没写 `add_header`，缓存改用 `expires` 指令表达。

3. **证书不存在会让整个 nginx 起不来**
   所以新装/迁移时，带 `ssl_certificate` 的配置必须是最后一步才上线的东西。

---

## 九、上线前已经在本机"预演"过一遍

为了不让服务器当小白鼠，22 号晚在开发机上用**同一个版本的 nginx（1.27.5）**
把这两份配置真跑起来了（Windows 版 nginx + 自签证书 + 假页面），逐项验证：

| 验证项 | 命令 | 结果 |
|---|---|---|
| 配置语法 | `nginx -t -c conf/https.conf` | `syntax is ok` / `test is successful` ✅ |
| 配置语法（引导版） | `nginx -t -c conf/http-only.conf` | 同上 ✅ |
| HTTP 跳转（域名访问） | `curl -I -H "Host: yisuifang.work" http://…/` | `301 → https://yisuifang.work/` ✅ |
| HTTP 跳转（用 IP 访问） | `curl -I -H "Host: 43.129.75.228" http://…/patient/` | `301 → https://yisuifang.work/patient/` ✅ |
| **ACME 校验文件可取** | `curl http://…/.well-known/acme-challenge/test-token` | `200 ACME-TOKEN-OK` ✅（这条最关键，坑 1 就是它） |
| 三个端首页 | `curl -k https://…/`、`/patient/`、`/admin/` | 都是 `200` ✅ |
| 前端带指纹资源 | `curl -k https://…/admin/assets/app.js` | `200` + `Cache-Control: max-age=2592000` ✅ |
| 照片 | `curl -k https://…/photos/test.jpg` | `200` + `max-age=604800` ✅ |
| index.html 不吃缓存 | `curl -k https://…/` | `Cache-Control: no-cache` ✅ |
| 安全头没被缓存头挤掉 | 上面每一条响应头 | 全部带 `X-Robots-Tag: noindex, nofollow` ✅ |
| 隐藏文件被拦 | `curl -k https://…/.env` | `404` ✅ |
| 引导版形态 | 用 `http-only.conf` 起一遍 | 三端 200 + ACME 200，80 上业务照常 ✅ |

> 顺带修掉一个只有真跑起来才会发现的问题：`expires -1` 让 `index.html` 每次回源校验。
> 否则发新前端后用户浏览器可能还捧着旧 `index.html`，看起来"没更新"，容易被误判成"部署失败"。
> 注意这里**不能用 `add_header Cache-Control`**，那会把 server 级的安全头整片挤掉（见坑 2）。

---

## 十、部署实录（2026-09-22 晚，实际执行的）

**0. 打通服务器访问**：把协作者的公钥写进服务器 `~/.ssh/authorized_keys`
（root 账号，主机 `VM-0-14-ubuntu`），此后 `ssh root@43.129.75.228` 免密进入。

**1. 上传**（包的 MD5 两侧一致，确认没传坏）

```
followup-https1.zip  c57a5d76fcdbd9e34d28a456a6662733
followup-fix4.zip    d022e4c888f820d1c3e3439e9c5ec09c
```

**2. 先验合并结果再动手**：`docker compose config` 确认 443 已发布、
`/etc/letsencrypt`、`/var/www/certbot` 两个挂载进来了，才开始跑安装。

**3. 安装脚本输出（关键几行）**

```
!! https config found but no certificate yet - falling back to the http bootstrap
  http  /         -> 200      ← 引导版顶上，网站没断
  http  /patient/ -> 200
  http  /admin/   -> 200
-- dry run first (checks DNS + port 80, costs no rate limit)
The dry run was successful.
Successfully received certificate.        ← 正式签发
  https /         -> 200
  https /patient/ -> 200
  https /admin/   -> 200
  https /health   -> 200
  http  /         -> 301   (expect 301)
```

**4. 装完之后的服务器侧复核**

| 复核项 | 命令 | 结果 |
|---|---|---|
| 证书内容 | `openssl x509 -in …/fullchain.pem -noout -subject -issuer -dates -ext subjectAltName` | `CN=yisuifang.work`，Let's Encrypt，SAN 含 www ✅ |
| 续期通道 | `certbot renew --dry-run` | `all simulated renewals succeeded` ✅ |
| 续期脚本 | `bash https/renew-cert.sh` | 执行成功并 reload 了 nginx（当时还没到续期时间，属正常） ✅ |
| 定时任务 | `cat /etc/cron.d/followup-cert-renew` + `systemctl is-active cron` | 已安装，cron `active` ✅ |
| 重启自愈 | `docker compose restart nginx` | 重启后 HTTPS 依旧 200（证书文件在位，不会像没装证书时那样起不来） ✅ |
| 日志 | `docker compose logs nginx --tail 15` | 无 error（唯一的 WARN 是冒烟测试故意触发的"患者越权访问"负例） ✅ |

**5. 公网侧复核**（从开发机，走真实公网）

| 复核项 | 结果 |
|---|---|
| `curl https://yisuifang.work/health` | `200`，`ssl_verify_result=0`（证书链被系统信任，**不是**自签） |
| 三端页面 | 全部 `200` |
| `http://yisuifang.work/`、`http://43.129.75.228/` | 都是 `301 → https://yisuifang.work/...` |
| 浏览器实测（Chromium，**不忽略证书错误**） | 三端标题正常、**0 条明文 http 请求**（无 mixed content）、0 条控制台错误 |
| 患者端接口冒烟 | `portal-smoke-test.ps1 -BaseUrl https://yisuifang.work` → **12 项全绿** |

截图证据：`output/playwright/https-check-staff.png`、`-patient.png`、`-admin.png`。

**6. 同批部署的 fix4**（登录页管理员入口修复，见《patch4-管理员入口修复》）

```
unzip -o /root/followup-fix4.zip        → www/staff/index.html 指向 index-BUD2HSHV.js
线上 Login 分块已不含 127.0.0.1，且带 /admin/
```

> 旧的 `www/staff/assets/*.js` 仍在磁盘上（历史上多个版本累计）。
> **故意不删**：万一有用户浏览器缓存着旧 `index.html`，那些旧文件还能兜住，不会白屏。
> 等确认没人访问旧版本后，可以整目录重传一次做清理。
