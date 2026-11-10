# catpm 协议规范（四层）

catpm 的包生态由四层协议构成。每层只依赖下一层，可以单独实现或替换：

```
┌────────────────────────────────────────────┐
│ 第 4 层  源层（source/registry）            │  包从哪来：本地目录源 / 远程 URL 源
├────────────────────────────────────────────┤
│ 第 3 层  封装层（packaging）                │  包怎么装：.cpkg 归档 + sha256
├────────────────────────────────────────────┤
│ 第 2 层  解析层（resolution）               │  选哪个版本：说明符 → 锁定
├────────────────────────────────────────────┤
│ 第 1 层  清单层（manifest）                 │  包是什么：catpm.json
└────────────────────────────────────────────┘
```

所有 JSON 字段名、文件名、哈希算法均为本规范的固定部分。实现参考：`catpm/src2/`（CatBase 写的参考实现，当前编译产物 `catpm/catpm55`，即 v0.5.5）。

---

## 第 1 层：清单层（manifest）

### 1.1 包清单 `catpm.json`

每个包的根目录必须有一个 `catpm.json`：

```json
{
  "name": "mathx",
  "version": "0.2.0",
  "catpm": "0.2.0",
  "deps": {"stringx": "^0.3.0"},
  "files": ["src/extra.catc"]
}
```

| 字段 | 必填 | 类型 | 说明 |
|---|---|---|---|
| `name` | 是 | str | 包名。小写字母、数字、`-`；不允许 `/`、`@`、大写。入口文件约定为 `index.catc` |
| `version` | 是（作为包时） | str | 三段数字版本 `x.y.z`（语义见第 2 层） |
| `catpm` | 是 | str | 生成该清单的 catpm 版本 |
| `deps` | 否 | dict[str,str] | 依赖：包名 → 版本说明符（第 2 层语法的子集） |
| `files` | 否 | list[str] | 除 `index.catc`/`catpm.json` 外需要打进包里的文件，相对包根的路径 |

**应用项目 vs 包**：同一个文件格式。作为消费方的项目可以不写 `version`；作为包发布的项目必须有 `version` 和 `index.catc`。

### 1.2 项目内布局

```
<project>/
  catpm.json          清单（直接依赖）
  catpm.lock          锁文件（第 2 层，生成的）
  deps/<name>/        安装好的包（源码内置，第 3 层安装产物）
    index.catc
    catpm.json
  .catpm-cache/       下载缓存（第 4 层）
    <name>/<name>-<ver>.cpkg
```

---

## 第 2 层：解析层（resolution）

### 2.1 版本号

`major.minor.patch`，三段非负整数。比较规则为逐段数值比较，缺段按 0：`1.10.0 > 1.9.0`，`1.2 == 1.2.0`。

### 2.2 版本说明符（支持的子集）

| 写法 | 含义 | 等价区间 |
|---|---|---|
| `1.2.3` | 精确版本 | `[1.2.3, 1.2.3]` |
| `^1.2.3` | 主版本内 | `>=1.2.3 <2.0.0` |
| `^0.2.3` | 主版本为 0 时锁次版本（同 npm） | `>=0.2.3 <0.3.0` |
| `~1.2.3` | 次版本内 | `>=1.2.3 <1.3.0` |
| `>=1.2.0` | 下界（含） | — |
| `>1.0.0` | 下界（不含） | — |
| `<2.0.0` | 上界（不含） | — |
| `<=2.0.0` | 上界（含） | — |
| `latest` 或缺省 | 任意，取最高 | — |
| `*` | 任意，取最高（v0.4 新增，`latest` 的同义词） | — |
| `>=0.2.0,<0.4.0` | **逗号 AND 列表**（v0.4 新增）：每个成员都须满足，等价于区间交集 | `[0.2.0, 0.4.0)` |

命令行写法：`catpm add mathx@^1.2.0`（`@` 后整体是说明符）；manifest 里存说明符原文。AND 列表成员间空格可有可无（`>=0.2.0, <0.4.0` 同义）；成员可混用任意已支持写法（如 `^0.3.0,<0.4.0`、`0.2.0,*`）。

