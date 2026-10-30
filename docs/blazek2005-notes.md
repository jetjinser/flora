# blazek2005《Computational Fluid Dynamics》翻译完成记录

Jiri Blazek《Computational Fluid Dynamics: Principles and Applications》2nd ed. (Elsevier 2005) 翻译的完成记录:统计、id 总表、原书勘误清单、术语表。翻译规范见 `docs/translation-guide.md`。

## 1. 成书统计(2026-10-10 更新)

| 项 | 数量 |
| --- | --- |
| 内容页面 | 14 + 书目录页:前置材料 `blazek2005-front`、第1–12章 `blazek2005-ch01`…`blazek2005-ch12`(附录A 内容在 ch12 页内,小节独立成页)、索引 `blazek2005-index`、书目录 `cfd` |
| 双语块 | 1661 |
| 编号公式(全部锚点跳转) | 755:(2.1)–(2.45)、(3.1)–(3.17)、(4.1)–(4.127)、(5.1)–(5.77)、(6.1)–(6.78)、(7.1)–(7.102)、(8.1)–(8.46)、(9.1)–(9.82)、(10.1)–(10.48)、(11.1)–(11.14)、(12.1)–(12.5)、(A.1)–(A.114) |
| 插图(全部从扫描页裁剪嵌入) | 127:图2.1–2.5、3.1–3.7、4.1–4.12、5.1–5.19、6.1–6.6、7.1–7.3、8.1–8.15、9.1–9.12、10.1–10.9、11.1–11.24、12.1–12.8、A.1–A.7 |
| 文献条目页 | 1067(第2章 41、第3章 247、第4章 103、第5章 75、第6章 108、第7章 161、第8章 53、第9章 109、第10章 20、第11章 123、附录A 27) |
| 正文文献引用链接 | 约 2400(第2–9章/附录A 约 2000,第10章 52、第11章 348,双语 lane 各计一半) |

表 6.1、6.2(纯数值表)用 `@verbatim` 重建;索引 403 词条按字母分组的单页中英对照(`blazek2005-idx-a…w` 为分组 id)。

## 2. id 与命名总表

| 对象 | 命名 | 例 |
| --- | --- | --- |
| 页面 | 文件名即 id | `blazek2005-ch02`、`blazek2005-ch09` |
| 小节 | `blazek2005-<章>-<节>` | `blazek2005-3-1-2` |
| 前置材料小节 | `blazek2005-front-ack` / `blazek2005-front-symbols` / `blazek2005-front-abbrev` | |
| 公式锚点 | `eq-<章>-<编号>` | `eq-4-58` |
| 文献条目 | `blazek2005-r<章>-<编号>`,章号小写(附录A 为 `ra`) | `blazek2005-r7-154`、`blazek2005-ra-3` |
| 插图资源 | `blazek2005/fig-<章>-<图>.png` | `blazek2005/fig-11-24.png` |
| 索引字母分组 | `blazek2005-idx-<字母>` | `blazek2005-idx-a` |

## 3. 原书排印疑误与译注清单

英文 lane 照录原书;以下各处已加译注(第10章起用 `@sidenote` 页边注,第3–9章为行内括号注):

| 位置 | 原书 | 说明 |
| --- | --- | --- |
| 式(7.54) | `exp(Re_T²)` 无负号 | Launder–Sharma 通行形式为 `exp(−Re_T²)`,已加行内译注 |
| 式(7.77) | 积分域印作 D,下文却写 Ω | 原书符号不一致,照录 |
| 式(10.36) | 括号不配对 | `@sidenote` 注明应为三项之和 |
| p.354 | "Cranck and Nicholson" | 通行拼法 Crank–Nicolson,`@sidenote` |
| p.367 | "Fig. 10.8," 缺右括号 | `@sidenote` |
| p.373 | "rather rate" 应为 rare | `@sidenote` |
| p.381 | 图11.10 图题 "an O-grid" 脱漏 of | `@sidenote` |
| p.392 | "which particularly suitable" 缺 is | `@sidenote` |
| p.397 | "cirumellipsoid" 应为 circumellipsoid | `@sidenote` |
| A.1 首句 | "Supposed" 应为 Supposing | `@sidenote` |
| A.5 | "This effects" 应为 affects | `@sidenote` |
| A.12 步骤1 | "the dimensions becomes" | `@sidenote` |
| 12.7 节 | "(Subsection 4.3.3 and 5.3.2." 缺右括号 | `@sidenote` |

