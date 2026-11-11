# 2026-11-11 · 源探测工具 + 服务器源清单

这次更新加了两条命令（`probe`、`catpm-quickstart`）和一个探测引擎（`catpm-probe`），
并给本机配置了一份可用的源清单。下面三块分开写：做了什么、解决了什么、修了什么 bug。
每条结论都来自仓库里 `tools/srcprobe/evidence/logs/` 下的真实运行记录。

---

## 一、这次更新做了什么

### 1. 新增探测命令 `probe`（给人用的）

```bash
probe <用户名>/<仓库名> [--add] [--prio N] [--branch 分支] [--paths 子目录] [--verify]
```

它做一件事：判断一个 GitHub 仓库**能不能当 catpm 源**，并用人话告诉你结论。

- 有源：打印 `✅`、源地址、这个源里有哪些包和版本、下一步该敲什么命令（`09-beginner-probe.log` 场景 A）；
- 没有源：打印 `❌` 和原因（普通代码仓库、缺 `index.json`），这不是报错，服务器上的东西一点不动（同日志场景 B）；
- 查不了：打印 `⚠️` 并区分「仓库不存在/私有」和「网络不通/被限流」，不冒充「没有源」（同日志场景 C、D）；
- 参数写错：一句中文提示，不抛堆栈（场景 E）。

`--add` 会把源写进清单，**写之前先自动备份**，然后把撤销命令打印出来（`11-rollback.log`）。

### 2. 新增一键命令 `catpm-quickstart`（跑完整条链路）

```bash
catpm-quickstart <用户名>/<仓库名> <包名> [版本]
```

一条命令依次做四步：探测 → 写清单（自动备份）→ `catpm update` 刷新索引 → `catpm add` 真实下载安装并校验 sha256。
每一步都打中文说明；演示项目固定放 `~/catpm-demo`，不污染别的目录。真实产物见 `10-quickstart.log`：
`installed hellox@1.0.0 (sha256 ok)`，缓存 sha256 `a740f540…` 与官方索引一致，预编译二进制运行输出 `hello 1.0.0`。

### 3. 新增探测引擎 `catpm-probe`（给脚本用的）

`probe` 的底层。只依赖 bash + curl + python3。行为要点：

- 默认分支走 GitHub API，再补 `main`/`master` 兜底；
- 依次尝试根目录、`packages/`、`registry/` 等 7 个常见路径；
- 严格校验 `index.json` 的协议字段（`packages` 非空、每个版本有 `path` 和 64 位 `sha256`），
  **绝不把「HTTP 200 但不是合法索引」当成源**；
- 退出码分档：`0` 命中 / `1` 确定不是源 / `2` 参数错 / `3` 无法判断；
- 支持 `--write`、`--replace`、`--prio`、`--pkg`、`--verify-cpkg`、`--json`。

### 4. 配置了服务器源清单

生效文件 `~/.local/bin/package.where`（与 catpm 二进制同目录，任意工作目录都能读到）：

```text
https://raw.githubusercontent.com/monikalnbo/catpm-registry/main prio=10
https://raw.githubusercontent.com/monikalnbo/catpm/c78a90f/registry prio=5
```

- 第一行是官方源（9 个包）；
- 第二行是 v0.4 拆分 registry 仓库之前、本仓库 `c78a90f` 提交下 `registry/` 目录的内容，
  提供官方源已清理的旧版本（`mathx@0.2.0` 等），优先级更低，同名同版本仍走官方。

`catpm update` 实测：`2 ok, 0 failed, 14 entries`；两组来源都真实装包成功并核对 sha256
（`03-refresh.log`、`04-download-official.log`、`05-download-own-registry.log`）。

### 5. 文档

- `tools/srcprobe/GUIDE.md`：新手指南，每步在干嘛、成功输出长什么样、失败怎么判断；
- `tools/srcprobe/evidence/logs/01–13`：全部原始运行记录；
- 本文件所在的 `docs/updates/`：更新记录目录，约定见同目录 `README.md`。

### 6. 怎么用

```bash
# 不想装到 PATH，直接在仓库里跑也行：
tools/srcprobe/probe monikalnbo/catpm-registry

# 想装成全局命令：
install -m 0755 tools/srcprobe/probe tools/srcprobe/catpm-probe tools/srcprobe/catpm-quickstart ~/.local/bin/

# 只看不改
probe monikalnbo/catpm-registry

# 写进清单（自动备份 + 打印回滚命令）
probe monikalnbo/catpm-registry --add

# 一条命令跑完整链路
catpm-quickstart monikalnbo/catpm-registry hellox 1.0.0
```

回滚：`--add` 会把备份路径写在屏幕上，复制那行 `cp -p '<备份>' '<清单>'`，再 `catpm update` 即可。
实测回滚后的文件与改动前**逐字节一致**（`11-rollback.log`）。

---

## 二、解决了什么问题

