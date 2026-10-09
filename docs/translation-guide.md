# 书籍翻译规范

本文档是 Flora 站点上书籍翻译项目的正式规范,整理自《The Elements of Style》与《Computational Fluid Dynamics》(下称 CFD)两本书的实际翻译实践。适用于:修订现有译文、翻译新章节、以及启动新书的翻译。修改本文档前请先确认与站点实际渲染效果一致。

站点与构建方法见仓库根目录 `README.md`。

## 1. 页面骨架

每个章节/附录/索引是一个 `.plant` 文件,位于 `plants/`,文件名决定页面地址(`blazek2005-ch02.plant` → `/blazek2005-ch02.html`)。源文件可按书归入子目录(`plants/blazek2005/`、`plants/strunk1999/`):Grove 递归收集、**id 仍取文件 basename**(扁平化),目录只是组织手段,URL 不受影响;注意从项目根目录运行 grove 命令。

**id 命名规范**(2026-10-10 全站整理后确立,新书包定前缀时遵守):

- 所有可寻址树 id 一律以书前缀开头(`<书>-…`)且**全小写**(URL 大小写敏感);`unstable` 等位置生成的地址除外。**前缀用 Zotero 引用键:作者姓+出版年**(如 `blazek2005-`、`strunk1999-`):图书在英语引用实践中的通行"缩写"就是作者键(`[Blazek, 2005]`、bibtex `blazek2005`),多版本由年份天然区分;领域通称(`cfd` 这类)撞车风险高,不用。**裸姓氏保留给 `taxon person` 人物树**(`blazek`、`strunk`),书主页用完整键(`blazek2005`)。
- 页面 id 结构自描述:前置材料 `<书>-front`、章节 `<书>-chNN`(两位补零,章号与 id 直接对应)、书索引 `<书>-index`、后记页 `<书>-back`;一章拆多页时加字母后缀(如 strunk1999 第四章三份 `strunk1999-ch04a/b/c`)。
- 小节子树 `<书>-<章>-<节>`;词条型子树 `<书>-<类型>-<名称/编号>`(如 `strunk1999-rule-1`、`strunk1999-usage-aggravate`、`blazek2005-front-symbols`)。**禁止裸词 id**——早期 strunk1999 曾有 `foreword`、`rule-1` 这类无前缀子树,会直接污染全站顶层 URL。例外:人物树用裸姓氏(`blazek`、`strunk`、`white`),`@taxon["person"]`,中文小传,存 `plants/person/`;著作页用 `@author["<人树>"]` 标注作者——读取期只记录目标树,链接文本在分析期取自人树标题(实现见 `modules/commands.plant` 与 `modules/queries.plant`),即 jms forester `\author{kazmer}` 引用 `kazmer.plant` 的语义。
- 文献条目 `<书>-r<章>-<编号>`(附录章号小写,如 `blazek2005-ra-3`);公式锚点 `eq-<章>-<编号>` 是页内 fragment,不占树命名空间,无需前缀。

```scheme
@use-modules[(flora commands) (language scribble commands)]

@title{Governing Equations 第2章 控制方程}
@summary{一句话中文摘要。}
@taxon["chapter"]
```

- 第一行 `@use-modules` 固定不变;`(flora commands)` 提供 `@bi`、`@emph`、`@sidenote`、`@defn` 等,并转出 `bilingual`/`lang`/`term`。
- taxon 约定:正文章节 `chapter`、索引/主题索引 `index`、文献条目页 `reference`;前置材料页不写 taxon。taxon 会以首字母大写形式显示在标题上方(如 "Chapter.")。
- 小节用可嵌套的 `@subtree[#:id "..."]{ @title{4.2.1 Cell-Centred Scheme 单元中心格式} ... }`,**每个小节必须有稳定 ID**,命名 `blazek2005-<章>-<节>`(如 `blazek2005-3-1-2`);每个小节会生成独立路由页(`blazek2005-3-1-2.html`)。
- 标题双语:英文原题在前、中文译名在后。
- 同书内所有作者 id 必须带书名前缀且唯一(Grove 会对重复 id 报错);无 id 的子树只能得到位置生成的"不稳定"地址,应避免。

## 2. 双语形式

散文按原文自然段逐段做成双语块,`@bi` 是 `@bilingual[#:reader "zh-CN"]` 的别名(定义于 `modules/commands.plant`):

```
@bi{
  @lang["en"]{The discussion of the conservation laws leads us…}
  @lang["zh-CN"]{对守恒定律的讨论很自然地引导我们……}
}
```

- 中文 lane 默认显示,英文原文折叠;折叠提示自动使用被折叠 lane 的语言码(如 "en ▸"),不要传 `#:source-label` 覆盖它。
- 英文 lane **忠实照录原文**:还原行末断字("begin-ning"→"beginning"),删除页眉页脚,原书排印笔误照录不改;中文 lane 按语义翻译。
- 中文 lane 标点用全角("，" "。" ";"),中文与拉丁字母/数字之间不加手动空格;英文 lane 保持英文标点。
- 列表、代码块等块级内容随所在段落进入两条 lane,中文 lane 用中文重建。
- 字面 `@` 写成 `@"@"`;所有大括号必须配平;禁用 Markdown 语法。

## 3. 数学公式

公式一律用 LaTeX 重排(源书扫描件的 OCR 文字层公式不可靠,**必须逐条对照扫描页转录**,禁止凭 OCR 文字层猜造):

