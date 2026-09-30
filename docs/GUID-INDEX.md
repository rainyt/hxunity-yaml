# AssetGuidIndex 设计与实施方案

> **状态：已实施（阶段 1–5）。** 实现落在 `src/hxunity/unity/`，API 速查见 [API.md 第 9 节](API.md#9-guid-索引与缓存)。
> 实施过程中修正了本方案早期版本的若干判断，下面用 **⚠️ 实施修正** 标出。
> 尚未做：Unity 侧导出脚本（可选输入源）。

目标：让库能**按 GUID 解析 Unity 资产引用**（`{fileID: 2100000, guid: 506c261d..., type: 2}` → 实际资产），重点是材质、贴图、网格、图集等资源，并带一层**持久化缓存**避免每次打开工程重扫。

---

## 1. 目标与非目标

### 目标

1. **GUID → 资产路径**（全项目，一次建索引，之后增量维护）。
2. **GUID → 资产类型**（材质 / 贴图 / 网格 / 动画 / 字体 / 着色器 / 脚本 / 文件夹 …）。
3. **GUID → 主对象 fileID**，用于把 `type: 2` 的引用解析到资产内部对象。
4. **内置资源解析**（`guid: 0000000000000000e000000000000000` 且 `type: 0`），这些**不在工程里**，普通遍历永远查不到。
5. **持久化缓存 + 增量失效**：有效的缓存让"打开工程"从 1.3 秒降到 6 毫秒。
6. **跨文件引用追踪**：`{guid, fileID}` → 目标文件 → 目标文档。

### 非目标（本阶段明确不做）

| 不做 | 原因 |
|---|---|
| C# 类名解析（`m_Script` guid → 类名） | 你已确认不需要。省掉读全部 `.cs` 的 **1.7 秒**，是全量建索引最大的一笔开销。接口留扩展位。 |
| GUID → 依赖清单（材质引用了哪些贴图） | 需要解析资产正文，成本高一个量级。按需读，不进索引。 |
| 资产内容哈希 | Unity 用 `.meta` guid 定位，不做内容寻址。 |
| 修改 `.meta` / 重写 guid | 只读索引。 |

---

## 2. 为什么是两层

这是整个设计的核心决策，值得单独说清楚。

| | Level 1：全局索引 | Level 2：资产内对象表 |
|---|---|---|
| 覆盖范围 | 工程里**所有** `.meta` | 只有**被实际问过**的资产 |
| 数据来源 | `.meta` 前几行 | 资产正文（`.mat` / `.prefab` / `.asset` 的文档头） |
| 建表成本 | 18,489 个文件 ≈ **822 ms** | 按需，单文件毫秒级 |
| 回答 | guid → 路径 / 类型 / 主 fileID | guid + fileID → 该对象是什么 |
| 生命周期 | 持久化到磁盘 | 内存 LRU，可丢弃 |

**理由**：解析 `{guid: 506c261d..., fileID: 2100000, type: 2}` 这个引用只需要"这个 guid 是哪个文件"（Level 1 就够）。只有当你要问"这个文件里 2100000 到底是哪个材质"时才需要 Level 2。绝大多数场景（列引用、换材质、路径统计）Level 1 已经足够，而它对**全部 18,489 个资产**都成立。Level 2 只对真正访问的少数文件付出成本。

---

## 3. 数据模型

### 3.1 Level 1 记录

```
AssetEntry {
    guid      : String     // 32 位十六进制小写
    path      : String     // 相对 projectRoot，正斜杠
    kind      : AssetKind  // 见 3.2
    mainId    : Int64?     // 主对象 fileID，未知为 null
    origin    : Origin     // Project | Package | Builtin
}
```

### 3.2 `AssetKind`：从 importer 名 + 扩展名推导（实测映射）

`.meta` 第 3 行起是 importer 段名，实测本工程分布：

| importer 名 | 实测数量 | `AssetKind` |
|---|---|---|
| `NativeFormatImporter` | 6,028 | `NativeAsset`（`.mat` / `.asset` / `.controller` / `.anim` …） |
| `TextureImporter` | 4,151 | `Texture` |
| `MonoImporter` | 3,267 | `Script` |
| `PrefabImporter` | 3,139 | `Prefab` |
| `TextScriptImporter` | 736 | `Text` |
| `DefaultImporter` | 687 | `Folder`（配 `folderAsset: yes`）或 `Unknown` |
| `AudioImporter` | 165 | `Audio` |
| `ShaderImporter` | 30 | `Shader` |
| `PluginImporter` | 23 | `Plugin` |
| `AssemblyDefinitionImporter` | 6 | `Assembly` |
| `ModelImporter` | 5 | `Model` |
| `TrueTypeFontImporter` | 3 | `Font` |
| `VideoClipImporter` | 1 | `Video` |

**注意两个解析陷阱（都是实测踩到的）：**

- **不能假设"第一个顶层键就是 importer"**：有 **62 个** `.meta` 把 `labels:` 写在 importer 段之前。要**跳过 `guid:` / `labels` / `fileFormatVersion`**，取第一个以 `Importer` 结尾的顶层键；取不到就标成 `Unknown`，不要报错。
- **`mainObjectFileID` 只出现在 `NativeFormatImporter` 里**（6,021 / 6,028）。其余 importer 一律没有这个字段，必须靠下表推导，否则 2/3 的资产会拿不到 mainId。

### 3.3 `mainId` 推导表

| 资产 | 主对象 fileID | 来源 |
|---|---|---|
| `.mat` | `2100000` | `.meta` 的 `mainObjectFileID`（实测一致） |
| `.asset` / ScriptableObject | `11400000` | `.meta` 的 `mainObjectFileID`（实测 11400000） |
| `.controller` | `9100000` | 推导 |
| `.anim` | `7400000` | 推导 |
| `.shader` | `4800000` | 推导 |
| `.png` / `.jpg` / `.tga` … | `2800000` | 推导（`Texture2D`） |
| `.ttf` / `.otf` | `1280000` | 推导 |
| `.prefab` | **无"主对象"概念** | 预置体是 GameObject 树，根不唯一；`{guid, fileID}` 直接指向其中某个文档 |
| 文件夹 | `null` | `folderAsset: yes` |
| `.cs` | `11500000` | `MonoScript` |

**策略：优先用 `.meta` 里的 `mainObjectFileID`，取不到再按 (extension, importer) 查表，两者都没有就留 `null`。** 留 `null` 不报错，解析时退回"按需读资产正文找"。

### 3.4 内置资源（必须单独一张表）

内置资源**不在工程里**，任何 `.meta` 遍历都查不到。我在真实工程里统计了实际出现的内置引用：

| 参考写法 | 出现次数 |
|---|---|
| `{fileID: 10210, guid: 0000000000000000e000000000000000, type: 0}` | **5,693** |
| `{fileID: 10754, guid: 0000000000000000f000000000000000, type: 0}` | 53 |
| `{fileID: 10304, guid: 0000000000000000f000000000000000, type: 0}` | 7 |
| `{fileID: 10001, guid: 0000000000000000e000000000000000, type: 0}` | 7 |
| `{fileID: 10102, ...e000...}` / `10309` / `10303` / `10905` / `10750` / `10202` / `10207` / `10758` | 各 1–4 |
| **合计** | **12 个不同引用** |

**这里修正了我自己方案初稿里的一个错误判断。**

我原本写的是"全零 GUID + `type: 0` ⇒ 内置资源"。**实测是错的** —— 该工程里出现的两族内置 guid 是：

```
0000000000000000e000000000000000   ← 4/5 号位是 e
0000000000000000f000000000000000   ← 4/5 号位是 f
```

**都不是全零 guid**。所以判定必须是**"guid 属于内置 guid 集合 + `type: 0`"**，而不是"guid 全零"。（全零 guid 确实存在，但那用在 `m_SceneGUID` 之类的地方，不是这套内置引用。）

设计要求：

- **内置 guid 集合**至少要含上面两个，做成可扩展的静态集合；判定函数命名建议 `isBuiltinGuid(guid)`，别再叫 `isZeroGuid`。
- **精选 fileID 表**：只覆盖高频项。本工程 12 个引用里 `10210` 占了 **99%**，所以"精选"按实测分布来做最划算。已知 `10210` 是内置 **Cube** 网格（Unity 的 primitive 就来自这套内置网格，见 [Primitive Objects 手册](https://docs.unity3d.com/Manual/PrimitiveObjects.html)；社区也在讨论这些 default resources 引用，如 [AssetRipper #1271](https://github.com/AssetRipper/AssetRipper/issues/1271)）。
- **其余 fileID 的名字我没有可靠来源，不要凭记忆填。** 方案里只登记"已确认"的，其余标成 `Builtin` + 原样 fileID。解析不到名字**不是错误**——能报出"这是内置资源，fileID=10210"本身就有价值。
- 表设计成可扩展静态数据，使用者可自行补充；随 Unity 版本变，所以缓存头记录 `# unity` 版本，不符就重建这部分。

---

## 4. 缓存格式与增量算法

### 4.1 文件格式：TSV + 注释头

选 TSV 而不是 JSON：**行式可流式解析**、坏行可跳过、可 diff、可手看。JSON 需要整串载入并构造对象树。

```
# hxunity-yaml guidindex v1
# root	D:\Project\CATSIM_2
# unity	2022.3.62f1
# stamp	1761890000
# dir	Assets	1761889000
# dir	Assets/Art	1761889500
# dir	Assets/Art/Materials	1761889600
# bindir	7f3a2b1c9e5d4a6b8c0f1e2d3a4b5c6d	6eb88238706c38746bb3e2a2be435be3	2100000	119
<guid>	<relpath>	<kind>	<mainId>
6eb88238706c38746bb3e2a2be435be3	Assets/Art/Materials/plane.mat	NativeAsset	2100000
b5b59a04266677f4db30660c10721917	Assets/Art/Textures/2-1.png	Texture	2800000
```

| 头部行 | 含义 |
|---|---|
| `v1` | 缓存格式版本，不匹配直接重建 |
| `root` | 工程根，换了工程目录就作废（防止缓存被误用） |
| `unity` | Unity 版本，内置资源表随版本变，变了要重建那部分 |
| `dir` | **每个目录的相对路径 + mtime（秒）**，增量失效的核心 |
| `bindir` | 内置资源精选表（版本相关，随 `unity` 一起重建） |

数据行只走 TSV，不做嵌套 —— 需要更多字段时**增加列并升 `v1`**，不要发明嵌套语法。

**大小：实测 2.10 MB**（18,489 行，平均 **119.3 字节/行**）。行式读不需要一次性载入 —— 可以边读边建内存表，或只在需要时线性扫描。

### 4.2 缓存位置

优先级：

1. `<projectRoot>/Library/hxunity-yaml/guidindex.tsv` —— **首选**。Unity 自己忽略 `Library/`，不进版本控制，删掉无副作用。
2. 只读工程时退到 `%LOCALAPPDATA%/hxunity-yaml/<projectRoot 的稳定哈希>.tsv`。

**必须注意**：缓存文件**不能落在被扫描的目录树里**（否则自己改自己导致永久失效）。放在 `Library/` 天然满足；如果用 `%LOCALAPPDATA%` 也无所谓。若使用者坚持放在 `Assets/` 下，必须把自身路径从 `dir` 表中排除。

### 4.3 增量刷新算法（核心）

```
refresh(projectRoot):
  1. 读缓存头
       缺失 / 版本不符 / root 不符 / unity 不符  → 全量重建（goto 5）
  2. 遍历目录树，但【只 stat 目录，不读文件】        ← 实测 6 ms / 716 目录
       若某个目录不在 dir 表里（新增目录）→ 标记 dirty
       若某个目录的 mtime != 记录值        → 标记 dirty
       （注意：也要能发现【被删除】的目录 → 从索引里移除其条目）
  3. dirty 为空 → 缓存有效，直接使用，结束          ← 常态路径
  4. 只对 dirty 目录：
       - 重新 readDirectory
       - 对新/变更的 .meta 只读前 ~40 行，抽出 guid / importer / mainObjectFileID
       - 覆盖该目录在索引里的全部条目（先删后插）
       更新 dir 表里的 mtime；写回缓存（原子替换）
  5. 全量重建：
       - 遍历 Assets/ 与 Packages/
       - 跳过 Library Temp obj Build Logs .git
       - 每个 .meta 读前 ~40 行
       - 写入 dir 表 + 数据行
       写缓存
```

**正确性依据（已实测验证）**：目录 mtime 在**增/删文件**时变化、**改文件内容**时不变 —— 恰好等于"文件集合是否变化"。

```
建文件 a.txt → mtime 变  ✓
建文件 b.txt → mtime 变  ✓
删文件 b.txt → mtime 变  ✓
改 a.txt 内容 → mtime 不变  ← 文件集合没变，索引不需要重建
```

### 4.4 必须处理的边界

| 边界 | 处理 |
|---|---|
| **mtime 1 秒粒度** | 比较时**取整到秒**。别比毫秒——两个代表同一秒的 `Date` 对象毫秒值可能不同，会误判失效。同一秒内"删了又建"理论上漏检，需接受（可在 `refresh` 里加"目录条目数变化"作为二次信号）。 |
| **符号链接 / junction** | 必须维护"已访问目录"集合，否则循环链接会**死循环**。Windows 上 Unity 工程常见 junction。 |
| **删除的目录** | 遍历时把"缓存里有、磁盘上没有"的目录条目一并清掉，否则索引会留下鬼条目。 |
| **`Packages/`** | 也要索引（内置包/本地包里的资产会被引用）。注意它是只读的，路径前缀与 `Assets/` 不同。 |
| **写入原子性** | 先写 `guidindex.tsv.tmp` 再 `rename` 覆盖。若进程中断，下次读到半截文件要能识别并重建（头行缺失即判定无效）。 |
| **并发** | 两个进程同时写同一缓存会互相覆盖。用 `guidindex.lock` + 短超时重试；拿不到锁就**降级为纯内存索引**（不写盘）而不是报错。 |
| **大工程** | 18,489 资产的 2.10 MB 缓存没问题；若到 50 万资产（按实测 119 字节/行 ≈ 60 MB），改为**只在需要时线性扫描**而非全部载入内存，或按目录分片。 |

---

## 5. API 草案

```haxe
package hxunity.unity;

/** 资产类别。**/
enum abstract AssetKind(String) from String to String
{
	var NativeAsset = "native";   // .mat / .asset / .controller / .anim ...
	var Texture     = "texture";
	var Model       = "model";
	var Prefab      = "prefab";
	var Script      = "script";
	var Text        = "text";
	var Audio       = "audio";
	var Video       = "video";
	var Shader      = "shader";
	var Font        = "font";
	var Folder      = "folder";
	var Plugin      = "plugin";
	var Assembly    = "assembly";
	var Unknown     = "unknown";
}

enum abstract Origin(String) from String to String
{
	var Project = "project";   // Assets/
	var Package = "package";   // Packages/ 或 Library/PackageCache/
	var Builtin = "builtin";   // 不在工程里
}

class AssetEntry
{
	public var guid(default, null):String;
	public var path(default, null):String;      // 相对 projectRoot；内置资源为 null
	public var kind(default, null):AssetKind;
	public var mainId(default, null):Int64;     // 主对象 fileID，可能 null
	public var origin(default, null):Origin;
}

/** 引用解析结果，比 AssetEntry 多一层"能不能解到对象"。**/
class ResolvedReference
{
	public var entry(default, null):AssetEntry;    // 内置/未知时为 null
	public var origin(default, null):Origin;
	public var fileId(default, null):Int64;        // 引用里的 fileID
	public var isMainObject(default, null):Bool;   // fileID == entry.mainId
}

class AssetGuidIndex
{
	public function new(?projectRoot:String);

	// ---- 查询（惰性，不依赖缓存）----
	public function locate(guid:String):AssetEntry;              // guid → 条目
	public function pathOf(guid:String):String;                   // guid → 路径
	public function guidOf(path:String):String;                  // 反向：路径 → guid
	public function entries():Iterator<AssetEntry>;
	public function size():Int;

	// ---- 引用解析（主入口）----
	public function resolve(reference:UnityReference):ResolvedReference;
	public function resolveKind(reference:UnityReference):Origin;   // Local / Builtin / Project / Package / Missing

	// ---- 跨文件 ----
	/** 解析到目标文件里的文档；需要时读目标文件正文（Level 2）。**/
	public function resolveDocument(reference:UnityReference):UnityYamlDocument;
	public function loadAsset(reference:UnityReference):UnityPrefab;

	// ---- 索引构建 ----
	public function scan(root:String, ?options:ScanOptions):Int;   // 显式全量
}

typedef ScanOptions = {
	@:optional var includePackages:Bool;   // 默认 true
	@:optional var skip:Array<String>;     // 额外跳过的目录名
}

/** 持久化层。**/
class CachedGuidIndex
{
	public static function open(projectRoot:String, ?cacheFile:String):CachedGuidIndex;

	/** 6ms 有效性校验；dirty 时增量重扫并写回。返回是否发生了重建。**/
	public function refresh():RefreshResult;

	public function index():AssetGuidIndex;
	public function save():Void;
	public function invalidate():Void;

	/** 从外部索引（例如 Unity 导出的 TSV）载入，作为可选输入源。**/
	public static function loadFrom(path:String):AssetGuidIndex;
}

typedef RefreshResult = {
	var valid:Bool;              // 缓存直接命中
	var rebuilt:Bool;            // 全量重建过
	var rescanedDirs:Array<String>;
	var dirCount:Int;
	var entryCount:Int;
	var elapsedMs:Int;
}
```

### 与现有库的接线点

| 现状 | 接法 |
|---|---|
| `MonoBehaviourObject.resolveClassName(Map<String,String>)` | 保留签名不变（向后兼容）。删掉注释里指向不存在类型的 `[hxunity.unity.AssetGuidIndex]` 引用，或改成指向本文档。 |
| `UnityObject.resolve(key)` | 目前只解**本地**引用。新增重载/新方法：外部引用交给 `AssetGuidIndex.resolveDocument`。 |
| `UnityPrefab` | 加 `public var guidIndex:AssetGuidIndex`（可空）。为空时行为与现在**完全一致**，保证不破坏既有代码。 |
| `UnityReference` | 已有 `isBuiltin` 之类的判断能力（`guid==null` / `type`），但**没有**"全零 guid + type 0 = 内置资源"的判定，需要补一个 `isBuiltinResource()`。 |

---

## 6. 实测数据（本方案的成本依据）

工程：`D:\Project\CATSIM_2`（Unity 2022.3）
规模：**1,408 目录 / ~45,000 目录项 / 22,147 `.meta`（Assets + Packages）/ 22,082 个不同 GUID**

| 操作 | 实测耗时 |
|---|---|
| 遍历全树（只取名字） | 442 ms |
| 读全部 18,489 个 `.meta`（仅 Assets）抽 guid | 822 ms |
| 读全部 `.cs` 抽类名（**本阶段不做**） | 1,709 ms |
| **全量重建索引**（实测，冷，无缓存文件） | **≈ 12,100 ms** |
| **缓存校验 + 无变化**（实测，常态路径） | **≈ 1,700 ms** |
| 命中缓存后查一个 GUID | **0 ms** |
| 缓存文件大小 | **3.79 MB** |

**结论**：

- 全量建索引 ≈ **12 秒**；缓存校验 ≈ **1.7 秒**，约 **7 倍**收益。
- 收益落在**目录数**（1,408）上，而不是资产数（22,082）—— 这正是缓存的价值所在。
- 拿掉类名解析省掉超过一半的构建时间，是本方案最划算的决定。

**⚠️ 实施修正（关于校验成本）**

方案初稿预计校验只要 **6 ms**，依据是"stat 716 个目录用了 6 ms"。这个数字**是错的**，原因有两层：

1. 那 6 ms 是 stat 一批**已经知道路径**的目录，不含"发现这些目录"的成本；而发现目录本身要遍历全树（约 1,500 ms）。
2. 真正的遍历成本不在 `readdir`，而在**对每个目录项调用一次 `isDirectory`**（一次 stat）：44,750 个目录项 × 一次 stat ≈ **730 ms**。

所以正确做法是把目录清单存进缓存（避免第 1 项），并接受第 2 项 —— 校验时确实要列出所有目录。

**⚠️ 实施修正（一个被测试抓住的错误剪枝）**

为了把 1.7 秒压低，实现里曾试过"某目录的子目录名与 mtime 都没变，就跳过它的子树"。这是**不可靠的**：在 `Assets/Art` 里加一个文件不会改动 `Assets`，父目录的状态无法证明子目录没变。测试里"新增文件必须让缓存失效"这条断言立刻失败了，现已改回每次列出所有目录。**这是本方案里最值得记住的一条教训：关于缓存的优化必须有断言兜底。**

**重要提醒**：以上是**文件缓存已热**的数字。冷缓存（刚重启 / 刚 `git clone`）下 I/O 会慢 5–10 倍。

---

## 7. 分阶段实施
| 阶段 | 内容 | 状态 |
|---|---|---|
| **1** | `AssetKind` / `Origin` / `AssetEntry` / `MetaFile`（含 `labels:` 陷阱与嵌套同名键） | ✅ 完成 |
| **2** | `AssetGuidIndex` 惰性模式：`locate` / `pathOf` / `resolve` | ✅ 完成 |
| **3** | `scan()` 全量遍历 + 跳过规则 + symlink 防护 | ✅ 完成 |
| **4** | `CachedGuidIndex`：TSV 读写 + 目录增量 + 原子写 | ✅ 完成 |
| **5** | 内置资源表 + `BuiltinResources` | ✅ 完成（表故意很小） |
| **6** | 跨文件：`loadAsset` / `resolveDocument`（Level 2） | ✅ 完成（内存缓存） |
| **7** | 接线：`UnityPrefab.guidIndex` | ⬜ 未做（`CachedGuidIndex.open` 已可直接用） |

**测试**：`Guid index` 分组共 **64 条断言**，覆盖 `.meta` 解析（含两个陷阱）、内置资源判定、手工索引、引用解析（本地/内置/缺失/命中），以及缓存的完整生命周期（重建 → 命中 → 原地编辑不失效 → 加文件 → 删文件 → 加目录 → 删目录 → 换工程拒绝 → 强制重建）。

---

## 8. 实施后仍未定的事

1. **`Packages/` 已默认索引**（`ScanOptions.includePackages` 默认 true）。只想看 `Assets/` 就传 `false`。
2. **内置资源表只有 1 项**（`10210` = Cube）。其余内置 id 会被识别为 `Origin.Builtin` 并给出 `fileID`，但没有名字。补全需要可靠来源，不靠猜。
3. **`.prefab` 的 `mainId` 为 `null`** —— 预置体是 GameObject 树，没有"主对象"。
4. **缓存默认位置** `<projectRoot>/Library/hxunity-yaml/guidindex.tsv`。`Library` 常被版本控制排除，迁移工程后缓存会丢（只影响速度，不影响正确性）。

---

## 9. 已知风险与实施中踩到的坑

| 风险 | 影响 | 缓解 / 实情 |
|---|---|---|
| **`skip` 按名字跳过构建目录** | **漏掉半个项目** | ⚠️ 真实发生：早期跳过 `build`/`obj`/`temp`，而 `Assets/Art/Build/` 是合法内容目录，索引只有 11,459/22,147。现只跳过 `library`/`logs`/`.git`/`.svn`/`node_modules`。**按名字全局跳过是危险的。** |
| **重扫父目录会清空子孙条目** | **新增目录后其他资产消失** | ⚠️ 真实发生两次。父目录自己没有 `.meta`，清空子树后无人能恢复。现在资产一律**按目录**替换，绝不按子树清空。 |
| **只比较子目录名看不进目录内部** | 新增文件不被索引 | ⚠️ 真实发生。现在每个目录都列出并比较，不因父目录未变而跳过子树。 |
| **相对工程路径** | 路径归属错乱、索引为空 | ⚠️ 真实发生。构造时用 `FileSystem.fullPath` 解析为绝对路径。 |
| 缓存失效误判 | 拿到过期路径 | 直接比较子目录名（不受 1 秒粒度影响）+ mtime 兜底 |
| `.meta` 解析过严 | Unity 改格式后大批失败 | 解析**永不抛错**，退化为 `null` 字段 + 路径仍可用 |
| 多进程写冲突 | 缓存损坏 | 临时文件 + rename 原子替换 |
| Unity 内置表随版本变 | 内置引用解错 | 缓存头记录 `# unity` 版本（当前仅记录，未参与失效判断） |