| 之前 | 现在 |
|---|---|
| 想知道一个仓库能不能当源，只能手动拼 raw 地址、逐个试路径，还要自己看 JSON 对不对 | 一条 `probe owner/repo`，几秒内给出结论、源地址、包列表和下一步命令 |
| 试错时容易把「HTTP 200 的普通 JSON」误当索引，或者把网络故障当成「仓库没源」 | 三层结论分开：有源 / 确定没有 / 无法判断；只有协议字段全齐才算命中 |
| 改 `package.where` 没有护栏，改错了只能凭记忆恢复 | `--add` 自动备份并打印撤销命令；同一源重复添加会自动去重 |
| 探测、写清单、刷新、下载要分四步手动做，每步都可能漏 | `catpm-quickstart` 一条命令全做，每步有中文说明，失败就停并说明原因 |
| 旧版本包（如 `mathx@0.2.0`）在官方源里已被清理，装不回来 | 清单里补了 `c78a90f` 历史提交下的旧源，优先级更低，实测能装且 sha256 一致 |
| 新手看不懂英文报错和退出码 | 所有提示是中文大白话；退出码 0/1/2/3 有明确含义，写脚本也能判断 |

---

## 三、修了什么 bug

本次没有修改 catpm 本身（`catpm/src2/catpm.cat` 未动）。下面都是**新工具在开发和实测中暴露、并已修掉**的问题，
逐条标明是怎么发现的：

1. **清单文件权限不对**：`--replace` 写出的清单权限是 `0600`，和安装器生成的 `0644` 不一致，
   换用户/换进程读取可能失败。已改为写入后 `chmod 0644`。
   来源：`evidence/logs/08-final-verification.log` 里的权限修正记录。

2. **`probe` 在「没有源」时退出码仍是 0**：脚本拿它做判断会误以为成功。已改为「没有源」退出 1、「无法判断」退出 3。
   来源：`09-beginner-probe.log` 五个场景的退出码（0/1/3/3/2）。

3. **`probe` 不认 `--paths`**：想探测历史提交下 `registry/` 子目录时参数被丢掉，导致明明有源却报没有。
   已补上参数解析，`--branch c78a90f --paths registry` 现能命中（`12-matrix-rerun.log` 用例 ②）。

4. **`probe` 打印了一条永远跑不通的建议命令**：命中后曾提示 `catpm-probe --write "$SRC_URL"`（参数根本不是这个意思）。
   已删除，改成真正可用的两条下一步命令。

5. **`catpm-quickstart` 的回滚提示会说错话**：即使这条源原本就在清单里，也会说「清单是这次新建的，直接删文件」。
   已改为先记录「改动前清单是否存在」，只有确实新建时才建议删除，否则给出「无需回滚」。

6. **`catpm-quickstart` 在指定了自定义清单时仍去读默认清单**：设置 `CATPM_WHERE_FILE` 后，`probe` 写的是指定文件，
   但后续 `catpm` 命令读的却是默认清单。原因是 catpm 认的是 `CATPM_WHERE` 而不是 `CATPM_WHERE_FILE`。
   已在脚本里把两者同步，修复后同一场景的 `catpm update` 只刷新指定的那 1 个源（`12-matrix-rerun.log` 用例 ①）。

7. **帮助文本把脚本代码也打出来了**：`probe --help` 末尾会多出一行 `set -u`，`catpm-probe --help` 同样越界。
   已修正截取行号，帮助只剩用法说明（`13-final-check.log`）。

8. **源地址去重判断有缺陷**：早期写法在某些 shell 下会把地址比较弄错，可能重复写入同一行。
   已改为逐行取第一列做精确整行匹配，重复写入时明确提示「清单里已包含该源地址，不重复写入」
   （`11-rollback.log` 第 7 步实测两次均命中去重）。

9. **根目录源的 URL 多一个斜杠**：探测根目录时拼出了 `.../repo/main//index.json`。
   已对根目录单独处理，`--verify-cpkg` 的包体下载地址也一并正确。

10. **`--verify-cpkg` 抽检失败时没有阻断写入**：一次校验脚本写错（把 import 和代码挤在一行）导致语法错误，
    且失败后没有明确退出。已拆开修正，并把「校验不过就拒绝写清单」变成硬约束（退出 3）。

11. **网络失败路径会让脚本直接崩**：引擎开了 `set -u`（未定义变量即报错退出），
    但「最后一条非索引响应」「最后一条网络错误」「网络失败计数」这几个变量只在失败分支里赋值，
    在无命中或网络故障时会因变量未定义而中断，拿不到本该给出的「无法判断」结论。
    已改为开头统一声明默认值，网络故障现在稳定返回退出码 3（`09-beginner-probe.log` 场景 D）。

---

## 四、这次没做 / 已知限制

- 私有仓库用不了：匿名 raw 读不到，catpm 也没有账号凭据配置；
- GitHub 未登录 API 每小时 60 次，查太频繁会得到「无法判断」，等几分钟即可；
- `catpm update` 的索引缓存是**项目内**的，换目录要重新刷新；
- `catpm add` 一次只能装一个包；
- 带 `--branch`/`--paths` 找到的源，`catpm-quickstart` 不能一条命令指定，需先 `probe ... --add`。

以上均未在本次修改，属于协议与工具现状，如实记录。

## 五、怎么复现

```bash
cd <仓库根目录>

# 1. 探测（只看不改）
tools/srcprobe/probe monikalnbo/catpm-registry

# 2. 无源负例（应给出「没有源」并退出 1）
tools/srcprobe/probe monikalnbo/catpm

# 3. 历史提交下的旧源（应命中共 4 个包 5 个版本）
tools/srcprobe/probe monikalnbo/catpm --branch c78a90f --paths registry

# 4. 一键全链路（会改本机清单，改动前自动备份）
tools/srcprobe/catpm-quickstart monikalnbo/catpm-registry hellox 1.0.0
```

逐条对照 `tools/srcprobe/evidence/logs/09`–`13`，输出应与日志一致。
