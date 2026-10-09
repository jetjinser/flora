# kazmer2016《Injection Mold Design Engineering》翻译起步说明

David Kazmer《Injection Mold Design Engineering》2nd ed. (Hanser, 2016) 的翻译尚未开始。本页记录现状与起步要点。

## 现状

- 书源 PDF 在 `materials/books/`:`Injection Mold Design Engineering (David Kazmer).pdf`(547 页,37.4 MB)。
- 全文 `pdftotext -raw` 抽取已完成:`materials/kazmer2016/full-text-raw.txt`(约 18.4 万词)。
- 文字层由 calibre 电子书转换而来,**正文干净**(无 OCR 噪音),比 blazek2005 容易;但:
  - **公式被转换破坏为 Symbol 字体乱码**(如 `æ ö ÷ ç`),必须对照原 PDF 页重排(流程同 blazek2005:Read 工具直读原页转录);
  - 232 页含插图位图,裁剪流程照 blazek2005;
  - 索引/目录结构需重新提取(未做过 `-layout` 分章切片,第一步应照 blazek2005 的方式生成分章切片)。

## 起步清单

1. 按 blazek2005 的方式生成分章文字切片(`pdftotext -layout`),放入 `materials/kazmer2016/src/`。
2. 定页面划分;id 前缀已定为 **`kazmer2016-`**(Zotero 引用键:作者姓+出版年,依 `docs/translation-guide.md` §1 命名规范):页面 `kazmer2016-chNN`、文献 `kazmer2016-r<章>-<N>`(原书文献编号规则需先核实是否每章独立);源文件放 `plants/kazmer2016/` 子目录(id 取 basename,URL 不受影响);裸姓氏 `kazmer` 留给将来的人物树。
3. 翻译规范照 `docs/translation-guide.md`;格式范例 `plants/blazek2005/blazek2005-ch02.plant`。
4. 试点一章(公式中等密度的一章)验证公式转录与双语形式,再铺开。