**明确不支持**（不虚构）：`x` 通配（`1.x`）、`||` 或关系、`~=`（pip 专用）、预发布后缀（`1.0.0-rc1`）、`latest-1`。原因：`x` 通配需把版本段当模式匹配（当前版本引擎是纯区间比较）；`||` 需把解析结果从单区间改为区间并集（选择规则「取满足说明符的最高版本」将不再良定）；预发布需在比较器里加预发布段排序规则——三者均超出 v0.4 版本引擎（`ver.catc`）的设计范围，留待后续版本。测试 `test_ver.cat` 断言数随版本增长：v0.4/v0.5 44 项，v0.5.2 起 62 项（新增边界与坏输入项）。

### 2.3 选择规则

1. 对一个包名，取源索引里**满足说明符的最高版本**（`best_match`）。
2. 无满足版本 → 报错并列出可用版本，退出码 1。
3. 传递依赖全闭包解析：BFS 从直接依赖出发，队列处理到空为止（不止一级）。

### 2.4 冲突策略

同名包只解析一次，**先到先得**（BFS 序中先出现者的说明符生效）。若后到者要求的说明符不被已锁定版本满足，不失败，记一条冲突警告，写入 lock 的 `# conflicts:` 注释并打到终端。例：A 锁了 `stringx 0.3.0`，B 要 `stringx@<0.3.0` → 警告，仍用 0.3.0。

### 2.5 锁文件 `catpm.lock`

```
# catpm lock file v2 (generated, do not edit)
# format: name version
fmtx 0.1.0
mathx 0.2.0
stringx 0.3.0
```

- 纯文本，一行一包，`name version`（空格分隔）；`#` 开头为注释/冲突警告。
- `list` 显示的版本来自 lock；lock 缺项显示 `?`。
- `remove` 后以新 lock 为「应存在集合」prune `deps/`。
- `catpm lock` 命令：只解析写 lock，不安装（对标 `npm install --package-lock-only` / `pip freeze` 前置步骤）。
- **`install` 是 lock-exact 的**（v0.4 起，对标 `npm ci`）：lock 存在且覆盖 catpm.json 全部直接依赖时，严格按 lock 逐包安装（含 sha256 校验与 prune），**不重新解析**——lock 手改过也照 lock 装（漂移被尊重）；lock 缺失或不完整时回退到全量重解析并重写 lock（对标 `npm install`）。
- `catpm upgrade`（v0.5.4 起的拼法；v0.4–v0.5.3 叫 `update`）：忽略 lock 重新解析，按 manifest 说明符重写 lock 并安装（对标 `npm update` / `apt upgrade`）。v0.5.4 把该命令更名为 `upgrade`，`update` 让位给索引刷新语义（§4.7）。
- `catpm outdated`（v0.4 新增）：对每个已装包查源索引最新版，`current != newest` 标 `-> upgradable`（对标 `npm outdated` / `pip list -o`）。

---

## 第 3 层：封装层（packaging）

### 3.1 包怎么打包：`.cpkg` 归档

`catpm pack` 在包根目录执行，产出 `dist/<name>-<version>.cpkg`：

- 格式：**tar.gz**（GNU tar，`tar -czf`）。系统自带 tar/gzip 即可，无新依赖。
- 归档内路径为**包根相对路径**，不含顶层目录：
  ```
  index.catc        必须有：包入口（使用方 import 的就是它）
  catpm.json        必须有：内嵌清单（版本与 deps 与源清单一致）
  <files...>        可选：catpm.json "files" 列出的额外文件
  ```
- pack 流程：建 `dist/stage-<name>-<ver>/` → 拷入 `index.catc`、`catpm.json`、`files` → `tar -czf dist/<name>-<ver>.cpkg -C stage .` → 删 stage → 计算 **sha256** 并连同字节数打印。

### 3.2 校验和

- 算法：**sha256**（十六进制小写，64 字符）。
- pack 时计算归档哈希；publish 时写入索引（第 4 层）；install 时下载后重算比对，不一致 → 报错退出 1（防篡改/防传输损坏）。
- 参考实现通过 `exec("sha256sum …")` 取哈希（v0.1.8 无内置 sha256，容器 64 位 `hash()` 不是加密哈希——如实记录的权衡）。

### 3.3 安装形态：源码内置（vendoring）

