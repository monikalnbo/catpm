# catpm — 用 CatBase 写的依赖包管理器（pip/npm 式语义 + 四层协议）

catpm 是一个用 **CatBase v0.1.8** 语言编写、由本机 `catcc 0.1.8`（Zig 0.14.1 后端）编译为原生 ELF 二进制的依赖包管理器：版本说明符、lock 文件、打包发布、本地/远程两种源、sha256 校验、下载缓存，一应俱全——全部用一门新语言的不到 1000 行源码实现。

> 协议规范独立成文档：**[PROTOCOL.md](PROTOCOL.md)**（清单层 / 解析层 / 封装层 / 源层，四层）。
> 本仓库自身就是一个可用的远程源：`registry/` 目录 + raw URL（见下文「把本仓库当源用」）。

---

## 1. 这是什么

| | |
|---|---|
| 语言 | CatBase v0.1.8（本机验证包；`catcc 0.1.8` + Zig 0.14.1 后端） |
| PM 源码 | `catpm/src2/catpm.cat`（入口，~700 行）+ `util.catc` + `ver.catc`（版本引擎） |
| 二进制 | `catpm/catpm2`，226,840 B，MIT 许可 |
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
export CATPM_REGISTRY=$PWD/registry      # 本地目录源；或 https://…/registry URL 源

catpm init                        # 创建 catpm.json
catpm add mathx                   # 最新版
catpm add 'mathx@1.2.3'           # 精确版本（同 pip 的 ==、npm 的 @1.2.3）
catpm add 'mathx@^1.2.0'          # 范围（同 npm caret；也支持 ~ >= > < <=）
catpm install                     # 按 catpm.json 全装（同 npm install / pip install -r）
catpm lock                        # 只解析 + 写锁，不装（同 npm i --package-lock-only）
catpm list                        # 列出已装（同 pip list / npm ls）
catpm remove mathx                # 移除 + 清孤儿传递依赖
catpm pack                        # 打包当前目录为 dist/<name>-<ver>.cpkg
catpm publish registry/           # 发布到本地源（自动维护 index.json）
```

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
| 指定源 | `-i <url>` | `--registry` | `CATPM_REGISTRY=<dir\|URL>` |
| 锁文件 | （无标准） | package-lock.json | `catpm.lock` |

**说明符子集**（实测支持的）：`1.2.3`、`^1.2.3`（0 主版本锁次版本，同 npm）、`~1.2.3`、`>=` `>` `<` `<=`、`latest`。不支持 `*`/`1.x`/`||`/逗号列表/`~=`/预发布——完整表见 PROTOCOL.md §2.2，不虚构。

## 5. 把本仓库当远程源用

```bash
export CATPM_REGISTRY=https://raw.githubusercontent.com/monikalnbo/catpm/main/registry
catpm add mathx        # 真实 HTTPS 下载 + sha256 校验 + 缓存
```

发布自己的包：`catpm pack` → `catpm publish registry/` → `git push`（三步，见 `scripts/publish-remote.md`）。

## 6. 仓库布局

```
catpm/src2/          PM 源码（catpm.cat + ver.catc + util.catc + test_ver.cat）
catpm/catpm2         编译好的 x86_64 Linux 二进制
registry/            远程源内容（index.json + .cpkg）——本仓库即源
pkgsrc/              示例包源（stringx / mathx 0.2.0+0.3.0 / fmtx，含传递与钻石依赖）
demo/                v0.1 演示项目；demo2/ 为 v0.2（说明符 + 远程源）
logs/build.log       catpm 构建记录（真实 catcc 命令、体积、耗时）
logs/run.log         端到端演示记录（init→add→lock→编译→运行→remove）
logs/syntax-probe.log CatBase v0.1.8 语法/标准库探针（含失败案例）
scripts/e2e.sh       一键复现 build.log + run.log
PROTOCOL.md          四层协议规范
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
bash scripts/e2e.sh        # 重建 catpm 二进制 + 从零重演 demo → logs/
bash probe/run_probes.sh   # 语法探针套件 → logs/syntax-probe.log
```

## 9. 许可

MIT（见 [LICENSE](LICENSE)）。`registry/` 里的示例包同为 MIT。