其余轻微笔误("much worser"、"in order to to" 等)英文 lane 照录、未加注。

## 4. 重复与存疑文献(照录未改)

- 第3章 [11] 与 [116] 为同一文献(Van Leer, Lee, Roe, AIAA 91-1552),[116] 作者误印 "Roe, P."。
- 第4章 [36] 与 [42] 完全同文(Jameson, AIAA 93-3559);[9] 与 [97] 同为 Radespiel, NASA TM-101557。
- 存疑编号/人名(疑为原书之误):blazek2005-r6-50 `NASA CR-17954`(疑 179546)、blazek2005-r7-38 `Spalart, S.R.`(应为 P.R.)、blazek2005-r7-159 `2003-839`(疑 2003-0839)、blazek2005-r9-46 `Van Henson, E.`(应为 V. E. Henson)、blazek2005-r9-3 `Airfoil and Wings`(应 Airfoils)。

## 5. OCR 处理原则与代表性修正

文字层(300dpi 扫描 OCR)只作叙述底稿:公式一律对照扫描页逐条转录(常见于式 (4.46) 之后、(6.4x)、(7.3x)、(9.5x)、(A.x) 等区域,OCR 损坏率接近 100%);正文讹误仅作字形级最小修正。代表性修正约 150 处,典型模式:

- 人名:`Wakers`→Walters、`L5hner/LShner`→Löhner、`Mfiller/Miiller`→Müller、`Paill~re`→Paillère、`SjSgreen`→Sjögreen、`Damk6hler`→Damköhler、`Hs D.`→Hänel、`Hallbgck`→Hallbäck、`Kadio~lu`→Kadioğlu
- 术语:`k-c/k-e/k-s`→k-ε、`k-w/k-~`→k-ω、`L U-SSOR`→LU-SSOR、`A USM`→AUSM、`gacobian/Yacobian`→Jacobian、`OVER-FLOW`→OVERFLOW
- 编号标签:`[is]`/`[a2]`/`[4s]` 等被 OCR 吞掉的条目号按上下文还原;`(1.21)`→(A.21) 类章号丢失
- 法/德/瑞典文重音:für、Équations、générales、Strömungsfeldern、Försöksanstalten、Université de Montréal 等

## 6. 中文推荐译法(主要术语)

计算流体力学(CFD)、控制方程、Navier-Stokes 方程(保留英文)、欧拉方程、守恒定律、控制体、有限差分/体积/单元法、结构/非结构网格、离散化、对流通量、黏性通量、源项、中心格式、上风格式、显式/隐式格式、湍流建模、边界条件、残差、多重网格、限制器函数、时间推进、雷诺平均、大涡模拟(LES)、原始变量、守恒变量、通量向量、完全气体/真实气体、状态方程、远场、虚单元、单元中心格式、单元顶点格式、对偶控制体、解的重构、限制器、双时间步、预条件。

## 7. 已知边界

- 正文文献引用中,两处 `(Eqs. (2.14, 2.15))` 型共括号引用采用"括号内裸编号各自成链"的形态;范围引用只链两端——两者都与原书可见文字一致。
- 同一文献被多章引用时,各章链接指向同一条 tree;原书重复著录的条目(见第 4 节)保留为两条。
- 插图为灰度扫描裁剪,原书印刷缺陷(如图 5.16 的截断、图 9.1 的墨点)忠实保留。