CatBase v0.1.8 的编译模型是「单入口 `.cat` + import 传递展开、无独立编译产物链接」，因此包**以源码形态安装**：

- `install` = 解 `.cpkg` 到 `deps/<name>/`；
- 使用方 `import ./deps/<name>/index.catc as <name>`；
- 包间依赖在包内写 `import ../<dep>/index.catc as <dep>`；
- **别名一致性规则（catcc 硬约束）**：同一文件在全编译单元中必须只用一个别名（钻石依赖成立的前提，违反时报 `Cannot perform operation '+' on types 'str' and 'unknown'`）。约定：**别名一律等于包名**。

### 3.4 预编译二进制 `bin/<name>`（v0.5.3）

源码 vendoring 之外，包**可以**额外携带一个预编译可执行文件 `bin/<name>`（在 catpm.json 的 `files` 里列出，随 pack 进归档）：

- **定位**：独立工具的交付形态（同 apt 直接下 deb）。由于 CatBase 无稳定 ABI/链接器、唯一消费模型是编译期 import 展开，`bin/` **不参与 import 体系**——可 import 的库仍必须是纯源码包。
- **install 时**（v0.5.3 起）：解包后若存在 `deps/<name>/bin/<name>` →
  1. `chmod 0755` 恢复执行位；
  2. 格式/架构校验：ELF（magic `\x7fELF`，e_machine 与 `uname -m` 匹配：62=x86_64、183=aarch64、40=arm、3=x86）**或** `#!` shebang 脚本；两者皆非 → `check FAILED` 标记（安装不中止，源码部分照常落盘）。不采用「跑一下看有无输出」判定的原因：sh 的 ENOEXEC 回退会把任意带执行位的文本当脚本跑出输出，而 v0.1.8 的 `exec()` 拿不到子进程退出码；
  3. 冒烟：`--version`/`--help` 至少一个有输出。
- **publish 时**（v0.5.3 起）：index.json 该版本条目登记可选字段 `bin`：
  ```json
  "bin": { "path": "bin/<name>", "os": "linux", "arch": "x86_64", "sha256": "<内层二进制哈希>" }
  ```
  非 ELF（如 shebang 脚本）登记为 `"os":"any","arch":"any"`。
- **向后兼容**：`bin` 为可选字段——旧 catpm 忽略未知键照常工作；新 catpm 对无 `bin` 字段的条目走纯源码路径（行为与 0.5.2 完全一致）。兼容性双向实测见 `logs/run7.log` [5/8][6/8]。
- 归档整体的 sha256 门不受影响：篡改 .cpkg 任何字节 → MISMATCH → exit 1，零接触（`logs/run7.log` [2/8]）。

---

## 第 4 层：源层（source / registry）

### 4.0 源定义文件 `package.where`（apt sources.list 式）

包从哪来，不再绑死在代码或环境变量里，而由一个**用户可改写的源清单文件**声明。catpm 启动时按以下顺序查找（找到即止）：

| 顺序 | 位置 | 用途 |
|---|---|---|
| 1 | `$CATPM_WHERE` 指向的文件 | 显式指定（CI、测试） |
| 2 | `./package.where`（当前目录） | 项目级源配置 |
| 3 | `<catpm 二进制所在目录>/package.where`（含上溯 2 级） | **默认：与 PM 同仓库** |
| 4 | 都没有 → 回退 `CATPM_REGISTRY` → `./registry` | v0.2 单源兼容模式 |

**文件格式**（一行一源，`#` 注释，空行忽略）：

```
# catpm source list v1 (apt sources.list style)
# <dir-or-URL> [prio=N] [pkg=name1,name2]
/abs/path/registry3                          prio=10
./relative-registry                           prio=5
https://raw.githubusercontent.com/u/r/main/registry    prio=1   pkg=mathx,loganx
```

| 字段 | 必填 | 语义 |
|---|---|---|
| `<dir-or-URL>` | 是 | 源地址。目录须以 `/`、`./`、`../` 开头；URL 须 `http(s)://` 开头。其他形式报错（exit 1） |
| `prio=N` | 否（默认 0） | 源优先级，**越大越优先**。决定两件事：(a) 下载顺序——多源都有同一 name@ver 时按 prio 从高到低尝试；(b) 排序稳定性——prio 相同时按文件行序（稳定排序） |
| `pkg=a,b` | 否（默认全部） | **源钉定（pinning）**：该源只参与列表内包名的解析与下载（apt pin 的简化版）；未列出的包视同该源不存在 |

