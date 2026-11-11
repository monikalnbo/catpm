# mathx 0.5.0

完整数学库（纯 CatBase 0.1.8，无外部依赖除 stringx）。
所有函数逐个断言测试通过（169 断言，logs/mathx-build.log）。

## 函数清单（62 个公开函数 + 3 常量）

### 基础（int/float）
| 函数 | 说明 |
|---|---|
| abs_int(x) / abs_float(x) | 绝对值 |
| sign_int(x) / sign_float(x) | 符号（-1/0/1） |
| clamp_int(x,lo,hi) / clamp_float | 区间夹取 |
| max_int(a,b) / min_int(a,b) / max_float / min_float | 两值取大/小 |
| max_of_list(xs) / min_of_list(xs) | 列表取大/小 |
| floor_float(x) / ceil_float(x) | 下取整/上取整（负数正确） |
| round_half_away(x) | 四舍五入（半值远离零，实测 round(-2.5)=-3） |

### 数论
| 函数 | 说明 |
|---|---|
| gcd(a,b) / lcm(a,b) | 辗转相除（0.4.0 兼容，现接受负数） |
| is_prime(n) | 试除判定（6k±1 优化） |
| next_prime(n) | 严格大于 n 的最小素数 |
| sieve(n) | 埃氏筛，全部 ≤n 素数 |
| prime_factors(n) | 质因数分解（含重复，升序） |
| distinct_primes(n) | 去重质因数 |
| count_divisors(n) | 因数个数 |
| is_perfect(n) | 完全数判定（6/28/496…） |
| totient(n) | 欧拉函数 |
| collatz_steps(n) | Collatz 步数（0.4.0 兼容） |

### 幂与根
| 函数 | 说明 |
|---|---|
| power(b,e) | 快速幂（平方取余法，0.4.0 兼容语义） |
| mod_pow(b,e,m) | 模幂（m ≤ 3037000499 时中间值安全） |
| isqrt(n) | 整数平方根（牛顿法；n<0 返回 -1） |
| sqrt_float(x) | 浮点平方根（牛顿迭代，无内建 sqrt） |
| cbrt_float(x) | 立方根（支持负数） |
| hypot(a,b) | √(a²+b²) |

### 组合数学
| 函数 | 说明 |
|---|---| 
| factorial(n) | 阶乘（n<0 返回 -1） |
| perm(n,k) / comb(n,k) | 排列数/组合数（精确整数） |
| fib(n) | 斐波那契（迭代；n≤0 → 0） |

### 统计
| 函数 | 说明 |
|---|---|
| sum_list / mean / median | 求和/均值/中位数（偶数取中间均值） |
| variance / variance_sample | 总体/样本方差 |
| stddev | 标准差 |
| sort_floats(xs) | 插入排序（语言无内建 sort） |

### 进制转换（2–36）
| 函数 | 说明 |
|---|---|
| to_base(n,base) | 整数转字符串（负数带 -，数字 0-9a-z） |
| from_base(s,base) | 解析（大小写均可；非法输入返回 0） |
| digit_val(c) | 单字符转数值（非法 -1） |

### 三角/对数（级数+区间归约，f64 精度 ~1e-9 以内）
| 函数 | 说明 |
|---|---|
| sin / cos / tan | sin 泰勒级数+周期归约；cos=sin(x+π/2) |
| atan | 三段归约（>1 取倒数、>1/√3 用 π/6 恒等式）后泰勒 |
| exp | 归约到 |r|≤ln2/2 后泰勒，再乘 2^k |
| ln | 归约到 f∈[1,2) 后 atanh 级数 |
| log10 / log2 | ln 换底 |
| pow_float(b,e) | b>0 用 exp·ln；b<0 仅整数 e |
| deg2rad / rad2deg | 角度弧度互转 |

### 常量
MATHX_VERSION、MATHX3（"yes"，0.4.0 兼容）、PI、E

### 0.4.0 兼容性
原 7 个公开函数 gcd/lcm/is_prime/fib/loud_double/power/collatz_steps 全部保留，语义不变（gcd/lcm 额外接受负数入参）。loud_double 仍依赖 stringx。

## 用法
```
import ./deps/mathx/index.catc as mathx
# mathx.fib(10) -> 55
# mathx.comb(52, 5) -> 2598960
# mathx.sin(mathx.PI / 6.0) -> 0.5
# mathx.to_base(255, 16) -> "ff"
```

## 明确不做（如实记录）
- 位运算类（catbase v0.1.8 无位运算符）
- 复数、矩阵（未实现，未测试）
- 双曲函数 asin/acos（弧度域实现的精度边界未逐点验证，暂不虚报）
