# catpm 源探测 · 新手指南

这份文档是写给**第一次用**的人的：不需要看懂协议，照着复制粘贴就行。
文中每一段输出都是本机真实运行后粘贴的（对应 `evidence/logs/09`–`12`）。

---

## 0. 先搞清楚三个词

| 词 | 大白话 |
|---|---|
| **包** | 一个能装的东西，比如 `hellox`。 |
| **源** | 一个「包仓库」的网址。catpm 从源里下载包。 |
| **package.where** | 服务器上的**源清单**，一行一个源。catpm 装包时就来这里找。 |

一个 GitHub 仓库**能当源**的前提：它里面有个合法的 `index.json`（包目录清单），
并且包体文件（`.cpkg`）放在对应位置。只有代码、没有 `index.json` 的普通仓库**不能**当源。

---

## 1. 最常用的一条命令：看看某个仓库有没有源

```bash
probe monikalnbo/catpm-registry
```

就这一条。`monikalnbo/catpm-registry` 换成你想查的 `用户名/仓库名`。
**它只看不改**：不会动服务器清单，也不会装任何东西。

### 有源的时候，你会看到这个

```text
正在检查 GitHub 仓库：monikalnbo/catpm-registry
（会依次试 main / master 分支下常见位置，通常几秒到十几秒）

结论：这个仓库有 catpm 源 ✅

  源地址：https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
  在哪找到：分支 main，位置 (root)
  里面共有 9 个包、9 个版本：

    catpm        0.5.5
    fmtx         0.1.0
    hashx        0.1.0
    hellox       1.0.0
    loganx       0.1.0
    mathx        0.5.0
    randx        0.2.0
    stringx      0.3.0
    timex        0.1.0

下一步怎么用这条源：
  1) 正式加进服务器源清单（会先备份原清单）：
     probe monikalnbo/catpm-registry --add
  2) 加完后刷新索引并装包：
     cd ~/catpm-demo && catpm update && catpm add <包名>
     或者一条命令全做：catpm-quickstart monikalnbo/catpm-registry <包名>（--branch 探测到的源请先手动 --add）
```

看到 `✅`、源地址、包列表，就成功了。工具还会把「下一步该敲什么」直接打出来。

### 没有源的时候，你会看到这个（这是正常结论，不是报错）

```text
结论：这个仓库里没有 catpm 源 ❌

说人话：它只是一个普通的 GitHub 代码仓库，不是「包仓库」，所以不能拿来当源。
（工具已经检查了 main/master 分支下的根目录、packages/、registry/ 等常见位置，
  没有任何一个位置存在合法的 index.json —— catpm 源必须有这个文件。）

常见原因 / 怎么办：
  · 仓库名写错了？去浏览器打开 https://github.com/<用户名>/<仓库名> 核对一下。
  · 源其实在别的分支或子目录？用 --branch 指定分支、--paths 指定子目录后再试。

（这只说明「这个仓库不适合当源」，不是出错，服务器上的东西一点没动。）
```

### 判断不了的时候，你会看到这个（也不是报错，重试或换仓库即可）

```text
结论：现在没法判断这个仓库有没有源 ⚠️

原因：GitHub 上查不到这个仓库（不存在，或者是私有仓库）。
...
注意：这不代表「仓库没有源」，只是这次没检查成功，可以稍后重试。
```

---

## 2. 把这条源写进服务器清单（会先自动备份）

```bash
probe monikalnbo/catpm-registry --add
```

会发生三件事：

1. 探测（同上面第 1 步）；
2. 命中后，**先把原清单复制一份备份**，再把源追加进 `/root/.local/bin/package.where`；
3. 屏幕上直接打印**撤销命令**，复制就能回滚。

真实输出（节选，完整见 `evidence/logs/11-rollback.log`）：

```text
正在把这条源加入服务器清单 …
  已备份原清单 -> /root/.local/bin/package.where.bak.20261112-000608
  已写入：https://raw.githubusercontent.com/monikalnbo/catpm-registry/main prio=5

撤销方法（复制粘贴即可）：
  cp -p '/root/.local/bin/package.where.bak.20261112-000608' '/root/.local/bin/package.where'
撤销后建议再跑：catpm update
```

