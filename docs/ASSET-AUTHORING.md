# 写入侧补充需求：从零生成 Unity 资产

> **状态：已实施（P0-1 … P2-2 全部）。** 本文保留为需求记录，实施结果与逐条核对结论见 §0.1；用法速查见 [API.md 第 13 节](API.md#13-写入侧从零生成资产)。
> **需求来源：** MapEditor（Electron 美术/地图编辑器）的「PSD → 预制体」导出流程。
> **相关文档：** API 速查见 [API.md](API.md)，GUID 索引见 [GUID-INDEX.md](GUID-INDEX.md)。

## 0.1 实施结果与核对结论

### 落地位置

| 需求 | 实现 |
|---|---|
| P0-1 GUID 生成与分配 | `hxunity.unity.AssetGuid`；随机源抽到 `hxunity.yaml.Xorshift`（与 `UnityDocumentSet.newFileId` 共用）；`AssetGuidIndex.newGuid()` / `CachedGuidIndex.newGuid()` 走索引 O(1) 判重 |
| P0-2 `.meta` 创建 | `hxunity.unity.MetaDocument`（可变模型 + 保留全字段的 `parse`/`emit`）、`MetaWriter`（`forFolder` / `forTexture` / `forNativeAsset` / `forPrefab` / `forScript` / `rewriteGuid`）、`TextureImportSettings` + `SpriteMetaData` + `PlatformTextureSettings` |
| P0-3 单文档资产 | `hxunity.unity.UnityMaterial`（`create` / `fromFile` / `fromTemplate` / `setTexture` / `setShader` / `setRenderQueue` / `save`）、`MaterialProperties`；`UnityDocumentSet.createEmpty()` |
| P0-4 类型化引用 | `hxunity.unity.AssetReference`（fileID + `type` 表，带实测出处）、`AssetClassifier.mainObjectIdOf(extension)`、`UnityReference.texture/material/prefab/sprite/script/shader/builtin` |
| P1-1 组件默认字段 | `hxunity.unity.ComponentDefaults`（GameObject / Transform / RectTransform / MeshRenderer / MeshFilter / SpriteRenderer / SortingGroup / Material；只用于新建，解析路径不注入） |
| P1-2 字段写入便捷方法 | `UnityObject` 增加 `setInt/setFloat/setBool/setString/setReference/setGuidReference/setLocalReference/setVector/setColor/setQuaternion/setSeq/addToSeq/addReferenceToSeq/setFlowMap` |
| P1-3 `m_SavedProperties` 封装 | `hxunity.unity.MaterialProperties`（读写对称，条目按名字排序插入） |
| P1-4 目录级刷新 | `CachedGuidIndex.refreshDirectory(dir):DirectoryRefresh`（重读该目录 + 缓存里没见过的子目录，并更新父目录记录） |
| P2-1 资产写入工具 | `hxunity.unity.AssetWriter`（原子写、LF/无 BOM/末尾换行、`.meta` 路径推导、文件名清洗与重名） |
| P2-2 组合入口 | `hxunity.unity.UnityAssetFactory`（`ensureFolder` / `createTexture` / `createMaterial` / `createPrefab` / `writeMeta`，索引登记 + 重写时保留 GUID） |

### 逐条核对结论（原「待核对项」）

全部以真实语料为准，语料取自 `CATSIM_2`（`2022.3.62f3c1`），副本见 `tests/fixtures/Unity2022/`：

1. **`type:` 的取值**（把工程内全部 `{fileID, guid, type}` 三元组与目标 `.meta` 的 importer 段关联统计）：
   **材质 = `type: 2`**（9,882 次）、**贴图 = `type: 3`**（4,422 次）、**预制体 = `type: 3`**（5,128 次）。
   规则是「`type: 2` = 原生资产（`NativeFormatImporter` 管的 `.mat` / `.asset` / `.controller` / `.anim`）、`type: 3` = 其余工程资产（导入资产 + 预制体）、`type: 0` = 引擎内置」。
   原 `UnityReference` 注释里"`type: 2` 是导入资产（贴图）"的说法与实测相反，已改正并加注实测数据。
2. **`TextureImporter` 的 `serializedVersion` = `13`**（Unity 2022.3 写的），字段与顺序逐行取自真实 `.meta`，内置样板在 `MetaWriter.textureTemplateLines`。
3. **空值冒号**：Unity 2022.3 的 `.meta` 写的是**带尾随空格**的 `userData: `（2,804 份取样中 2,802 份如此），生成的 `.meta` 照此写出。
4. **`m_SavedProperties` 的四个列表按属性名排序**（`_BaseMap` < `_Color` < `unity_Lightmaps`），新属性按序插入而不是追加。
5. **`material` 的 `serializedVersion` = `8`**，字段集与顺序（含 `m_Parent` / `m_ModifiedSerializedProperties` / `stringTagMap` / `m_LockedProperties`）取自真实 `.mat`。
6. **预制体的引用 fileID = `100100000`**；但 `AssetClassifier.mainIdOf` 对 `.prefab` 仍返回 `null`（预制体没有"主对象"）。
7. **`m_Enabled` 不只看 Behaviour**：`Renderer`（MeshRenderer / SpriteRenderer / …）与 `SortingGroup` 也序列化它，`ComponentDefaults.writesEnabled` 单列一张表，没有改动 `ClassIds.isBehaviour` 的既有语义。
8. **`textureFormat` 顶层默认值是 `1`**（2022.3 实测；老编辑器写 `-1`），`platformSettings` 里仍是 `-1`（"跟随"）。
9. **`platformSettings` 默认写三条**（`DefaultTexturePlatform` / `Standalone` / `Android`）：写空数组后 Unity 会在下次导入时补回来，等于把文件重写一遍。
10. **`spriteSheet` 的 `internalID` / `spriteID` 是 Unity 导入时自己分配的值**（老版本按 `21300000 + 2n` 顺序分配，2022 里是每个 Sprite 一个 63 位 id 挂在 `nameFileIdTable` 上）。库**不猜**这两个值：调用方给了才写，给了 `internalID` 就同时写进 `nameFileIdTable`（引用图集里的某个 Sprite 靠这张表）。多 Sprite 条目的字段集取自真实图集 `.meta`。

### 与验收标准的差距（如实说明）

- **「放进真实 Unity 工程导入一次、`git diff` 为空」这一步没有执行**——本环境没有可驱动的 Unity 编辑器。作为替代，测试把生成物与同类型真实文件做**逐字节比对**（文件夹 `.meta` / `.mat` `.meta` / 预制体 `.meta` / 贴图 `.meta` 四类全部一致），并断言生成组件的字段名序列与真实预制体一致；剩余风险是字段**取值**层面的差异（例如 Unity 认为某个默认值应该是别的数），这类差异不会导致资产损坏，只会让 Unity 重写一次文件。
- 多 Sprite 图集的 `internalID` 只能由调用方提供（见结论 10），因此"从零生成一张图集并让 Unity 完全不重写"这一点无法在本库内保证。
- `RefreshResult` 之外新增了 `DirectoryRefresh`（`CachedGuidIndex.refreshDirectory` 的返回值），而不是复用 `RefreshResult`：增量刷新的语义（added / removed / missing）在原结构里无处安放。

## 0. 背景与目标

库目前在「读 / 改 / 保真往返」这条线上已经很完整：YAML 语法层、Unity 对象图、预制体实例、GUID 索引、逐字节往返写回。但**写侧只有「修改已有文件」这一条路径**，缺少「从零造一个新资产」。

触发场景：编辑器要把一个 PSD 的图层组结构导出成一个 Unity 工程目录树——目录结构 + 导出的 PNG + `.mat` + `.meta` + `.prefab`——随后被现有读取链消费：

```
GUID 索引（按 .meta 建） → MaterialLibrary.__parseMaterial（读 .mat） → RenderTreeBuilder（读 MeshRenderer.m_Materials）
```

**目标：让调用方不手搓任何 YAML 文本，也不重复实现 GUID / fileID / `type` 这类 Unity 约定知识。** 这类知识写错不会立刻报错，而是「打开工程才发现贴图丢了」，所以必须收进库里并用真实语料验证。

## 1. 现状缺口一览

| 缺口 | 现状位置 | 后果 |
|---|---|---|
| 没有 GUID 生成能力 | `src/hxunity/unity/` 下无对应类；`BuiltinResources.isBuiltinGuid` 只能判别 | 生成的 `.meta` 没有 guid，索引不到，引用全断 |
| `.meta` 只能读不能写 | `src/hxunity/unity/MetaFile.hx` 只有 `parse`，且只扫前 400 行头部字段 | 只能靠调用方拼字符串，字段集完整性无人保证 |
| 没有「新建单文档资产」入口 | `UnityPrefab.createEmpty()` 语义是 prefab；写 `.mat` 要自己 `new UnityYamlDocument(...)` + 手搓 `YamlMap` | 每个调用点重复实现一遍 Material 结构 |
| 引用构造要知道 fileID / `type` 常量 | `UnityReference.asset(guid, fileId, type)` 可用，但 `AssetClassifier.MAIN_IDS` 是私有静态表 | fileID 写错 = 贴图丢失 |
| `addComponent` 不写类特有字段 | `GameObjectObject.addComponentOfClass` 只写 `m_ObjectHideFlags` / `m_CorrespondingSourceObject` / `m_PrefabInstance` / `m_PrefabAsset` / `m_GameObject` / `m_Enabled` | 生成的 MeshRenderer 缺 `m_Materials`、`m_SortingOrder`…，Unity 读入后补默认值并重写文件 |
| 字段写入要自己造节点 | `UnityObject` 只有 `set(key, YamlNode)`，没有 `setInt` / `setReference` / 序列追加 | 调用方到处写 `new YamlScalar(..., Plain)` |
| 没有 `m_SavedProperties` 封装 | 无 | 编辑器侧 `MaterialLibrary.__parseMaterial` 手写几十行 `YamlSeq`/`YamlEntry` 遍历，读写不对称 |
| `CachedGuidIndex` 无目录级刷新 | 只有 `open` / `refresh` / `save` / `invalidate` | 导出后要看到新资产只能全量重扫（真实工程约 12 秒） |

---

## 2. 需求清单

### P0-1　GUID 生成与分配

**现状：** 库内完全没有 GUID 生成能力。

**需求：** 新增 `hxunity.unity.AssetGuid`（或 `Guids`）：

- `generate():String` —— 32 位小写十六进制，Unity 格式；
- `isValid(text):Bool`、`normalise(text):String`；
- `isNone(text):Bool` —— 全零 guid（Unity 的「无引用」）；
- 唯一性分配：`generateUnique(taken:String->Bool):String`，或更省事的 `AssetGuidIndex.newGuid():String`（内部用 `entriesByGuid` + `misses` 判重，O(1)）。批量导出一次要分配几十到几百个 guid，逐个遍历索引不可接受；
- 生成结果必须**排除**全零 guid 与 `BuiltinResources.isBuiltinGuid` 命中的内置 guid。

**实施注意：** 不要用 `Std.random`。`UnityDocumentSet.newFileId` 的注释里已经记录过 Neko 上未 seed 会抛异常的坑，请复用同一套自实现 xorshift 随机源，保证跨目标一致。

**验收：** 批量生成 10 万个，无重复、无全零、无内置 guid，格式与真实 `.meta` 一致。

---

### P0-2　`.meta` 创建（最关键缺口）

**现状：** `MetaFile.parse` 只读，且只解析头部四个字段（`guid` / importer / `mainObjectFileID` / `folderAsset`）。写 `.meta` 目前只能按 API.md §处理 `.meta` 的配方手工拼。

**需求：** 提供写入侧模型与工厂。两种形态可任选其一，或都提供：

1. **可变模型：** `MetaFile.create(guid, importer)` → `get`/`set` 字段 → `emit()` / `save(path)`；
2. **工厂方法（按 importer 分）：**
   - `MetaWriter.forFolder(guid)` —— `DefaultImporter` + `folderAsset: yes`；
   - `MetaWriter.forTexture(guid, ?TextureImportSettings)` —— `TextureImporter`；
   - `MetaWriter.forNativeAsset(guid, mainObjectFileID)` —— `.mat` / `.asset`，`NativeFormatImporter`；
   - `MetaWriter.forPrefab(guid)` —— `PrefabImporter`；
   - `MetaWriter.rewriteGuid(templatePath, guid)` —— **从一份样板 `.meta` 复制、只替换 guid**。这是 Unity 兼容性最高的一条路，建议作为 `forTexture` 的实现基础。

`TextureImportSettings` 至少覆盖：`textureType`（Sprite / Default）、`spriteImportMode`、`spritePixelsToUnits`（PPU）、`spritePivot`、`alphaIsTransparency`、`mipmapEnabled`、`maxTextureSize`、`filterMode`、`wrapMode`、压缩设置、`platformSettings`（可默认空数组）、`spriteSheet`（`SpriteMetaData`：name / rect / pivot / alignment / border，用于多 Sprite 图集式导出）。

**输出细节（必须与 Unity 2022.3 对齐）：**

- 首行 `fileFormatVersion: 2`，`guid:` 顶格，随后是驼峰命名的 importer 段；
- 2 空格缩进、LF 行尾、文件末尾保留一个换行、UTF-8 无 BOM；
- 空值冒号沿用库现有规则（`userData:` 无尾随空格，场景里的 `value: ` 带空格）；
- **逐个 importer 的 `serializedVersion` 必须与 Unity 2022.3 对齐**——请从真实资产取样核对，不要凭记忆填；
- `spritePixelsToUnits` 缺失会退回 Unity 默认值，而本编辑器的渲染链强依赖 PPU 与材质 Pivot 一致，所以这个字段必须在默认值里显式写出。

**验收（金标准）：** 把库生成的 `.meta` 放进一个真实的 Unity 2022.3 工程，让 Unity 导入一次，**导入前后 `git diff` 为空**（或差异可逐条解释）。做不到这一步的字段集，等于把重写风险转嫁给了调用方。

**待核对项：** 每类 importer 的完整字段名与顺序，请以真实语料为准；测试语料需要新增一份真实的 `TextureImporter` `.meta` 与一份 folder `.meta` 作为对照基准。

---

### P0-3　从零创建单文档资产（`.mat` / `.asset`）

**现状：** 写 `.mat` 需要调用方自己 `new UnityYamlDocument(ClassIds.Material, id, false, body)` 并手搓整个 `m_SavedProperties`。

**需求：** 新增 `UnityMaterial`（命名与所在包由你定，语义上属于「单文档资产」而非 prefab）：

- `UnityMaterial.create(?shaderGuid)`；
- `UnityMaterial.fromFile(path)` / `fromTemplate(templatePath)`（从样板复制，保留 Unity 写的字段集与 `serializedVersion`）；
- `setTexture(property, textureGuid, ?fileId)`、`setColor(property, ColorData)`、`setFloat(property, Float)`、`setVector(property, VectorData)`；
- `setShader(guid, ?fileId)`、`setRenderQueue(value)`（决定写 `m_CustomRenderQueue` 还是着色器的 Queue 标签）；
- `save(?path)`。

同时建议给 `UnityDocumentSet` 补一个 `createEmpty()`（带标准 `%YAML 1.1` / `%TAG` 前导的空文档集），这样单文档资产不必借用 prefab 语义。

**生成的最小结构（本编辑器读取链已依赖）：**

```yaml
%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!21 &2100000
Material:
  serializedVersion: 8
  m_ObjectHideFlags: 0
  m_CorrespondingSourceObject: {fileID: 0}
  m_PrefabInstance: {fileID: 0}
  m_PrefabAsset: {fileID: 0}
  m_Name: <名字>
  m_Shader: {fileID: 4800000, guid: <着色器 guid>, type: 3}
  m_CustomRenderQueue: <队列值，或 -1 交给着色器 Queue 标签>
  m_SavedProperties:
    serializedVersion: 3
    m_TexEnvs:
    - _MainTex:
        m_Texture: {fileID: 2800000, guid: <贴图 guid>, type: ?}
        m_Scale: {x: 1, y: 1}
        m_Offset: {x: 0, y: 0}
    m_Ints: []
    m_Floats: []
    m_Colors: []
```

> 示例中的字段顺序与 `serializedVersion` 数值仅供示意，实际取值请以真实 `.mat` 语料为准。

> **待核对项（重要）：** 贴图引用里的 `type:` 取值。库现在 `UnityReference` 的注释写的是「`type: 2` 是 imported asset（贴图）、`type: 3` 是 project asset（脚本）」，但真实 Unity 材质文件里贴图引用常见 `type: 3`，而本编辑器工程里的材质引用样例是 `{fileID: 2100000, guid: ..., type: 2}`。请用真实 `.mat` 语料确定材质/贴图/预制体三类引用各自的 `type`，并把结论写进注释与常量表。

**验收：** 库生成的 `.mat` ① 能被 Unity 导入为正常材质、贴图槽位正确、无 Missing；② 能被本编辑器的 `MaterialLibrary.__parseMaterial` 解析出 `texturePath` / `pivot` / `renderQueue`。

---

### P0-4　类型化引用与主对象 fileID

**现状：** `UnityReference.asset(guid, fileId, type)` 存在，但调用方要自己知道 fileID 和 `type`；`AssetClassifier.MAIN_IDS` 是私有静态表，`mainIdOf(meta, extension, kind)` 又需要一个 `MetaFile` 实例才能调用。

**需求：**

- 公开 `AssetClassifier.mainObjectIdOf(extension:String):Int64`（无需 `MetaFile`）；
- 新增类型化引用构造：
  - `UnityReference.texture(guid)` → `{fileID: 2800000, guid, type: ?}`
  - `UnityReference.material(guid)` → `{fileID: 2100000, guid, type: 2}`
  - `UnityReference.prefab(guid)` → `{fileID: 100100000, guid, type: ?}`
  - `UnityReference.sprite(guid, fileId)`（图集内子 Sprite）
- 或统一入口 `AssetReference.of(guid, AssetKind)`。

**理由：** 一次导出要生成几百条引用，fileID / `type` 写错是最高发的静默 bug，这类知识必须在库里集中维护。

---

### P1-1　组件的默认字段模板（写 prefab 的必要条件）

**现状：** `addComponentOfClass` 只写公共字段，不写类特有字段。于是 `addComponent("MeshRenderer")` 产出的 MeshRenderer **没有 `m_Materials`**，也没有 `m_SortingLayerID` / `m_SortingOrder`，Unity 读入时会补默认值并重写整个文件；本编辑器 `RenderTreeBuilder.createMesh` 也正是靠 `m_Materials` 找材质、靠 `m_SortingLayerID` 判排序层。

**需求：** 为库已知的类准备「默认字段模板表」，`addComponent` 用模板初始化。至少覆盖：`Transform`、`RectTransform`、`GameObject`、`MeshRenderer`、`MeshFilter`、`SpriteRenderer`、`SortingGroup`、`Material`、`Texture2D`（meta 侧）。

**边界（必须遵守）：** 模板**只在新建时**使用。解析已有文件时仍以文件内容为准，**绝不允许注入字段**，否则会破坏逐字节往返这一核心保证，既有 500 条断言会挂。

**验收：** `createEmpty()` → `createGameObject` → `addComponent("MeshRenderer")` → `save()` 产出的 prefab，Unity 打开后 `git diff` 为空。

---

### P1-2　字段写入的便捷方法

**现状：** `UnityObject` 只有 `set(key, YamlNode)`，调用方要自己造节点。

**需求**（放在 `UnityObject` 或 `Component` 上）：

- `setReference(key, UnityReference)` / `setGuidReference(key, guid, ?fileId, ?type)`
- `setInt` / `setFloat` / `setBool` / `setString`
- `setVector(key, VectorData)` / `setColor(key, ColorData)` / `setQuaternion`
- `addToSeq(key, node)` / `setSeq(key, Array<YamlNode>)`
- `setFlowMap(key, ...)` —— 用于 `m_TexEnvs` 那种行内映射

写出的引号风格、流式折行、数字写法必须与 Unity 一致——库内已有 `Scalars.ofString`、`plain`、`YamlWriter` 等设施，请复用并暴露，不要另起一套。

---

### P1-3　`m_SavedProperties` 读写封装

**现状：** 无。编辑器侧在 `MaterialLibrary.__parseMaterial` 里手写遍历 `m_TexEnvs` / `m_Colors` / `m_Floats`，共几十行防御性判断。

**需求：** `MaterialProperties` 封装：

- `getTexture(prop):String`（返回 guid）/ `setTexture(prop, guid, ...)`
- `getColor(prop):ColorData` / `setColor` / `getFloat` / `setFloat` / `getVector`
- `removeProperty(prop)`
- 保证生成的条目形状与 Unity 一致（如 `- _Pivot: {r: 0.5, g: 0.5}`，自定义属性按 `r/g/b/a` 键序列化）

**收益：** 编辑器侧可以删掉手写遍历，且读/写对称——同一个封装既能解析 Unity 原生材质，也能生成自己的材质。

---

### P1-4　`CachedGuidIndex` 的目录级刷新

**现状：** `CachedGuidIndex` 只有 `open` / `refresh` / `save` / `invalidate` / `size` / `isLoaded`。底层 `AssetGuidIndex.scanDirectory(directory)` 已经有了，但没有往上透出，也没有和缓存落盘串起来。

**需求：** `CachedGuidIndex.refreshDirectory(dir):RefreshResult`（或返回本次新增/移除的 guid 列表），内部走 `AssetGuidIndex.scanDirectory` + 缓存更新。

**理由：** PSD 导出是「边导边看」的交互流程，每导一个资源就全量重扫（真实工程约 12 秒）不可接受。

---

### P2-1　资产写入工具

**需求：** `AssetWriter` 或同级工具：

- `ensureDirectory(path)`；
- `saveText(path, text)` —— LF、UTF-8 无 BOM、末尾换行；
- `saveBytes(path, bytes)`；
- **原子写**（临时文件 + rename）—— 半截文件会被 Unity 索引成损坏资产，也会让编辑器读到不完整 YAML；
- `metaPathOf(assetPath)` / `assetPathOf(metaPath)` —— 索引按「`<资产名>.meta`」推导资产路径，命名规则错一位就整条链断掉；
- `uniqueFileName(dir, baseName, ext)` —— PSD 图层重名/非法字符清洗。

---

### P2-2　新建资产的组合入口（可选，但价值高）

一次调用生成配套的一组文件并保证互相引用正确，例如：

```haxe
var asset = UnityAssetFactory.createTexture(projectRoot, "Assets/Psd/Hero/hand.png", pngBytes, settings);
// → 写 png、写 png.meta（新 guid）、返回 AssetEntry
```

本编辑器的 PSD 导出正是这个用例（每导出 1 个图层 = 1 个 png + 1 个 `.meta` + 1 个 `.mat` + 1 个 `.mat.meta`）。

---

## 3. 明确不在范围内

以下由编辑器侧负责，**不要**进库：

- PSD 解析（编辑器走 npm 的 `ag-psd`，渲染进程/主进程内使用，不引入 Haxe 侧解析器）；
- 位图编码与像素合成（PNG 编码走纯 JS 的 `pngjs` 或 DOM canvas，不做 Haxe 实现）；
- 「PSD 图层树 → prefab 层级 / 坐标 / Pivot」的业务映射规则；
- 工程的排序层（SortingLayer）设置、渲染顺序判据。

## 4. 与编辑器的对接契约（建议作为验收依据）

库侧实现时，请以下面这些现有读取点为验收面——生成物必须能被它们原样消费：

| 读取点 | 位置 | 依赖的字段 |
|---|---|---|
| 资产索引 | `ProjectFiles.scanInto` | 每个资产必须有同名 `.meta`；文件夹要有 `folderAsset: yes` |
| 材质解析 | `MaterialLibrary.__parseMaterial` | `m_CustomRenderQueue`；`m_Shader`；`m_SavedProperties.m_TexEnvs[].<prop>.m_Texture`（外部 guid）；`m_Colors` 中含 `pivot` 的 `{r, g}`；退化到 `m_Floats` 的 `_PivotX` / `_PivotY` |
| 着色器队列 | `MaterialLibrary.__parseShaderQueue` | `.shader` 文本里的 `Queue = "..."` |
| 渲染 | `RenderTreeBuilder.createMesh` | `m_Materials[0]` 的外部 guid；`m_SortingLayerID` / `m_SortingOrder` |
| 主对象 fileID | `AssetClassifier.MAIN_IDS` | 纹理 `2800000`、材质 `2100000`、MonoScript `11500000` |

## 5. 建议的实施顺序

1. **P0-1 GUID + P0-2 `.meta`**：没有这两项，后面全都落不了地；
2. **P0-3 `.mat` + P0-4 类型化引用**：编辑器可以开始导「图片 + 材质」；
3. **P1-1 组件模板 + P1-2 字段写入**：编辑器可以开始导 `.prefab`；
4. **P1-4 目录级刷新**：导出体验闭环；
5. **P1-3 / P2-1 / P2-2**：编辑器侧瘦身与工程健壮性。

## 6. 测试要求

- 新增真实语料：`.mat`、`TextureImporter` `.meta`、folder `.meta`、带 MeshRenderer 的 `.prefab` 各一份；
- 新增断言：
  1. 从零生成的 `.mat` / `.meta` / `.prefab` 与 Unity 写的对照文件逐字节一致（或差异可解释并写明）；
  2. 生成的 guid 唯一、格式合法、非全零、非内置；
  3. 生成的 `.prefab` 能被 `UnityPrefab.fromFile` 读回，且组件字段完整（`m_Materials` 在）；
  4. `scanDirectory` / `refreshDirectory` 之后，新资产的 guid 可 `locate` 到；
  5. **既有 500 条断言全绿**，逐字节往返保证不被模板机制破坏。
- 保持库既有约束：零外部依赖、JS/Electron 就绪、64 位 id 全程 `Int64` 不经过 `Float`。
