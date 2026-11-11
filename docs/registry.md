# catpm 源（registry）操作手册

源层的协议规范见 [PROTOCOL.md §4](../PROTOCOL.md)；本文是用户与维护者视角的操作手册：怎么配源、怎么发布包、怎么管理 registry 仓库。

> 想先确认「某个仓库到底能不能当源」，用仓库里的探测工具：`tools/srcprobe/probe <用户名>/<仓库名>`。
> 它会直接告诉你有没有源、源地址、里面有哪些包；加 `--add` 可写进清单（自动备份），
> 用法见 [tools/srcprobe/GUIDE.md](../tools/srcprobe/GUIDE.md)。

## 源是什么

一个源 = 一个 `index.json` + 一组 `.cpkg` 文件，放在**一个目录**（本地源）或**一个 URL 前缀**（远程源）下。不需要任何服务器软件：GitHub 仓库 + raw 直链就是一个完整的远程源（catpm-registry 即如此运行）。

```
<registry-root>/
  index.json                     # 单文件索引：全部包的全部版本
  mathx/mathx-0.4.0.cpkg         # 包体（tar.gz）
  stringx/stringx-0.3.0.cpkg
  catpm/catpm-0.5.5.cpkg         # catpm 本体也是包（self-update 用）
```

## 配源：package.where

放哪（找到即止）：`$CATPM_WHERE` → `./package.where` → **catpm 二进制所在目录**（默认形态，安装器自动放好）→ 回退 `CATPM_REGISTRY` 单源。

```bash
catpm sources       # 列出全部源 + 实测可达性（恒 live，不读缓存）
```

格式（一行一源，`#` 注释）：

```
# <dir-or-URL> [prio=N] [pkg=name1,name2]
/abs/path/registry3                                 prio=10
./my-local-registry                                  prio=5
https://raw.githubusercontent.com/monikalnbo/catpm-registry/main    prio=1
/mirror                                              prio=20  pkg=mathx
```

- **版本候选 = 全部源的并集**，`latest`/`*` 取并集中最高版本。
- **下载按 prio 降序回退**：同一 name@ver 多源都有时，从最高 prio 源拉，失败降级到下一个。
- **`pkg=` 钉定**：该源只参与所列包名的解析。
- 索引缓存（v0.5.4+）：`catpm update` 刷新，读命令 TTL（默认 86400s，`CATPM_INDEX_TTL` 覆盖）内走缓存；某源不可达保留旧缓存并打 STALE 警告。

## 发布一个包（维护者）

```bash
# 1. 包目录：index.catc + catpm.json（name/version/deps/files）
cd mypkg
catpm pack                      # -> dist/mypkg-1.0.0.cpkg（打印 sha256 与字节数）

# 2. 发布进本地 registry 检出目录（自动合并 index.json）
catpm publish ~/checkouts/catpm-registry

# 3. 推送 = 发布（raw URL 即源）
cd ~/checkouts/catpm-registry
git add -A
git commit --allow-empty-message --no-edit -a    # 极短或空白 message（规范见 docs/release.md）
git push
```

注意事项（都踩过）：

- registry 仓库的 `.gitignore` **不能**含 `*.cpkg`——否则包体进不了 git 树，index.json 指向 404。catpm-registry 的 .gitignore 只忽略 `.catpm-cache/`。
- **一次推成**：源码定稿后再推，不推中间版。raw CDN 有几分钟的新旧不一致窗口，期间 self-update 的 sha256 校验会正确拦截（安全机制，不是 bug），等 CDN 一致即可。
- 预编译二进制包：包内加 `bin/<name>` 并列进 catpm.json 的 `files`，publish 自动在 index.json 登记 `bin` 指纹（os/arch/内层 sha256）。详见 PROTOCOL.md §3.4。

## registry 只留最新版（v0.5.5 起长期规则）

每个包目录**只保留最新版本的 .cpkg**，index.json 同步收敛；老版本从 git 历史找回。操作细节与影响实测见 [release.md](release.md#registry-只留最新版操作细节)。要点：

- 删除后 `catpm add <pkg>@<旧版>` 如实报错 exit 1（该版本已不在源里）。
- 已装项目零影响（deps/ 与缓存是完整整包）。
- 找回：`git show <commit>:<name>/<name>-<ver>.cpkg > x.cpkg` → 放入本地目录源即可再装。
- 每次清理后必须复测 self-update 全量替换链路。

## 把任意 git 仓库变成源

不需要 GitHub Pages / release 附件 / 专门服务器：

```
https://raw.githubusercontent.com/<user>/<repo>/main
```

只要该 URL 前缀下能 GET 到 `index.json` 与 `.cpkg` 文件，就是一个合法远程源。私有仓库不行（raw 需要认证，curl 匿名拿不到）。

## 环境变量一览

| 变量 | 作用 | 默认 |
|---|---|---|
| `CATPM_WHERE` | 显式指定 package.where 路径 | （不设） |
| `CATPM_REGISTRY` | 单源兼容回退（v0.2 行为） | `./registry` |
| `CATPM_INDEX_TTL` | 索引缓存时效（秒） | 86400 |
| `CATPM_INSTALL_DIR` | 安装器目标目录（install.sh） | `~/.local/bin` |

## 常见问题

**Q: 装包时报 `not found in any source`？**
先 `catpm sources` 看可达性；再看版本说明符是否把候选全排除了（`add pkg@^2` 而源里只有 1.x 时报错并列出可用版本）。

**Q: 索引改了但 catpm 还看到旧版本？**
TTL 内读缓存是设计行为；`catpm update` 立即刷新，或设 `CATPM_INDEX_TTL=0`。

**Q: 想装一个已被清理的老版本？**
从 registry git 历史取回 .cpkg（见上），放进本地目录源；或直接把老版本 cpkg 所在目录 publish 成一个新的本地源。注意：放进 `.catpm-cache/` 不够——索引里没有该版本条目时解析器不会选它。
