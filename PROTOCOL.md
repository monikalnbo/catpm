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

所有 JSON 字段名、文件名、哈希算法均为本规范的固定部分。实现参考：`catpm/src2/`（CatBase 写的参考实现，编译产物 `catpm/catpm2`）。

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

命令行写法：`catpm add mathx@^1.2.0`（`@` 后整体是说明符）；manifest 里存说明符原文。

**明确不支持**（不虚构）：`*`、`x` 通配（`1.x`）、`||` 或关系、逗号 AND 列表、`~=`（pip 专用）、预发布后缀（`1.0.0-rc1`）、`latest-1`。实现于 `ver.catc` 的 `satisfies()`，测试 `test_ver.cat` 29 项断言。

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

远程源不需要专门的服务器：任何能按固定 URL 提供 `index.json` 与 `.cpkg` 文件的地方都是源。GitHub 仓库即满足——`main` 分支的 `registry/` 目录通过 `https://raw.githubusercontent.com/<user>/<repo>/main/registry/index.json` 即为索引 URL。发布 = 向该仓库提交新的 `.cpkg` 与更新后的 `index.json`（catpm 仓库里的 `scripts/publish-remote.md` 给出三步流程）。

---

## 命令对照（pip / npm / catpm）

| 动作 | pip | npm | catpm |
|---|---|---|---|
| 初始化 | — | `npm init` | `catpm init` |
| 装一个包 | `pip install pkg` | `npm install pkg` | `catpm add pkg` |
| 装指定版本 | `pip install pkg==1.2.3` | `npm i pkg@1.2.3` | `catpm add pkg@1.2.3` |
| 范围版本 | `pip install pkg>=1,<2` | `npm i pkg@^1.2.3` | `catpm add pkg@^1.2.3`（也支持 `~` `>=` `<` `>` `<=`） |
| 按清单全装 | `pip install -r requirements.txt` | `npm install` | `catpm install` |
| 只生成锁 | — | `npm i --package-lock-only` | `catpm lock` |
| 列出已装 | `pip list` | `npm ls` | `catpm list` |
| 移除 | `pip uninstall pkg` | `npm uninstall pkg` | `catpm remove pkg`（自动清孤儿） |
| 打包 | `python -m build` | `npm pack` | `catpm pack` |
| 发布 | `twine upload` | `npm publish` | `catpm publish <dir>`（本地源） |
| 固定源 | `-i https://pypi.org/simple` | `--registry` | `package.where`（`CATPM_REGISTRY` 为单源兼容） |
| 源清单/多源 | pip.conf `index-url`（单源） | `.npmrc`（单源） | **`package.where`** 多源清单（apt sources.list 式，§4.0） |
| 查看源 | — | `npm config get registry` | `catpm sources`（含可达性检查） |
| 锁文件 | （无标准） | `package-lock.json` | `catpm.lock` |

语义差异（如实记录）：catpm 的 `add` 同时写清单并安装（npm 语义）；pip 的 `install` 对应 catpm 的 `install`。catpm 没有全局安装、没有虚拟环境概念——依赖永远装在项目内 `deps/`。
