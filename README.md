# catpm — 用 CatBase 写的依赖包管理器（pip/npm 式语义 + apt 式源清单 + 四层协议）

catpm 是一个用 **CatBase v0.1.8** 语言编写、由本机 `catcc 0.1.8`（Zig 0.14.1 后端）编译为原生 ELF 二进制的依赖包管理器：版本说明符、lock 文件、打包发布、本地/远程多源、sha256 校验、下载缓存、apt sources.list 式的 `package.where` 源清单，一应俱全——全部用一门新语言实现。

> 协议规范独立成文档：**[PROTOCOL.md](PROTOCOL.md)**（清单层 / 解析层 / 封装层 / 源层，四层；源层含 package.where 规范 §4.0）。
> 本仓库自身就是一个可用的远程源：`registry/` 目录 + raw URL（见下文「把本仓库当源用」）。

---

## 1. 这是什么

| | |
|---|---|
| 语言 | CatBase v0.1.8（本机验证包；`catcc 0.1.8` + Zig 0.14.1 后端） |
| PM 源码 | `catpm/src2/catpm.cat`（入口，v0.3）+ `util.catc` + `ver.catc`（版本引擎） |
| 二进制 | `catpm/catpm3`（v0.3.0，253,840 B）；`catpm/catpm2`（v0.2.0，226,840 B），MIT 许可 |
| 源定义 | `package.where`（apt sources.list 式多源清单，与 PM 同仓库默认生效） |
| 源码形态 | 源码内置（vendoring）：包以源码安装进 `deps/`，catcc 单入口编译时传递展开 import |

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

前置：Linux + CatBase v0.1.8（`bin/catcc`、`conf/`、`runtime/`）+ 系统 `tar`/`sha256sum`/`curl`（Linux 发行版均自带）。

```bash
# 从源码构建（catcc 编译 catpm 自身）
cd catbase && ./bin/catcc ../catpm/src2/catpm.cat -o ../catpm/catpm2
```

不想构建时也可直接使用仓库里已编译的 `catpm/catpm2`（x86_64 Linux ELF）。

## 3. 用法

```bash
# 源由 package.where 定义（与 catpm 同仓库/同目录默认生效；无需环境变量）：
#   catpm sources                 # 查看当前源清单 + 实测可达性
catpm init                        # 创建 catpm.json
catpm add mathx                   # 最新版（多源时版本候选=并集取最高）
catpm add 'mathx@1.2.3'           # 精确版本（同 pip 的 ==、npm 的 @1.2.3）
catpm add 'mathx@^1.2.0'          # 范围（同 npm caret；也支持 ~ >= > < <=）
catpm install                     # 按 catpm.json 全装（同 npm install / pip install -r）
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
| 范围版本 | `pip install pkg>=1,<2` | `npm i pkg@^1.2.3` | `catpm add pkg@^1.2.3`（`~` `>=` `<` `>` `<=` 同理） |
| 按清单全装 | `pip install -r requirements.txt` | `npm install` | `catpm install` |
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

**说明符子集**（实测支持的）：`1.2.3`、`^1.2.3`（0 主版本锁次版本，同 npm）、`~1.2.3`、`>=` `>` `<` `<=`、`latest`。不支持 `*`/`1.x`/`||`/逗号列表/`~=`/预发布——完整表见 PROTOCOL.md §2.2，不虚构。

## 5. 把本仓库当远程源用

默认 `package.where`（与 catpm 同仓库）已指向本仓库的 GitHub raw 源，开箱即用：

```bash
catpm add mathx        # 真实 HTTPS 下载 + sha256 校验 + 缓存（无需设置任何变量）
```

或临时用单源兼容模式：`CATPM_REGISTRY=https://raw.githubusercontent.com/monikalnbo/catpm/main/registry`。

发布自己的包：`catpm pack` → `catpm publish registry/` → `git push`（三步，见 `scripts/publish-remote.md`）。

## 6. 仓库布局

```
catpm/src2/          PM 源码（catpm.cat v0.3 + ver.catc + util.catc + test_ver.cat）
catpm/catpm3         编译好的 x86_64 Linux 二进制（v0.3.0；catpm2 为 v0.2.0）
catpm/package.where  默认源清单（指向本仓库 GitHub raw 源）
registry/            远程源内容（index.json + .cpkg）——本仓库即源
registry3/           v0.3 多源演示本地源（含 loganx）
registry-mirror/     v0.3 镜像源（mathx 0.4.0 独有，prio/pkg= 演示）
pkgsrc/              示例包源（stringx / mathx 0.2–0.4 / fmtx / loganx，含传递与钻石依赖）
demo/                v0.1 演示项目；demo2/ 为 v0.2；demo_where*/ 为 v0.3（package.where）
logs/build.log       catpm 构建记录（真实 catcc 命令、体积、耗时）
logs/run.log         端到端演示记录（init→add→lock→编译→运行→remove）
logs/build3.log      v0.3 构建 + 单测记录
logs/where3.log      v0.3 package.where 六场景实测（默认源/改写切换/多源/回退/错误/编译运行）
logs/syntax-probe.log CatBase v0.1.8 语法/标准库探针（含失败案例）
scripts/e2e.sh       一键复现 build.log + run.log
scripts/e2e_v2.sh    一键复现 v0.2 全生态
scripts/e2e_v3.sh    一键复现 v0.3 package.where 六场景
PROTOCOL.md          四层协议规范（§4.0 package.where）
LICENSE              MIT
```

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
bash probe/run_probes.sh   # 语法探针套件 → logs/syntax-probe.log
```

## 9. 许可

MIT（见 [LICENSE](LICENSE)）。`registry/` 里的示例包同为 MIT。