**拉包规则（实测）**：
1. **版本候选 = 所有（未被 pin 排除的）可用源的并集**。解析器在并集上跑 `best_match`——`mathx 0.2.0/0.3.0@registry3 + 0.4.0@mirror` 并集后 `latest` → `0.4.0`。
2. **下载按 prio 降序回退**：选定 name@ver 后，从含它的最高 prio 源拉取；该源失败（文件缺失/curl 出错）→ 警告并降级到下一含它的源；全失败 exit 1。
3. **索引不可达 ≠ 致命**：某源 `index.json` 拉不到（目录不存在/URL 超时）→ 打警告跳过，其余源照常工作；**全部**不可达才 exit 1。
4. **sha256 恒校验**：无论本地复制、远程下载还是缓存命中，都重算并与该源索引里的哈希比对。
5. **格式错误立即报错（exit 1，带行号）**：地址形式非法、`prio=` 非非负整数、未知选项。重复源行打警告忽略。
6. `CATPM_REGISTRY` 在找到 package.where 时被忽略（打提示），保持单一年度真相源。

命令：`catpm sources` 列出所有已配置源（prio/kind/root/serves/status 一览，并实测可达性）。

对照 apt：`package.where` ↔ `/etc/apt/sources.list`；`prio=` ↔ apt pin-priority；`pkg=` ↔ apt Pin（简化：只按包名，不支持版本表达式）。

### 4.1 索引格式 `index.json`
一个源 = 一个索引 + 一组 `.cpkg` 文件。索引是单文件 JSON：

```json
{
  "packages": {
    "mathx": {
      "0.2.0": {
        "path": "mathx/mathx-0.2.0.cpkg",
        "sha256": "0ffece55f6b5684a63be892b030793f3e3899ef46a848daa0acc261e5bb624d6",
        "deps": {"stringx": "^0.3.0"}
      },
      "0.3.0": { "...": "..." }
    }
  }
}
```

| 字段 | 说明 |
|---|---|
| `path` | 相对源根的 `.cpkg` 路径（远程源即 URL 后缀） |
| `sha256` | 该 `.cpkg` 的 sha256，安装时强制校验 |
| `deps` | 该版本的依赖说明符（内嵌副本，解析层无需下载包体即可全闭包解析） |
| `bin` | **可选**（v0.5.3）：`{path, os, arch, sha256}` 预编译二进制指纹，详 §3.4；旧实现忽略、新实现容缺 |

`catpm publish <dir>` 自动维护本地源的 `index.json`（读取新 `.cpkg` 的哈希 + 源清单的 deps，合并写入）。

### 4.2 两种源（在 package.where 里混用不限量）

| | 本地目录源 | 远程 URL 源 |
|---|---|---|
| 写在 package.where | `/abs/path/registry`、`./rel`、`../rel` | `https://host/.../registry`（`http://` 亦接受） |
| 读索引 | 直接读 `<root>/index.json` | 下载 `<root>/index.json` |
| 取包体 | 复制 `<root>/<path>` | 下载 `<root>/<path>` |
| 发布 | `catpm publish <dir>` | 不支持命令内直接发布（推 git 仓库 + raw URL 即成源，见 §4.4） |

多源时版本候选为**并集**、下载按 `prio` 回退、`pkg=` 钉定——见 §4.0。

### 4.3 下载流程与缓存

1. 需要某包某版本 → 查缓存 `.catpm-cache/<name>/<name>-<ver>.cpkg`；
2. 命中 → 跳过下载（打印 `cached`）；未命中 → 本地复制 / 远程下载；
3. **无论是否命中缓存都重算 sha256 并校验**；
4. `tar -xzf` 到 `deps/<name>/`，检查 `index.catc` 存在，否则报错。