### 怎么回滚

把上面那行 `cp -p ...` 原样复制执行，然后：

```bash
catpm update
```

就回到改动前的状态。`evidence/logs/11-rollback.log` 里实测了整条路径：
回滚后文件的 sha256 与「改动前」**逐字节一致** ✅。

同一个源重复 `--add` 不会写第二行（工具会提示「清单里已经有这条源了」）。

### prio 是什么？要不要改？

`prio` 是优先级，**数字越大越优先**。不写默认 5；官方源通常用 10。
一般不用管，只有多个源提供同一个包、你想让某个源优先时才需要：

```bash
probe owner/repo --add --prio 10
```

---

## 3. 一条命令跑完：探测 → 写清单 → 刷新 → 真实下载安装

```bash
catpm-quickstart monikalnbo/catpm-registry hellox 1.0.0
```

参数格式：`catpm-quickstart <用户名>/<仓库名> <包名> [版本号]`。
它默认为你准备一个演示项目目录 `~/catpm-demo`，所有下载都装在那里，不污染别的目录。

四个步骤，屏幕上都会打中文说明：

| 步骤 | 在做啥 | 成功长什么样 |
|---|---|---|
| 第 1 步 | 探测 + 把源写进清单（已有则跳过） | `结论：这个仓库有 catpm 源 ✅` / `清单里已经有这条源了` |
| 第 2 步 | 打印当前清单 | 你刚加的源出现在列表里 |
| 第 3 步 | `catpm update` 刷新索引 | `index cache updated: 1 ok, 0 failed, ... entries total` |
| 第 4 步 | 真实下载并安装 | `installed hellox@1.0.0 (sha256 ok)` |

真实输出（节选，完整见 `evidence/logs/10-quickstart.log`）：

```text
== 第 3 步 / 4：刷新索引（catpm update）
catpm: refreshing package index from 1 source(s)
  OK   https://raw.githubusercontent.com/monikalnbo/catpm-registry/main  9 entries (first refresh)
catpm: index cache updated: 1 ok, 0 failed, 9 entries total (age out after 86400s; override with CATPM_INDEX_TTL)

== 第 4 步 / 4：从源真实下载安装 hellox@1.0.0
catpm: added hellox '1.0.0' to catpm.json (resolves to 1.0.0)
catpm: resolved 1 package(s):
  - hellox@1.0.0
catpm: installing into ./deps/
  prefetch hellox@1.0.0 <- https://raw.githubusercontent.com/monikalnbo/catpm-registry/main/hellox/hellox-1.0.0.cpkg
  cached .catpm-cache/hellox/hellox-1.0.0.cpkg
  installed hellox@1.0.0 (sha256 ok) -> deps/hellox/index.catc
  prebuilt bin/hellox ok (linux-x86_64 / x86_64, executable) -> deps/hellox/bin/hellox
catpm: wrote catpm.lock

== 结果
已安装（/root/catpm-demo/deps）：
    hellox  1.0.0
包体缓存与 sha256（与索引里的值比对过，一致才会安装）：
  a740f5400969fca1b516f0e8526f2f8250d204c40a4e937ff43115a65dbe92e6  .catpm-cache/hellox/hellox-1.0.0.cpkg
```

想确认真的能跑：

```bash
~/catpm-demo/deps/hellox/bin/hellox
# 输出：
# hello 1.0.0
# hellox says hi
```

如果最后一步失败（包名/版本不在源里），工具会停下来并提示先看上面列出的可用版本。

> 注意：带 `--branch` / `--paths` 探测到的源（比如历史提交里的源），
> `catpm-quickstart` 无法一条命令指定，请先 `probe ... --add` 手动加源，再 `catpm add`。

---

## 4. 失败了怎么判断（常见原因对照表）