- 展示公式:`@tex-display-math[#:id "eq-<章>-<编号>"]{ … \tag{<章>.<编号>} }`,放在两个双语块之间(公式无语言,不进双语块、不重复渲染)。多行推导用 `aligned`。
- 行内公式与变量:`@tex-math{...}`,两条 lane 内各自照写。
- 原书无编号的展示公式不加 `#:id`,也不写 `\tag`。
- 正文对公式的引用写成 `@link["blazek2005-chNN#eq-N-M"]{(N.M)}`,可精确滚动到公式;双语 lane 同步;范围引用 `(2.19)–(2.25)` 只链两端、连接符留在外。
- 公式 id 挂在容器元素上,MathJax 在浏览器端渲染(`flora-head` 已配置 `output.displayOverflow: 'scale'`,超宽公式自动缩放;并在排版完成后对 URL 锚点补一次滚动)。⚠ 内联 `<script>` 的内容会被 HTML 转义,写配置时避开 `=>`、`&`、`<` 等字符。

## 4. 引用与文献

原书文献编号**每章独立重起**,文献条目页的 id 必须带章号:`blazek2005-r<章>-<编号>`,全小写(附录A 的章号写作 `a`,如 `blazek2005-ra-3`)。

- 每条文献一个页面:`@title{}` 为条目完整英文原文,`@taxon["reference"]`,正文可附一句中文说明(可选)。
- 正文引用一律链接化:`[32]` → `@link["blazek2005-r2-32"]{[32]}`,双语 lane 同位置同步。
- 合并引用拆成多个链接、标点留在链接外(`[14, 15]` → `@link[…]{[14]}、@link[…]{[15]}`);范围引用 `[15]-[17]` 只链两端、连接符留外——与原书可见文字保持一致。
- 章末不手写文献列表:页面底部"参考文献"区由 Grove 自动汇总本页引用;文献页自身有"反向链接"区列出全部引用位置。
- `@image` 的替代文本只能是纯文本(见下节);文献引用不要放进 `@image` 或 `@tex-math` 内部。

## 5. 插图

插图从原书扫描页裁剪,嵌入双语块之外(与展示公式同策略),图下接中文图题与图例译文:

```
@image["blazek2005/fig-2-1.png"]{图2.1:有限控制体的定义(固定于空间中)}

@emph{图2.1:有限控制体的定义(固定于空间中)。}图例:流线;@tex-math{\Omega}——控制体;…
```

裁剪流程(全程可脚本化):

1. `nix shell nixpkgs#poppler-utils nixpkgs#imagemagick -c bash -c '...'` 后 `pdftoppm -png -r 200 -f <PDF页> -l <PDF页> "<PDF>" out`(整页约 1220×1920)。
2. Read 整页 PNG,按比例估算图形包围盒(**不含**英文 "Figure X.Y:" 图题行)。
3. `convert -crop WxH+X+Y +repage -fuzz 8% -trim +repage` 输出到 `assets/blazek2005/fig-<章>-<图>.png`,`-trim` 自动去白边;结果必须 Read 目检:图形完整、无英文图题残留、轴标签/子图标注齐全。
4. `assets/` 目录由 `project.scm` 递归扫描自动注册(URL 即 `/blazek2005/fig-X-Y.png`),新增图片无需改配置。
5. 图片样式见 `style.css` 的 `.article img`(居中、88% 限宽)。

纯数值表格用 `@verbatim` 重建,不裁图。

## 6. 译注与边注

原书排印疑误(拼写、缺负号、括号不配对等)的处理:英文 lane 忠实照录;需要提醒读者时用 `@sidenote{译注:原书印作…,通行形式应为…}` 放在对应段落处(页边注;第10章起用此惯例,第3–9章为行内括号译注,如第7章式 (7.54),保持原样即可)。

## 7. 子代理协作模式(大章节生产)

一章由 2–3 个子代理并行生产,主会话合并:

- **切分范围必须按原书目录精确到小节**,并在任务书里写明各小节的印刷页码;合并前用"公式编号断点"交叉核对(前半章末条 id 与后半章首条 id 衔接),实践中已两次靠断点核对发现整节遗漏与跨页公式缺口。
- 页界截断的句子与跨页公式是高发缺口,合并时人工核对两半接缝。
- 各代理只写自己的临时 part 文件,不跑构建;合并后统一 `grove check`。
- 子代理并发受配额限制,同批 2 个为宜;超限报错等待后重试即可。

## 8. 各书特例

- **eos(The Elements of Style,前缀 `strunk1999`)**:同为段落级双语(2026-10-08 自纯中文译文改造);页面 `strunk1999-front`(前言+导言)、`strunk1999-ch01`…`strunk1999-ch05`(第四章拆 `ch04a/b/c` 三页)、`strunk1999-back`(后记+术语表);条目型内容每条一个带 id 的子节,类型有 `strunk1999-rule-N`、`strunk1999-usage-*`(误用词)、`strunk1999-gloss-*`(语法词条)、`strunk1999-reminder-N`、`strunk1999-form-*`、`strunk1999-foreword`/`strunk1999-introduction`/`strunk1999-afterword`;误/正例句与文学引文恢复为 `@itemize`/`@blockquote`,保留英文、置于双语块之外;英文 lane 的 OCR 粗稿(`materials/strunk1999/`)需还原为干净原书文本。
- **CFD**:数学锚点(第3节)、文献树(第4节)、插图(第5节);Navier-Stokes 等以英文更常见的名称保留英文;原书文献编号每章独立。
- 新书参照本文档 + 已完成书作为格式范例(`plants/blazek2005/blazek2005-ch02.plant` 是公式/引用/图片的完整样例)。

## 9. 已知边界

- 公式 id 的同页唯一性校验不覆盖 transclude 进来的子树(同一公式经 transclude 渲染两次时可重复)。
- MathJax 从 CDN 加载,浏览需联网;完全离线可改为构建期 temml 转换或本地打包 MathJax。
- 子树锚点(`@link["页#子树id"]`)尚未支持——Grove 生成的子树 DOM id 是位置 id;公式锚点不受影响。