远程下载实现说明（如实记录）：CatBase v0.1.8 内置 `http_get` 对 `https://` 实际发起的是**明文 TCP 连 443**（runtime.zig `parseUrl` 剥掉 scheme 后无 TLS 握手，实测 GitHub 返回 500 / 连接恐慌）。因此参考实现通过 `exec("curl -sS -f -L …")` 完成真实 HTTPS 下载。这是语言运行时的现状，不是协议要求——协议只要求「按 URL GET 字节流并校验 sha256」。

### 4.4 把 git 仓库当远程源（catpm 自身生态的用法）

远程源不需要专门的服务器：任何能按固定 URL 提供 `index.json` 与 `.cpkg` 文件的地方都是源。GitHub 仓库即满足。

**v0.4 起的仓库分离形态**：包集中在专用仓库 **[catpm-registry](https://github.com/monikalnbo/catpm-registry)**（index.json 与 `<name>/<name>-<ver>.cpkg` 放仓库根），catpm 主仓库只保留 PM 本体（源码、二进制、package.where、文档、安装脚本、日志）。默认 `package.where` 指向：

```
https://raw.githubusercontent.com/monikalnbo/catpm-registry/main
```

发布 = `catpm pack` → `catpm publish <registry-仓库检出目录>` → `git push`。注意 registry 仓库的 `.gitignore` 不能含 `*.cpkg` 规则（否则包体进不了 git 树，index.json 里指向 404——v0.3 发布 loganx 时踩过，靠 `git add -f` 补救；catpm-registry 的 .gitignore 只忽略 `.catpm-cache/`）。

### 4.5 自更新：catpm 本体也是源里的一个包（v0.5）

对标 `apt install apt` / `pip install -U pip`：catpm 本体（名字就叫 `catpm`）作为**普通包**挂在源里，`catpm self-update` 完全复用第 4 层协议（package.where 多源解析 → index.json → .cpkg 下载 → sha256 校验），不另造发布机制。包内布局：

```
catpm-registry/
  catpm/
    catpm-0.4.0.cpkg      内含 bin/catpm（预编译 x86_64 ELF）+ 全部源码
    catpm-0.5.0.cpkg      （index.catc、util.catc、ver.catc）
    catpm-0.5.1.cpkg
    catpm-0.5.2.cpkg
```

`catpm.json` 依赖为空（PM 无运行时依赖，仅依赖系统 `tar`/`sha256sum`/`curl`）。

**命令语义**：`catpm self-update [@spec]`——省略 spec 取源中最高版本；`@spec` 用第 2 层说明符语法（`@0.4.0` 精确、`@^0.5.0` 范围均可，显式降级允许）。前缀 `@` 对应 `add pkg@spec` 的写法，实现上先剥去再解析。

**原子替换流程**（任一步失败即中止，旧二进制零接触）：

1. 按 package.where 解析 catpm 包的目标版本（多源版本并集，prio/pkg= 钉定照常生效）
2. 下载 .cpkg 进项目缓存 `.catpm-cache/` → **sha256 门**：与 index.json 记录不符即删缓存中止
3. 解包取 `bin/catpm` 放 `<bindir>/catpm.new`（绝不直接写活文件）→ **冒烟测试**：`catpm.new --version` 输出必须含目标版本号，否则删候选中止
4. 全部通过才 `mv -f catpm.new catpm`（同目录 rename(2)，内核原子）——不存在"半替换"状态

失败实测（`logs/selfupdate5.log`）：源不可达 / sha256 篡改 / 坏二进制候选，三种情况旧版均完好可继续装包，`bin/` 无 `.new` 残留。

**鸡生蛋边界（如实记录）**：catpm 0.4.0 及更早没有 self-update 子命令（如同远古 apt 需先 `apt-get` 装新 apt）。从旧版升级到 ≥0.5.0 走 `curl | sh` 重装或手动放二进制；此后再靠 self-update 演进。

### 4.6 发版规则（自 v0.5.1 起长期生效）

catpm 自身的版本演进遵守固定规则：

1. **版本号固定 +0.0.1**：每次发版在上一版基础上加一个 patch 位（`0.5.0 → 0.5.1 → 0.5.2 → …`），无论改动大小，不跳 minor。第 2 层的语义化比较（§2.1）不受影响——这只是发布节奏约定，不是解析规则。
2. **先 diff 后发版**：发布新版前，对「上一版源码 ↔ 新版源码」做完整真实 diff（`diff -ruN`，覆盖 `catpm/src2/` 全部文件），产出落盘到主仓库 `diffs/v<旧>..v<新>.diff`，人工核对无未预期改动后才发版；diff 文件随发版同一提交推送。此规则保证每个版本对的可审计性——self-update 的用户可以精确看到两次升级之间 PM 本体改了什么。
3. **快照来源**：上一版快照取自已发布 .cpkg 内的源码（`tar -xzOf catpm-<ver>.cpkg ./index.catc` 等）或仓库 git 历史，不用「记忆中的上一版」。
4. **registry 一次到位**（0.5.2 实测教训）：catpm-registry 的推送在源码定稿、diff 核对后**一次推成**；推两次会出现 raw CDN 短暂的「新 cpkg + 旧 index.json」窗口，self-update 的 sha256 校验会正确拦截该窗口内的升级（安全机制生效的实证），但链路实测需等 CDN 一致后再做。

发布顺序（每次相同）：源码定稿 → 全量单测（v0.5.2 起为 62 断言） → 全新编译 → 生成并核对 diff → `catpm pack` → `catpm publish` → git push 两仓库 → raw 直链 200 验证 → self-update 链路实测。

### 4.6a 仓库规范（v0.5.5 起长期生效）

**commit 规范——说明一律不进 commit message**：

- commit message 一律**空白**（`git commit --allow-empty-message`）或至多一个极短词（如 `0.5.5`）；**不写正文、不写长文、不写改动说明**。
- 一切说明进文档：改动动机、设计、实测数据写在 `README.md`、`PROTOCOL.md` 或 `docs/` 下对应文档，commit 只做指针。
- 理由：本仓库的真相源是文档 + 落盘日志 + diff 文件；commit message 是易失性二手信息，双写必然漂移。

**文档规范——README 多写、docs/ 补齐**：

- `README.md` 承担入口职责：安装（curl | sh / 手动）、快速上手、全部命令、配置（package.where / 环境变量）、缓存与 self-update、发版协议、性能说明。
- `docs/` 下按专题补齐：`docs/guide.md`（教程速查：上手 + 进阶两篇的要点索引，权威用法以 README/PROTOCOL 为准）、`docs/perf.md`（性能实测方法与数据）、`docs/release.md`（发版步骤 checklist）、`docs/registry.md`（源与发布操作手册）。后续改动说明**优先落文档**再提交代码。
- 教程文章正文落工作区（`catpm-tutorial.md` 上手篇、`catpm-tutorial-v2.md` 进阶篇），仓库内 docs/guide.md 收编其要点速查；教程中引用的命令、输出、版本号一律来自真实仓库与实测日志，不虚构。

### 4.6b 发版产物规范（v0.5.5 起长期生效）

**registry 只保留最新版本的完整文件**：

- 每次发新版时，`catpm-registry` 里**每个包目录只保留最新版本的 `.cpkg`**；老版本产物文件（旧 `.cpkg`、index.json 中旧版本条目）一律删除，index.json 同步收敛到只含最新版条目。
- **老版本不丢**：老版本的一切内容都在 catpm-registry 的 **git 历史**中——发版删除旧产物的那次 commit 之前的树里，旧 `.cpkg` 与旧 index.json 完整可找回（`git checkout <commit> -- <path>` / `git show <commit>:<path>`）；重要老版本可另打 tag（如 `v0.5.4-last`）便于直接定位。
- **发布产物 = 完整整包**：最新节点（tag / release 附件）与 diff 文件只包含对应版本的完整内容；不做「只含增量的发布产物」。
- **版本替换一律全量**：self-update 与安装脚本下载、替换的都是完整新版文件集（整包 .cpkg → 整个二进制），不做增量补丁、不做字节级差异应用。
- **如实记录的影响（v0.5.5 实测）**：registry 删除老版本后，`catpm add <pkg>@<旧版>` 与 `self-update @<旧版>` 对该旧版本**不可再安装**（解析器在源索引中找不到该版本即报错 exit 1，行为与「版本从未存在过」一致）；锁文件中已装的老版本不受影响（本地 deps/ 与缓存仍是完整整包）。老版本需求从 git 历史找回：检出旧 commit 取回 `.cpkg` 后放入本地源或缓存即可安装。self-update 全量替换链路在删除旧版后实测仍通过（0.5.4→0.5.5）。


### 4.7 索引缓存与 update/upgrade 语义划分（v0.5.4）

对标 `apt update`（只刷新索引）与 `apt upgrade`（应用更新），v0.5.4 起两个动词分工固定：

| 命令 | 语义 | 碰 deps/ 吗 |
|---|---|---|
| `catpm update` | 刷新索引缓存（§下），**不安装任何包** | 否 |
| `catpm upgrade` | 重解析 manifest + 重写 lock + 安装（v0.4–v0.5.3 的 `update` 即此语义） | 是 |

**索引缓存布局**（项目内，随 `.catpm-cache/` 一起属于第 4 层的本地状态）：

```
.catpm-cache/
  index-cache/
    <sha256(root)[0:16]>.json   每源一份：该源 index.json 的原样字节副本
    meta.json                   {"roots": {...}, "fetched_at": {root: epoch秒}, "counts": {root: 条目数}}
```

**刷新（`catpm update`）**：遍历 package.where 全部源（prio 降序），逐源拉取 index.json（远程走 HTTP、本地直读），成功即覆盖写该源的缓存文件并更新 meta；每源打印条目数与较上次增减（`first refresh` / `+N vs last refresh` / `N vs last refresh` / `no change`）。失败语义：某源不可达 → 该源 `ERR ... unreachable`，**本地旧缓存原样保留（last good copy，绝不删除）**；索引非 JSON 对象 → `ERR ... invalid index`（同样保留旧缓存）；其余源照常刷新；只要有失败 → 命令尾行 `PARTIAL FAILURE` + exit 1。

**读路径（`add` / `install` / `lock` / `outdated` / `upgrade`）**：

1. TTL（默认 86400 s，`CATPM_INDEX_TTL=<秒>` 覆盖；非数字/负数回退默认）内有该源的新鲜缓存 → 直接用缓存，不联网；
2. 缓存缺失或已过期 → live 拉取一次，成功顺手写缓存；
3. live 失败但存在旧缓存 → 用旧缓存并打 `STALE` 警告（离线可继续安装已见过的版本）；
4. live 失败且无缓存 → 警告 unreachable；全部源都拿不到 → exit 1。

`catpm sources`（要实测可达性）与 `catpm self-update`（必须看到刚发布的新版本）**恒为 live 拉取**，不读缓存。

**pip 式新版本提示**：`catpm --version` 与 `catpm update` 尾部用 live 索引查 catpm 包最新版，`newest > current` 时打印一行 `notice: new version available: current X, available Y — run 'catpm self-update'`（不改变退出码，不阻塞）；否则静默。

### 4.8 中断恢复（v0.5.5）：任意时刻被杀，重跑即续

协议目标：**PM 进程在任意写入/下载/解包时刻被 SIGKILL / SIGINT / 断网打断，磁盘上不出现半写状态；重跑同一命令自动发现并清理残留后继续，最终结果与一气呵成一致**。

**四层防护（各写路径的强制形态）**：

| # | 规则 | 适用写路径 |
|---|---|---|
| 1 | **原子写**：状态文件一律写 `<path>.catpm-tmp` 再 `mv -f` 同目录改名（rename(2) 原子）；任何时刻被杀，`<path>` 只可能是旧全文或新全文 | catpm.json、catpm.lock、索引缓存每源 json 与 meta.json |
| 2 | **暂存解包**：tar 一律先解进 `deps/.stage-<name>/`，校验 `index.catc` 存在后才删旧 `deps/<name>/` 并 `mv` 换入；`deps/` 内以 `.` 开头的目录对 `list` / prune / fix 均不可见 | install/add 的解包、self-update 的候选暂存（`.catpm-cache/self-stage/`） |
| 3 | **缓存自愈**：下载缓存命中必须先过 sha256 校验；不符（截断/损坏）→ 删除缓存 → 从源整体重拉一次 → 复验；仍不符 → exit 1（篡改语义不变） | `.catpm-cache/<pkg>/<pkg>-<ver>.cpkg`（安装路径与 self-update 路径同款） |
| 4 | **读侧防护**：读 manifest / lock / 索引缓存前校验——json 类必须以 `{` 开头且解析后非空（CatBase `json_loads` 对截断串静默返回空 dict，故必须显式查）；lock 校验 v2 头与行格式；不符 → 明确报错 exit 1，绝不带着坏状态继续 | read_manifest、read_lock、索引缓存读取 |

**残留形态与清扫**：上述机制下，被中断的进程最多留下——`.catpm-tmp` 孤儿、`deps/.stage-<name>/`、`.catpm-cache/self-stage/`、`<bindir>/catpm.new`、截断的缓存 .cpkg。重跑原命令即自愈（各命令入口先清自己的残留）；另有显式 `catpm fix` 一轮扫六类 + 报告 `deps/` 中无 lock 条目的孤儿目录（只报告不擅删）。

**已排除的方案（如实记录）**：不做 HTTP Range 字节级断点续传——恢复采用「检测 → 清理 → 整体重做」；包体积小（KB–百 KB 级），重拉代价可忽略，而 Range 续传需处理源端文件已更换时半截旧文件的一致性校验，复杂度配不上收益。另注：SIGKILL PM 后其 exec 派生的 curl/sh 孤儿子进程不被联动杀死，常会把下载补写完整——下次运行命中合法缓存直接用，视为无害。

---

## 命令对照（pip / npm / catpm）

| 动作 | pip | npm | catpm |
|---|---|---|---|
| 初始化 | — | `npm init` | `catpm init` |
| 装一个包 | `pip install pkg` | `npm install pkg` | `catpm add pkg` |
| 装指定版本 | `pip install pkg==1.2.3` | `npm i pkg@1.2.3` | `catpm add pkg@1.2.3` |
| 范围版本 | `pip install pkg>=1,<2` | `npm i pkg@^1.2.3` | `catpm add pkg@^1.2.3`（也支持 `~` `>=` `<` `>` `<=`、逗号 AND 列表、`*`） |
| 按清单全装 | `pip install -r requirements.txt` | `npm install` | `catpm install`（lock 存在时为 lock-exact，对标 `npm ci`） |
| 按锁精确还原 | （无） | `npm ci` | `catpm install`（lock 完整时自动走 lock-exact 路径） |
| 刷新包索引 | `apt update` | — | `catpm update`（只刷索引缓存，不装包，§4.7） |
| 升级到语义允许的最新 | `pip install -U pkg` | `npm update` | `catpm upgrade`（重解析重写 lock） |
| 查过期 | `pip list -o` | `npm outdated` | `catpm outdated` |
| 只生成锁 | — | `npm i --package-lock-only` | `catpm lock` |
| 列出已装 | `pip list` | `npm ls` | `catpm list` |
| 移除 | `pip uninstall pkg` | `npm uninstall pkg` | `catpm remove pkg`（自动清孤儿） |
| 修复中断残留 | — | — | `catpm fix`（v0.5.5，§4.8；重跑原命令亦自动自愈） |
| 打包 | `python -m build` | `npm pack` | `catpm pack` |
| 发布 | `twine upload` | `npm publish` | `catpm publish <dir>`（本地源） |
| 固定源 | `-i https://pypi.org/simple` | `--registry` | `package.where`（`CATPM_REGISTRY` 为单源兼容） |
| 源清单/多源 | pip.conf `index-url`（单源） | `.npmrc`（单源） | **`package.where`** 多源清单（apt sources.list 式，§4.0） |
| 查看源 | — | `npm config get registry` | `catpm sources`（含可达性检查） |
| 更新 PM 自身 | `pip install -U pip` | （npm 自更新用 nvm/n） | **`catpm self-update [@spec]`**（本体也是源里的包，§4.5；`--version`/`update` 有 pip 式新版本提示，§4.7） |
| 锁文件 | （无标准） | `package-lock.json` | `catpm.lock` |

语义差异（如实记录）：catpm 的 `add` 同时写清单并安装（npm 语义）；pip 的 `install` 对应 catpm 的 `install`。catpm 没有全局安装、没有虚拟环境概念——依赖永远装在项目内 `deps/`。