| 你看到的 | 含义 | 怎么办 |
|---|---|---|
| `结论：这个仓库里没有 catpm 源 ❌` | 仓库存在，但里面没有合法 `index.json` | 确认仓库名；源可能在别的分支/子目录 → 加 `--branch 分支 --paths 子目录` 再试 |
| `原因：GitHub 上查不到这个仓库（不存在，或者是私有仓库）` | 仓库不存在，或私有仓库匿名读不到 | 核对仓库名；私有仓库需先公开（catpm 目前不支持账号凭据） |
| `原因：网络连不上 GitHub（或请求被限流/代理拦截）` | 网络问题 | `curl -I https://github.com` 测网络；检查/关闭 `HTTPS_PROXY`；等几分钟再试（未登录 GitHub API 每小时 60 次） |
| `probe：仓库要写成 用户名/仓库名` | 参数写错 | 写成 `owner/repo`，不要只写一个词 |
| `catpm: warning: source unreachable` / `PARTIAL FAILURE` | catpm 访问不到清单里的源 | 这条源地址本身无效或网络不通，用 `probe` 重新确认地址 |
| `安装失败（包名或版本可能不在源里）` | 源里没有这个包/版本 | 看上面列出的可用包和版本，换一个 |
| `找不到 probe / catpm 命令` | 命令没装或不在 PATH | 本机已装在 `/root/.local/bin/`，确认该目录在 `PATH` 里 |

**关键区分**：`❌ 没有源` 和 `⚠️ 没法判断` 是两回事。
前者是确定结论，后者只是这次没查成（网络/私有仓库/限流），不代表没有源。

### 退出码（给写脚本的人看）

| 退出码 | 含义 |
|---|---|
| 0 | 有源（或写入成功） |
| 1 | 确定不是 catpm 源 |
| 2 | 参数写错 |
| 3 | 无法判断（网络/限流/仓库不存在或私有） |

---

## 5. 常用参数速查

```bash
probe owner/repo                      # 只看有没有源
probe owner/repo --add                # 有源就写进服务器清单（自动备份）
probe owner/repo --add --prio 10      # 顺便指定优先级（越大越优先）
probe owner/repo --branch dev         # 只看指定分支（可逗号分隔多个）
probe owner/repo --branch 3f2a1c9 --paths registry   # 看历史提交下的子目录
probe owner/repo --verify             # 额外下载每个包体、重算 sha256 比对（慢一些）
probe owner/repo -v                   # 连技术细节一起打印（排错用）
probe --help                          # 帮助

catpm-quickstart owner/repo 包名 [版本]   # 一条命令跑完全链路
```

带 `--verify` 时，只要有一个包体的 sha256 对不上，工具就**拒绝写入清单**——宁可停下也不装来路不对的包。

---

## 6. 服务器当前状态

生效的源清单是 `/root/.local/bin/package.where`（与 catpm 二进制同目录，所以任意目录下都生效）：

```text
# catpm source list v1 (apt sources.list style)
# <dir-or-URL> [prio=N] [pkg=name1,name2]
# generated by catpm-probe on 2026-11-11T15:55:36Z
https://raw.githubusercontent.com/monikalnbo/catpm-registry/main prio=10
https://raw.githubusercontent.com/monikalnbo/catpm/c78a90f/registry prio=5
```

- 第 1 行：官方源，9 个包；
- 第 2 行：此前自建 registry 的现存形态（`c78a90f` 提交下的 `registry/` 目录），
  提供官方源已清理的旧版本（如 `mathx@0.2.0`）。优先级更低，同名同版本时仍走官方。

改动前的原始清单备份在 `evidence/package.where.orig`。

---

## 7. 想自己复现/排错

所有真实运行日志都在 `evidence/logs/`：

| 文件 | 内容 |
|---|---|
| `09-beginner-probe.log` | `probe` 五种场景：有源 / 无源 / 仓库不存在 / 网络不通 / 参数错 |
| `10-quickstart.log` | 一键命令完整链路 + 重复执行的幂等行为 |
| `11-rollback.log` | 自动备份、按提示回滚、sha256 逐字节校验、重复写入去重 |
| `12-matrix-rerun.log` | 三组验证矩阵（官方源 / 旧自建源 / 普通仓库负例） |

更底层的协议细节、实现说明见 `README.md`。
