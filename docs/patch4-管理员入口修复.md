# patch4：登录页"管理员入口"跳到本机地址的问题

> 发现：2026-09-22 晚（配 HTTPS 时顺手做上线前检查）
> 影响：**线上用管理员身份从医护端登录，一定会跳错页面**
> 包里：`dist-deploy\followup-fix4.zip`（77KB，只动 `www/staff/`）

---

## 一、问题是什么

医护端登录页右上角有个「管理员」切换（用同一套工号密码登录管理后台）。
切到管理员、登录成功后，代码会跳转到"管理后台地址"：

```js
// 改之前 frontend/src/views/Login.vue
const adminUrl = import.meta.env.VITE_ADMIN_URL || 'http://127.0.0.1:5175'
```

`5175` 是**本地开发时**管理后台的端口。项目里没有 `.env.production`，
构建时 `VITE_ADMIN_URL` 没值，于是这个 `127.0.0.1:5175` 被**原样打进了线上包**。
实测线上 `Login-*.js` 里确实躺着这串地址。

后果有两层：

1. 用户点「管理员登录」成功后，浏览器跳到 `http://127.0.0.1:5175`
   —— 那是**用户自己电脑**上的端口，必然打不开（页面直接报错）。
2. 就算本地正好开着开发服务器，管理后台跑在 `127.0.0.1:5175`，
   和线上 `https://yisuifang.work` **不是同一个源**，`localStorage` 里的登录态
   根本带不过去，还是得重新登录一次（跨源 + 明文 http，被浏览器拦）。

## 二、怎么改的

```js
// 改之后 frontend/src/views/Login.vue
const adminUrl = import.meta.env.VITE_ADMIN_URL
  || (import.meta.env.DEV ? 'http://127.0.0.1:5175' : '/admin/')
```

线上管理后台和医护端**同一个域名、同一个端口**，就挂在 `/admin/` 下，
所以生产环境用相对路径 `/admin/` 才是对的：同源跳转，登录态直接复用，
而且 http/https 都不用硬编码。本地开发行为不变（还是 5175）。

## 三、怎么部署

```powershell
scp "F:\医院回访小程序\dist-deploy\followup-fix4.zip" ubuntu@43.129.75.228:/home/ubuntu/
```

```bash
cd /opt/followup
unzip -o /home/ubuntu/followup-fix4.zip     # 覆盖 www/staff/ 下的 index.html 和 assets/
```

**不用重启任何容器**（这三个前端目录是静态文件，nginx 直接读）。

## 四、怎么验证

```powershell
# 1) 线上首页应该引用新的入口文件
curl.exe -s http://43.129.75.228/ | Select-String "index-"
#    期望 index-BUD2HSHV.js

# 2) 新的 Login 分块里不应该再有 127.0.0.1，且应该带 /admin/
#    （HTTPS 还没装好的话把 https://yisuifang.work 换成 http://43.129.75.228）
$base = "http://43.129.75.228"
curl.exe -s "$base/assets/Login-DUAmpNO-.js" | Select-String "127.0.0.1"   # 期望没有输出
curl.exe -s "$base/assets/Login-DUAmpNO-.js" | Select-String "/admin/"     # 期望有输出
```

再用 A0001 在医护端登录页切到「管理员」登录一次，应该直接进 `https://yisuifang.work/admin/`
并且不用再登一次（登录态跟着走）。

## 五、顺带记一笔

这次打包**没有**包含 `www/staff/photos/`（照片没变，不需要重复传）。
`unzip -o` 只覆盖包里有的文件，旧 `assets/*.js` 会留在磁盘上——
它们不会再被引用，属于无害残留；要清理的话下次整包重传时一起删。
