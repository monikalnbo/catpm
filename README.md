# catpm — 用 CatBase 写的依赖包管理器（pip/npm 式语义 + apt 式源清单 + 四层协议）

catpm 是一个用 **CatBase v0.1.8** 语言编写、由本机 `catcc 0.1.8`（Zig 0.14.1 后端）编译为原生 ELF 二进制的依赖包管理器：版本说明符、lock 文件、打包发布、本地/远程多源、sha256 校验、下载缓存、apt sources.list 式的 `package.where` 源清单、**预编译二进制包（v0.5.3）**，一应俱全——全部用一门新语言实现。

> 协议规范独立成文档：**[PROTOCOL.md](PROTOCOL.md)**（清单层 / 解析层 / 封装层 / 源层，四层；源层含 package.where 规范 §4.0）。
> **v0.4 起仓库分离**：包集中在专用仓库 **[monikalnbo/catpm-registry](https://github.com/monikalnbo/catpm-registry)**；本仓库只保留 PM 本体（源码、二进制、package.where、文档、安装脚本、日志）。

---

## 1. 这是什么

| | |
|---|---|
| 语言 | CatBase v0.1.8（本机验证包；`catcc 0.1.8` + Zig 0.14.1 后端） |
| PM 源码 | `catpm/src2/catpm.cat`（入口，v0.5.3）+ `util.catc` + `ver.catc`（版本引擎） |
| 二进制 | `catpm/catpm53`（v0.5.3，283,328 B）；`catpm52`/`catpm5`/`catpm4`/`catpm3`/`catpm2` 为旧版，MIT 许可 |
| 源定义 | `package.where`（apt sources.list 式多源清单，默认指向 catpm-registry 仓库） |
| 源码形态 | 源码内置（vendoring）：包以源码安装进 `deps/`，catcc 单入口编译时传递展开 import |
| 自更新 | `catpm self-update`（对标 `apt install apt`）——catpm 本体也是 registry 里的一个包 |

**端到端已验证的完整链路**（真实命令与输出见 `logs/build.log`、`logs/run.log`）：

```
catpm pack                    打包 mathx -> dist/mathx-0.2.0.cpkg (tar.gz + sha256)
catpm publish registry/       发布 .cpkg + 更新 index.json
git push                      （GitHub 仓库 = 免运维的远程源）
CATPM_REGISTRY=<raw-url> \
  catpm add 'mathx@^0.2.0'    远程解析：下载 index.json -> 锁 0.2.0 -> 下载 .cpkg
                              -> sha256 校验 -> 解包 deps/
catcc main.cat -o app && ./app   引用直接+传递依赖，运行正确
```

## 2. 安装

### 一键安装（sh / bash / zsh）

前置只有 `curl` + `tar`（Linux 发行版均自带）。装到 `~/.local/bin`（或 `CATPM_INSTALL_DIR=...` 覆盖）：

```sh
curl -fsSL https://raw.githubusercontent.com/monikalnbo/catpm/main/install.sh | sh
```

`install.sh` 是纯 POSIX sh（同一份脚本在 sh / bash / zsh 下真实跑过，见 `logs/run4.log` [5/6]）：下载 `catpm5` 二进制与 `package.where`（默认源：catpm-registry 仓库）放到 `~/.local/bin`，`package.where` 与二进制同目录——catpm 找源时优先读二进制旁边的清单，开箱即用。装完即可 `catpm self-update` 保持新版（v0.5 起支持）。

### fish

```fish
curl -fsSL https://raw.githubusercontent.com/monikalnbo/catpm/main/install.fish | source
```

### PATH 设置（装完按所用 shell 加一行）

```bash
# bash (~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"

# zsh (~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"

# fish (~/.config/fish/config.fish)
fish_add_path ~/.local/bin
```

然后 `catpm --version` 验证（应输出 `catpm 0.5.3 (for CatBase 0.1.8)`）。

### 从源码构建

需要 CatBase v0.1.8（`bin/catcc`、`conf/`、`runtime/`）：

```bash
cd catbase && ./bin/catcc ../catpm/src2/catpm.cat -o ../catpm/catpm53  # ~12 s
```

不想构建时直接用仓库里已编译的 `catpm/catpm53`（x86_64 Linux ELF）。

> 说明：安装脚本只是「下载 + 放对位置」，catpm 自身运行还依赖系统 `tar`/`sha256sum`/`curl`（包管理操作用）；`catpm --version`、`catpm sources` 等纯命令无这些也能跑。

## 3. 用法

```bash
# 源由 package.where 定义（与 catpm 同仓库/同目录默认生效；无需环境变量）：
#   catpm sources                 # 查看当前源清单 + 实测可达性
catpm self-update                 # 更新 catpm 自身（同 apt install apt / pip install -U pip）
catpm self-update @0.4.0          # 装指定版本（可降级；说明符语法同 add）
catpm init                        # 创建 catpm.json
catpm add mathx                   # 最新版（多源时版本候选=并集取最高）
catpm add 'mathx@1.2.3'           # 精确版本（同 pip 的 ==、npm 的 @1.2.3）
catpm add 'mathx@^1.2.0'          # 范围（同 npm caret；也支持 ~ >= > < <=）
catpm add 'mathx@>=0.2.0,<0.4.0'  # 逗号 AND 列表（v0.4：每项都须满足）
catpm add 'mathx@*'               # 星号 = 任意版本取最高（v0.4，latest 同义词）
catpm install                     # lock 完整时 lock-exact 精确还原（同 npm ci）；
                                  #   否则按 catpm.json 重解析全装（同 npm install）
catpm update                      # 重解析 + 重写 lock + 安装（同 npm update）（v0.4）
catpm outdated                    # current vs newest，标 -> upgradable（v0.4）
catpm lock                        # 只解析 + 写锁，不装（同 npm i --package-lock-only）
catpm list                        # 列出已装（同 pip list / npm ls）
catpm remove mathx                # 移除 + 清孤儿传递依赖
catpm pack                        # 打包当前目录为 dist/<name>-<ver>.cpkg
catpm publish registry/           # 发布到本地源（自动维护 index.json）
catpm sources                     # 列出源清单（prio/类型/钉定/可达性）

# 兼容：无 package.where 时回退 CATPM_REGISTRY=<dir|URL> 单源（v0.2 行为）
```

### package.where — 源清单文件（对标 apt /etc/apt/sources.list）

包从哪里拉，由这个**用户可改写的文本文件**决定，改源不需要改任何代码。查找顺序：`CATPM_WHERE` → `./package.where` → **catpm 二进制所在目录**（即与 PM 同仓库，默认形态）→ 回退 `CATPM_REGISTRY`/`./registry`。

```
# catpm source list v1（apt sources.list 式；# 注释、空行忽略）
# <dir-or-URL> [prio=N] [pkg=name1,name2]
/abs/path/registry3                                       prio=10
./my-local-registry                                        prio=5
https://raw.githubusercontent.com/monikalnbo/catpm/main/registry   prio=1
/mirror-registry                                           prio=20  pkg=mathx
```

- **`prio=N`**：优先级，越大越优先。多源都有同一包时按 prio 从高到低尝试下载，失败自动降级（实测：见 `logs/where3.log` [4/6]）
- **`pkg=a,b`**：源钉定——该源只参与列表内包名的解析（apt pin 的简化版；实测 `mathx@0.4.0` 只从 mirror 拉，`logs/where3.log` [3/6]）
- **版本候选 = 多源并集**：`registry3` 的 mathx 0.2/0.3 + mirror 的 0.4 并集后 `latest` 解析为 0.4.0
- 单个源不可达 → 警告跳过继续用其余源；全部不可达 / 格式错误（带行号）→ exit 1
- 格式与全部规则详见 [PROTOCOL.md §4.0](PROTOCOL.md#40-源定义文件-packagewhere-apt-sourceslist-式)

应用代码引用安装好的包（相对 import + 与包名一致的别名——catcc 的硬约束，见 PROTOCOL.md §3.3）：

```catbase
import ./deps/mathx/index.catc as mathx
import ./deps/stringx/index.catc as stringx

def main() {
    print(mathx.fib(10))              # 直接依赖
    print(mathx.loud_double(21))      # 传递依赖 stringx 在包内被调用
}
```

## 4. 与 pip / npm 的命令对照

| 动作 | pip | npm | catpm |
|---|---|---|---|
| 初始化 | — | `npm init` | `catpm init` |
| 装一个包 | `pip install pkg` | `npm install pkg` | `catpm add pkg` |
| 指定版本 | `pip install pkg==1.2.3` | `npm i pkg@1.2.3` | `catpm add pkg@1.2.3` |
| 范围版本 | `pip install pkg>=1,<2` | `npm i pkg@^1.2.3` | `catpm add pkg@^1.2.3`（`~` `>=` `<` `>` `<=`、逗号 AND、`*` 同理） |
| 按清单全装 | `pip install -r requirements.txt` | `npm install` | `catpm install`（lock 完整时 lock-exact） |
| 按锁精确还原 | （无） | `npm ci` | `catpm install`（lock 完整自动走） |
| 升级（语义内） | `pip install -U pkg` | `npm update` | `catpm update` |
| 查过期 | `pip list -o` | `npm outdated` | `catpm outdated` |
| 只生成锁 | — | `npm i --package-lock-only` | `catpm lock` |
| 列出已装 | `pip list` | `npm ls` | `catpm list` |
| 移除 | `pip uninstall pkg` | `npm uninstall pkg` | `catpm remove pkg` |
| 打包 | `python -m build` | `npm pack` | `catpm pack` |
| 发布 | `twine upload` | `npm publish` | `catpm publish <dir>`（远程发布 = git push，见 scripts/publish-remote.md） |
| 指定源 | `-i <url>` | `--registry` | `package.where`（兼容 `CATPM_REGISTRY`） |
| 查看源 | — | `npm config get registry` | `catpm sources` |
| 锁文件 | （无标准） | package-lock.json | `catpm.lock` |

**与 apt 的对照**（源定义机制）：

| 概念 | apt | catpm |
|---|---|---|
| 源清单文件 | `/etc/apt/sources.list`（+ sources.list.d/） | **`package.where`**（与 PM 同仓库/同目录默认生效） |
| 一行一源 | `deb http://…/ stable main` | `/path/dir` 或 `https://…/registry` |
| 优先级/pin | `/etc/apt/preferences`（pin-priority） | `prio=N`（行内选项） |
| 钉定到源 | `Package: foo` + `Pin: origin …` | `pkg=foo,bar`（行内选项） |
| 列出源 | `cat /etc/apt/sources.list` | `catpm sources`（实测可达性） |
| 刷新索引 | `apt update` | 每次命令实时拉各源 index.json |

**说明符子集**（实测支持的）：`1.2.3`、`^1.2.3`（0 主版本锁次版本，同 npm）、`~1.2.3`、`>=` `>` `<` `<=`、**逗号 AND 列表** `>=0.2.0,<0.4.0`（v0.4）、**`*`**（v0.4，= latest）、`latest`。不支持 `1.x`/`||`/`~=`/预发布（原因见 PROTOCOL.md §2.2）——完整表见 PROTOCOL.md §2.2，不虚构。

## 5. 仓库分离：包都在 catpm-registry（v0.4）

**[github.com/monikalnbo/catpm-registry](https://github.com/monikalnbo/catpm-registry)**（PUBLIC）是包仓库：`index.json` + `<name>/<name>-<ver>.cpkg` 放仓库根，当前 7 包 11 版本：

| 包 | 版本 | 用途 | 依赖 |
|---|---|---|---|
| mathx | 0.2.0 / 0.3.0 / 0.4.0 | 算术（fib、gcd、完美数等） | stringx ^0.3.0 |
| stringx | 0.3.0 | 字符串工具（shout、capitalize…） | — |
| fmtx | 0.1.0 | 格式化输出 | stringx ^0.3.0 |
| loganx | 0.1.0 | 带时间戳日志 | — |
| **timex** | 0.1.0 | **v0.4 新增**：真实时间（`iso8601()`/`epoch()`/`stamp()`/`days_between()`，经 `exec(date)`） | stringx ^0.3.0 |
| **randx** | 0.1.0 | **v0.4 新增**：种子化确定性 PRNG（`seed`/`between`/`below`/`pick`/`die6`；LCG + 乘法混叠，无位运算可用故纯 `+ * %` 实现） | timex ^0.1.0 |
| **hellox** | 1.0.0 | **v0.5.3 新增**：首个预编译参考包（含 `bin/hellox` linux-x86_64 ELF） | — |
| **catpm** | 0.4.0 / 0.5.0 / 0.5.1 / 0.5.2 / 0.5.3 | **v0.5 新增**：PM 本体自举（包内含预编译 `bin/catpm` + 全部源码，供 `self-update`） | — |

本仓库（catpm）只保留 PM 本体：源码、二进制、`package.where`、README/PROTOCOL、安装脚本、日志。**v0.3 及以前放在本仓库的 `registry/`、`registry3/`、`registry-mirror/` 已整体删除（非归档）**——包体与索引全部迁移到 catpm-registry，raw 可达性实测 8/8 个 .cpkg + index.json 全 200（`logs/run4.log` [6/6]）。

默认 `package.where` 已指向新仓库，开箱即用：

```bash
catpm add mathx        # 真实 HTTPS 下载 + sha256 校验 + 缓存（无需设置任何变量）
```

或临时单源兼容模式：`CATPM_REGISTRY=https://raw.githubusercontent.com/monikalnbo/catpm-registry/main`。

发布自己的包：`catpm pack` → `catpm publish <catpm-registry 检出目录>` → `git push`（catpm-registry 的 .gitignore 不能含 `*.cpkg`，见 PROTOCOL.md §4.4）。

## 5b. 自更新：catpm self-update（v0.5）

对标 `pip install --upgrade pip` / `apt install apt`：catpm 本体作为**普通包**挂在 catpm-registry（名字就叫 `catpm`，包内含预编译 `bin/catpm` + 全部源码），自更新完全复用现有 package.where 多源机制——`apt 从自己的源里装 apt` 的模式：

```bash
catpm self-update            # 查源里的最新版并升级（0.5.0 -> 0.5.1 实测过）
catpm self-update @0.4.0     # 装指定版本（可降级；说明符同 add 语法）
```

**为什么不是 `catpm update catpm`**：`update` 已是「重解析项目 manifest 依赖」的语义（npm update 语义），复用会与项目操作混淆；apt 用 `apt install apt`（install 复用）、pip 用 `pip install -U pip`——catpm 的 `add`/`install` 只作用于项目 `deps/`，不碰二进制，故独立 `self-update` 子命令最清晰。

**原子性与失败回退**（全部实测，`logs/selfupdate5.log`）：

1. 多源解析 catpm 包版本（package.where 机制，支持 prio/pkg= 钉定）
2. 下载 .cpkg 到缓存 → **sha256 门**：不符即中止，二进制零接触
3. 解出候选二进制放 `<bindir>/catpm.new`（绝不直接覆盖活文件）→ **冒烟测试**：`catpm.new --version` 必须报出目标版本号，报不出（坏包/坏二进制）即删候选中止
4. 全部通过才 `mv`（同目录 rename，内核原子）替换活二进制

实测失败场景：源不可达（exit 1，旧版照常）、sha256 篡改（exit 1，"binary NOT touched"）、坏二进制候选（exit 1，冒烟测试拦下）——三种情况旧版均可继续正常装包。已升级 0.5.1 后再跑提示 already up to date。HTTPS 真源实测：GitHub catpm-registry 0.5.0 → 0.5.1 一次成功，升级后的二进制继续正常 add randx。v0.5.2 全链路再测（`logs/run6.log`）：0.5.0 → @0.5.1 → 0.5.2（默认 latest）→ @0.5.1（显式降级）四步全过、无 `.new` 残留；期间还意外实证了 sha256 门——registry 补推最终版 cpkg 后 raw CDN 短暂新包配旧 index，self-update 按设计拦截（MISMATCH, exit 1, 二进制未动），CDN 一致后重跑即升级成功。

注：catpm 0.4.0 及更早版本没有 self-update 子命令（如同远古 apt 需要先 apt-get 装新 apt），从那些版本升级请用 `curl | sh` 重装或手动放二进制。

## 5c. 发版规则（v0.5.1 起长期生效）

1. **版本号固定 +0.0.1 递增**：每次发版一律在上一版基础上 `+0.0.1`（0.5.0 → 0.5.1 → 0.5.2 → …），不按功能大小跳 0.1.0。
2. **先 diff 后发版**：每个新版本发布前，先对「上一版 ↔ 新版」源码做真实 diff（`diff -ruN <上一版快照> <新版快照>`，或 git 两个标签间 diff），diff 完整落盘到仓库 **`diffs/`** 目录，文件名含两端版本号：`diffs/v<旧>..v<新>.diff`（如 `diffs/v0.5.0..v0.5.1.diff`）。核对 diff 无未预期改动后才发版，diff 文件随发版一起提交推送。
3. **补历史 diff**：本规则生效前的相邻版本对同样补齐（`diffs/` 里现有 `v0.5.0..v0.5.1.diff`，其中 0.5.1 相对 0.5.0 仅版本号一行，如实反映）。首个按新规则发布的版本是 **v0.5.2**（`diffs/v0.5.1..v0.5.2.diff`，上一版快照取自 0.5.1 .cpkg 内源码——发布包是唯一可信快照源）。
4. **registry 一次到位**：0.5.2 发布过程中实测到——registry 推送两次（中间版 cpkg + 最终版 cpkg）会让 raw CDN 在几分钟窗口内新 cpkg 配旧 index.json，self-update 的 sha256 门如实拦截（这正是它存在的意义）。规则：**源码定稿 → 打包 → 推送，只推一次**；误推中间版后立即补推最终版并等 CDN 一致再做 self-update 实测。

## 5d. 预编译二进制包（v0.5.3）

对标 apt 直接下 deb：包作者把编好的二进制放进 `bin/<name>`，`catpm pack` 打进 .cpkg，`publish` 在 index.json 登记平台指纹，装包方在干净目录（**无 catcc**）就能装出可直接执行的二进制。

**包形态**：源码包 = `index.catc + catpm.json`；预编译包 = 再加 `bin/<name>`（并在 catpm.json 的 `files` 里列出）。hellox 1.0.0 是参考实现（linux-x86_64 ELF，21,344 B）。

**index.json 平台标记**（字段可选，向后兼容）：

```json
"hellox": { "1.0.0": {
    "path": "hellox/hellox-1.0.0.cpkg",
    "sha256": "<整个 .cpkg 的哈希>",
    "deps": {},
    "bin": { "path": "bin/hellox", "os": "linux", "arch": "x86_64", "sha256": "<内层二进制哈希>" }
} }
```

- **旧 catpm 读新索引**：`bin` 是未知字段，直接忽略，照常装（实测 0.5.2 装 hellox 成功，tar 保留 exec 位，二进制直接可跑）
- **新 catpm 读旧索引**：无 `bin` 字段即纯源码路径，行为与 0.5.2 完全一致（实测剥掉字段后照常装）

**安装时对 bin/<name> 做的三件事**（实测，`logs/run7.log`）：

1. `chmod 0755` 恢复执行位
2. **格式/架构校验**：ELF magic（`\x7fELF`，经 `ord()` 逐字节判定——CatBase 无 `\xNN` 转义且整型下标在二进制串上返回空，只有切片安全）+ e_machine（offset 18 LE u16：62=x86_64、183=aarch64…）与 `uname -m` 匹配；非 ELF 则必须是 `#!` shebang 脚本。**为什么拒绝「只是带执行位的文本」**：sh 的 ENOEXEC 回退会把它当脚本「跑」出输出，而 CatBase `exec()` 拿不到子进程退出码——「有输出」不能证明「能跑」，只能用确定性判据
3. 冒烟：`--version`/`--help` 必须有输出

校验失败（坏格式/错架构）**不中止安装**——源码部分照常落盘，二进制打上 `check FAILED` 标记由使用者定夺；整个 .cpkg 的 sha256 门（篡改即 exit 1、零接触）不变。

**设计边界（如实记录）**：为什么不做 compile-on-install——CatBase 没有稳定 ABI 与链接器，唯一的消费模型是「单入口源码、import 在编译期展开」，所以预编译二进制只服务独立工具（catpm 本体、hellox），可 import 的库（mathx 等）保持源码 vendoring。

**语言栏说明**：GitHub 语言栏只显示 [github/linguist](https://github.com/github/linguist) 已注册语言；CatBase 未注册，注册需上游 PR 且有真实使用量门槛（CONTRIBUTING.md 要求约 2000 文件/扩展，实测全 GitHub 仅 2 个 .catc 文件）——做不到就是做不到。本仓库用 `.gitattributes` 把 `.catc/.cat` 映射到最接近的已注册语言 Python（`linguist-language=Python`），脚本/日志/二进制标 vendored/generated；推送后实测语言栏从 `Shell 100%` 变为 `Python 81,206 B / Shell 5,340 B`。

## 6. 仓库布局

```
catpm/src2/          PM 源码（catpm.cat v0.5.3 + ver.catc + util.catc + test_ver.cat 62 断言）
catpm/catpm53        编译好的 x86_64 Linux 二进制（v0.5.3，283,328 B；catpm52/catpm5/catpm4/catpm3/catpm2 为旧版）
diffs/               发版前源码 diff（v0.5.0..v0.5.1、v0.5.1..v0.5.2、v0.5.2..v0.5.3；发版规则见 §5c）
catpm/package.where  默认源清单（指向 catpm-registry 仓库 GitHub raw）
install.sh           POSIX sh 安装器（sh/bash/zsh 通用，curl | sh 一键装）
install.fish         fish 原生安装器（curl | source）
.gitattributes       Linguist 映射（.catc/.cat→Python；脚本/日志标 vendored/generated，见 §5d）
demo/                v0.1 演示项目；demo2/ 为 v0.2；demo_where*/ 为 v0.3（package.where）
logs/build.log       catpm 构建记录（真实 catcc 命令、体积、耗时）
logs/run.log         端到端演示记录（init→add→lock→编译→运行→remove）
logs/build3.log      v0.3 构建 + 单测记录
logs/where3.log      v0.3 package.where 六场景实测（默认源/改写切换/多源/回退/错误/编译运行）
logs/build4.log      v0.4 构建 + 44 断言单测 + 新包行为探针
logs/run4.log        v0.4 六段实测：命令扫描/版本控制/仓库分离/安装器/raw 可达性
logs/build5.log      v0.5 构建记录（44 断言 + catpm5 编译 + 0.5.1 构建 + registry 状态）
logs/selfupdate5.log v0.5 自更新全场景实测：升级/幂等/降级/不可满足/三失败回退/live HTTPS
logs/build6.log      v0.5.2 构建记录（62 断言 + catpm52 编译 + 打包发布）
logs/run6.log        v0.5.2 打磨实测：三处修复复现验证 + self-update 全链路（0.5.0→0.5.1→0.5.2→降级）+ raw 验证
logs/build7.log      v0.5.3 构建记录（62 断言 + catpm53 编译 + hellox 打包发布含 bin 指纹）
logs/run7.log        v0.5.3 预编译包八段实测：安装链路/篡改拦截/坏格式拒绝/错架构拒绝/新旧互兼容/源码回归/self-update+HTTPS
logs/syntax-probe.log CatBase v0.1.8 语法/标准库探针（含失败案例）
scripts/e2e.sh       一键复现 build.log + run.log
scripts/e2e_v2.sh    一键复现 v0.2 全生态
scripts/e2e_v3.sh    一键复现 v0.3 package.where 六场景
scripts/e2e_v4.sh    一键复现 v0.4 全部六段（含安装器与 raw 可达性）
scripts/e2e_v5.sh    一键复现 v0.5 自更新全场景（build5.log + selfupdate5.log）
scripts/e2e_v6.sh    一键复现 v0.5.2 打磨发版（build6.log + run6.log）
scripts/e2e_v7.sh    一键复现 v0.5.3 预编译包发版（build7.log + run7.log）
PROTOCOL.md          四层协议规范（§4.0 package.where；§4.4 catpm-registry）
LICENSE              MIT
```

（v0.3 及以前的 `registry/`、`registry3/`、`registry-mirror/`、`pkgsrc/` 已从本仓库删除——包全部迁至 [catpm-registry](https://github.com/monikalnbo/catpm-registry)；包源码在该仓库各包目录的 .cpkg 归档内。）

## 7. CatBase v0.1.8 陷阱记录（写这个 PM 时踩过的）

全部来自真实编译/运行（`logs/syntax-probe.log`）：

**可用且被大量使用**：切片 `s[a:b]`、`startswith`/`endswith`/`find`/`rfind`/`split`/`replace`、文件 IO、`mkdir`/`listdir`、`json_dumps`/`json_loads`、`getenv`/`exec`/`exit`、dict `.put/.get/.contains/.remove/.keys`。

**绕过的坑**：

| 坑 | 绕法 |
|---|---|
| 内置 `http_get` 的 `https://` 是明文 TCP 连 443（无 TLS，实测 GitHub 拒收） | 远程下载走 `exec("curl -sS -f -L …")`；协议只要求 GET+sha256，不绑死实现 |
| 无 `sorted()`、字符串间 `<`/`>` 不支持 | 手写插入排序 + 逐字符 `ord()` 比较（`util.str_greater`） |
| 无 rmdir；`delete_file` 对目录是 no-op | `sh_die("rm -rf …")`（pack/unpack/prune 统一走它） |
| `exec()` 本身永远 exit 0，拿不到子进程退出码 | 让 sh 脚本失败时把 rc 写 `/tmp/catpm_rc`，父进程查该文件（`sh_die`） |
| 字符串字面量上直接调方法部分情况解析失败（如 `"foo".endswith()`） | 先赋给变量再调用 |
| dict **参数**上用 `k in d` 触发 Zig `@hasField` 编译错误 | 全部用 `.contains(k)` |
| 函数名遮蔽 Zig 原生标识符（`f16`/`u1`/`as` 是保留字） | 避开这些名字 |
| 同一文件两个别名导入 → 编译失败（catcc 硬约束） | 协议规定别名=包名（PROTOCOL.md §3.3） |
| `int("junk")` 不报错静默得 0 | 版本串先逐字符验数字再 `int()`（`ver.is_digit`/`vlen`） |
| 未使用的函数参数是 Zig 硬错误 | 删掉 |

**做不到的（如实记录，不虚构）**：f-string/字符串含 `\n` 转义（issue #5，两代版本同）、struct dict 字段下标赋值（issue #6）、`float("3.5")`、str 重复 `*`、内置加密哈希（故用 `sha256sum`）、一次编译多个入口源文件（故 vendoring）。

## 8. 复现

```bash
bash scripts/e2e.sh        # v0.1 全流程 → logs/build.log + run.log
bash scripts/e2e_v2.sh     # v0.2 说明符/远程源全生态 → logs/build2.log + run2.log
bash scripts/e2e_v3.sh     # v0.3 package.where 六场景 → logs/build3.log + where3.log
bash scripts/e2e_v4.sh     # v0.4 六段全测 → logs/build4.log + run4.log
bash scripts/e2e_v5.sh     # v0.5 自更新全场景 → logs/build5.log + selfupdate5.log
bash scripts/e2e_v6.sh     # v0.5.2 打磨发版 → logs/build6.log + run6.log
bash scripts/e2e_v7.sh     # v0.5.3 预编译包发版 → logs/build7.log + run7.log
bash probe/run_probes.sh   # 语法探针套件 → logs/syntax-probe.log
```

## 9. 许可

MIT（见 [LICENSE](LICENSE)）。[catpm-registry](https://github.com/monikalnbo/catpm-registry) 里的包同为 MIT。
