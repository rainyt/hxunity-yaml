# hxunity-yaml API 参考

面向 Unity 2022.3 YAML 资产（`.prefab` / `.asset` / `.unity` / `.mat` / `.controller` / `.anim` / `.meta`）的 Haxe 读写库。

设计目标是**保真往返**：文件读入再写出时，除调用方真正改动的内容之外，行尾、BOM、前置指令、字段顺序、引号风格、缩进与折行都保持原样，因此改动在版本控制里只显示真正的差异，而不是整文件重排。

- 仓库：<https://github.com/rainyt/hxunity-yaml>
- 类路径：`src`
- 入口包：`hxunity.yaml`、`hxunity.prefab`、`hxunity.types`、`hxunity.unity`

---

## 目录

1. [安装与编译](#1-安装与编译)
2. [快速开始](#2-快速开始)
3. [选择入口：文档层还是对象层](#3-选择入口文档层还是对象层)
4. [`hxunity.yaml` — YAML 与文档层](#4-hxunityyaml--yaml-与文档层)
5. [`hxunity.prefab` — 对象图编辑](#5-hxunityprefab--对象图编辑)
6. [`hxunity.types` — Unity 值类型](#6-hxunitytypes--unity-值类型)
7. [`hxunity.unity` — id 与引用](#7-hxunityunity--id-与引用)
8. [`ClassIds` — `!u!` 类 id 表](#8-classids--u-类-id-表)
9. [GUID 索引与缓存](#9-guid-索引与缓存)
10. [错误处理](#10-错误处理)
11. [保真格式的保证与边界](#11-保真格式的保证与边界)
12. [常见任务配方](#12-常见任务配方)
13. [构建与测试](#13-构建与测试)
14. [已知限制](#14-已知限制)

---

## 1. 安装与编译

haxelib 安装后 `-cp` 指向库根目录即可：

```hxml
-cp src
```

或按 `haxelib.json` 中的 `classPath` 由 haxelib 自动解析。库本身不依赖任何其它 haxelib 包（`dependencies` 为空），只用 Haxe 标准库。

**目标平台注意事项**

- 64 位 id 一律通过 `haxe.Int64` 承载，从不经过 `Float`。在 JavaScript 目标上 Haxe 的 `Int` 是 double，无法精确表示 `8601872862307532784` 这类 Unity id，因此所有 id 请使用 `FileId` / `UnityReference`，不要手工 `Std.parseInt`。
- `UnityPrefab.save` 与 `UnityDocumentSet.save` 使用 `sys.io.File`，需要 `sys` 目标（neko / hl / cpp / java / cs / python / eval）。纯 JS 目标请改用 `emit()` 自行写出。

---

## 2. 快速开始

### 读取、修改、写回

```haxe
import hxunity.prefab.UnityPrefab;
import hxunity.types.VectorData;

var prefab = UnityPrefab.fromFile("Assets/Hero.prefab");

for (root in prefab.rootGameObjects())
{
	Sys.println(root.name() + "  path=" + root.path());
}

var hand = prefab.findByPath("Player/Hand");
if (hand != null)
{
	hand.setName("LeftHand");
	hand.setActive(false);
	hand.transform().setLocalPosition(new VectorData(0.5, 1, 0));
}

prefab.save();   // 写回原路径
```

### 新建一个 prefab

```haxe
var prefab = UnityPrefab.createEmpty();
var root = prefab.createGameObject("Only");
var child = root.addChild("Nested");
child.addComponent("MeshRenderer");
prefab.save("Assets/New.prefab");
```

### 不落地、纯字符串处理

```haxe
var prefab = UnityPrefab.parse(text);
prefab.find("Child").setName("Renamed");
var out = prefab.emit();
```

---

## 3. 选择入口：文档层还是对象层

| 需求 | 入口 |
|---|---|
| 按层级/名字操作 GameObject、Transform、组件 | `UnityPrefab` |
| 逐字段读写、保留未知字段、处理非 prefab 的资产 | `UnityDocumentSet` + `UnityYamlDocument` |
| 只做语法解析或生成 | `YamlParser` / `YamlWriter` |
| 读写 `.meta`、`fileFormatVersion` 之类的无头文档 | `UnityDocumentSet` |

`UnityPrefab` 内部持有一个 `UnityDocumentSet`，并且**所有修改都直接写穿到底层 YAML 节点**，因此两种入口可以混用：

```haxe
var prefab = UnityPrefab.fromFile(path);
var renderer = prefab.find("Child").getComponent(ClassIds.MeshRenderer);

// 对象层没有专用封装时，直接落到字段层
renderer.set("m_SortingOrder", Scalars.node(99));

// 纯 YAML 层
var doc = prefab.documents.byId(renderer.fileId());
doc.fields().setRaw("m_SortingOrder", "100");
```

---

## 4. `hxunity.yaml` — YAML 与文档层

### 4.1 `UnityDocumentSet`

一个 Unity YAML 文件：`%YAML` / `%TAG` 前置指令 + 若干 `--- !u!` 文档。同时保留行尾风格与前导指令，使未改动的文件逐字节还原。

`.prefab`、`.asset`、`.unity`、`.mat`、`.controller`、`.anim`、`.meta` 都由这一层统一读取 —— 它们只是文档类型不同，文件结构完全一样。

```haxe
class UnityDocumentSet
{
	public var preamble(default, null):Array<String>;          // 文件开头的 % 指令
	public var documents(default, null):Array<UnityYamlDocument>;
	public var lineEnding(default, null):String;               // "\n" 或 "\r\n"
	public var trailingNewline(default, null):Bool;

	public function new(preamble:Array<String> = null, documents:Array<UnityYamlDocument> = null,
		lineEnding:String = "\n", trailingNewline:Bool = true);

	// --- 读取 ---
	public static function parse(text:String, ?options:YamlParseOptions):UnityDocumentSet;

	// --- 查询 ---
	public function count():Int;
	public function at(index:Int):UnityYamlDocument;               // 越界返回 null
	public function firstOfClass(classId:Int):UnityYamlDocument;   // 无匹配返回 null
	public function allOfClass(classId:Int):Array<UnityYamlDocument>;
	public function byId(fileId:Int64):UnityYamlDocument;          // 按锚点 &id 解析引用
	public function byIdText(fileIdText:String):UnityYamlDocument;
	public function contains(fileId:Int64):Bool;

	// --- 结构编辑（会自动维护 id 索引）---
	public function add(document:UnityYamlDocument):UnityYamlDocument;
	public function insert(index:Int, document:UnityYamlDocument):UnityYamlDocument;
	public function remove(document:UnityYamlDocument):Bool;
	public function replace(document:UnityYamlDocument):Void;      // 同 id 替换，否则追加
	public function reindex():Void;                                // 手工改过 fileId 后调用
	public function newFileId():Int64;                             // 未被占用的新 id

	// --- 写出 ---
	public function emit(?options:YamlWriteOptions):String;
	public function save(path:String, ?options:YamlWriteOptions):Void;
}
```

**`parse` 的行为细节**

- 没有 `--- !u!` 头的文件（`.meta`，或手写夹具）也会得到一个文档：`classId == 0`、`hasHeader == false`、`hasFileId == false`，正文原样保留，不会被静默丢弃。
- `preamble` 只收集文件最开头连续的 `%` 行。

**`emit` 的行为细节**

- 前置指令按原顺序输出，随后每个文档的头部，再是缩进为 0 的正文。
- 文档正文写出时强制使用 `\n` 且不带尾随换行，最后由 `lineEnding` / `trailingNewline` 统一决定整个文件的形态 —— 所以 `\r\n` 文件不会被写成 `\n`。

### 4.2 `UnityYamlDocument`

一个 `--- !u!<classId> &<fileId>` 文档，同时继承 `YamlNode`，可直接交给 `YamlWriter`。

```haxe
class UnityYamlDocument extends YamlNode
{
	public var classId(default, null):Int;      // !u! 标签里的 id，无头文档为 0
	public var fileId(default, null):Int64;     // 头部 &锚点
	public var stripped(default, null):Bool;    // `--- !u!114 &1 stripped`
	public var hasFileId(default, null):Bool;
	public var hasHeader(default, null):Bool;
	public var body(default, null):YamlNode;    // 通常是单键 YamlMap，键即类名
	public var bodyName(default, null):String;  // 正文里识别出的类名，或 null
	public var documentLine(default, null):Int; // --- 所在的 1 基行号

	public function new(classId:Int, fileId:Int64, stripped:Bool, body:YamlNode,
		documentLine:Int = 0, hasFileId:Bool = true, hasHeader:Bool = true);

	public function className():String;              // 类名；未知 id 回退到正文键，再回退 "Class<id>"
	public function isGameObject():Bool;             // classId == 1
	public function isTransform():Bool;              // Transform 或 RectTransform
	public function isPrefabInstance():Bool;         // classId == 1001
	public function hasFields():Bool;                // 正文是 YamlMap
	public function fields():YamlMap;                // 正文映射，非映射则抛错

	// 字段直读（键在正文映射里，即顶层类名下的字段）
	public function get(key:String):YamlNode;
	public function set(key:String, value:YamlNode):YamlNode;
	public function getString(key:String):String;
	public function getInt(key:String):Null<Int>;
	public function getFloat(key:String):Null<Float>;
	public function getBool(key:String):Null<Bool>;
	public function getMap(key:String):YamlMap;
	public function getSeq(key:String):YamlSeq;

	public static function classNameOf(classId:Int):String;
}
```

> `bodyName` 只会取**类 id 表里存在**的键。这一步很重要：`.meta` 文件的正文里会有 `PrefabImporter:` 这样的首字母大写键，如果把它当作类名，`className()` 就会报出 `PrefabImporter` 而不是该类 id 应有的 `Document`。

### 4.3 节点体系

三个节点类构成封闭集合：`YamlMap`、`YamlSeq`、`YamlScalar`。基类 `YamlNode` 提供位置、类型名、深比较与调试输出。

```haxe
class YamlNode
{
	public var line(default, null):Int;      // 1 基行号，未知为 0
	public var column(default, null):Int;    // 0 基列号，未知为 -1

	public function isCollection():Bool;
	public function asMap():YamlMap;         // 类型不符时抛带位置的 YamlError
	public function asSeq():YamlSeq;
	public function asScalar():YamlScalar;
	public function isNull():Bool;           // 标量且为空值
	public function toString():String;       // 标量原文；集合返回 ""
	public function typeName():String;
	public function deepEquals(other:YamlNode):Bool;
	public function toHaxe():Dynamic;        // String / Int64 / Float / Bool / Array / Map / null
	public function toJson(indent:Int = 0):String;
}
```

#### `YamlMap`

**有序**映射。内部用数组保存条目，因为 Haxe 的 `Map` 不保证顺序，而字段顺序必须与 Unity 写的一致。

```haxe
class YamlMap extends YamlNode
{
	public var entries(default, null):Array<YamlEntry>;
	public var flow(default, null):Bool;     // 源码里是 `{a: 1}` 这种流式

	public function new(entries:Array<YamlEntry> = null, flow:Bool = false, line:Int = 0, column:Int = -1);

	public function size():Int;
	public function isEmpty():Bool;
	public function indexOf(key:String):Int;               // 无则 -1
	public function has(key:String):Bool;
	public function get(key:String):YamlNode;              // 无则 null
	public function getEntry(key:String):YamlEntry;
	public function set(key:String, value:YamlNode):YamlNode;      // 就地替换，保持原位置
	public function setRaw(key:String, raw:String):YamlNode;       // 只改标量文本，位置与引号不变
	public function add(key:String, value:YamlNode):YamlNode;      // 追加，不查重
	public function remove(key:String):YamlNode;

	public function getString(key:String):String;
	public function getInt64(key:String):Int64;
	public function getInt(key:String):Null<Int>;
	public function getFloat(key:String):Null<Float>;
	public function getBool(key:String):Null<Bool>;
	public function getMap(key:String):YamlMap;
	public function getSeq(key:String):YamlSeq;

	public static function of(pairs:Array<{key:String, value:Dynamic}>):YamlMap;
}
```

> `getString` 对标量返回**未经解释的原文**（`"0"`、`"1.5"` 而非 `0` / `1.5`）；`getInt` / `getFloat` / `getBool` 才做解释。集合键返回 `null`。

#### `YamlSeq`

```haxe
class YamlSeq extends YamlNode
{
	public var items(default, null):Array<YamlNode>;
	public var flow(default, null):Bool;      // 源码里是 `[a, b]`

	public function new(items:Array<YamlNode> = null, flow:Bool = false, line:Int = 0, column:Int = -1);

	public function length():Int;
	public function isEmpty():Bool;
	public function get(index:Int):YamlNode;         // 越界返回 null
	public function push(item:YamlNode):YamlNode;
	public function removeAt(index:Int):YamlNode;
	public function removeItem(item:YamlNode):Bool;  // 按引用相等删除
	public function toStrings():Array<String>;       // 每项取原文

	public static function of(values:Array<Dynamic>):YamlSeq;
}
```

#### `YamlScalar`

```haxe
class YamlScalar extends YamlNode
{
	public var raw(default, null):String;     // 原文，不含引号、不含块标量头
	public var kind(default, null):ScalarKind;
	public var tag(default, null):String;     // `!u!114` 之类的显式标签
	public var anchor(default, null):String;

	public function new(raw:String, kind:ScalarKind = Plain, line:Int = 0, column:Int = -1,
		tag:String = null, anchor:String = null);

	public function setRaw(raw:String):Void;  // 只改文本，保留引号风格
	public function isPlain():Bool;
	public function isQuoted():Bool;
	public function toBool():Bool;            // 非布尔关键字则抛错
	public function toInt():Int;              // 非 32 位整数则抛错
	public function toFloat():Float;
	public function toInt64():Int64;          // fileID 请用这个
}
```

`ScalarKind` 是字符串枚举：

| 值 | 字面 | 含义 |
|---|---|---|
| `Plain` | `"plain"` | 无引号，如 `m_Name: alex_fat` |
| `SingleQuoted` | `"single"` | 单引号 |
| `DoubleQuoted` | `"double"` | 双引号（含转义） |
| `Literal` | `"literal"` | 块标量 `\|` |
| `Folded` | `"folded"` | 块标量 `>` |

引号风格必须保留：Unity 用 `type: 2`（整数）和 `"2"`（字符串）区分类型，丢掉引号信息就无法逐字节往返。

#### `YamlEntry`

```haxe
class YamlEntry
{
	public var key:String;
	public var value:YamlNode;
	public var line:Int;
	public function new(key:String, value:YamlNode, line:Int = 0);
}
```

### 4.4 `YamlParser` / `YamlWriter`

```haxe
class YamlParser
{
	// 解析单个文档正文，返回最后一个文档的 body
	public static function parse(text:String, ?options:YamlParseOptions):YamlNode;
	// 解析全部 `--- !u!` 文档
	public static function parseAll(text:String, ?options:YamlParseOptions):Array<UnityYamlDocument>;
}

class YamlWriter
{
	public static function write(node:YamlNode, ?options:YamlWriteOptions):String;

	public function new(?options:YamlWriteOptions);
	public function writeNode(node:YamlNode, indent:Int):Void;
	public function finish():String;

	public static function writeJsonString(sb:StringBuf, text:String):Void;
}
```

解析器对缩进宽度是宽容的（块结构由 token 流里的缩进值推导，不假定 2 空格），但不容忍结构性错误，例如 `---` 头缺少 `!u!` 类 id —— 会抛出带行号的 `YamlError`。嵌套深度上限 512。

输出器尽量贴近 Unity 2022.3 的写法：

- 映射与序列为块风格，缩进 2 空格；
- 序列的 `-` 与拥有它的键同级缩进；
- 节点记住自己是流式（`{fileID: 0}`）就按流式输出；
- 流式集合按 Unity 的真实规则折行：每写完一个逗号，若它落在第 80 列之后就换行；续行缩进 = 所属键起始列 + 2（最少 4 空格）。因此 key 在 2 的 `m_CorrespondingSourceObject` 折到 4、`- target:`（dash 缩进 4，键在 6）折到 8，整行不超过 89 列的引用保持单行；
- 引号标量按解析时记下的原文逐字重现（`\uXXXX` 转义的大小写、折行位置都保留）；程序化构造的值用 `Scalars.ofString` 决定是否加引号；
- 双引号标量重新编码时非 ASCII 一律 `\uXXXX`（小写十六进制），与 Unity 一致。

### 4.5 选项

```haxe
typedef YamlParseOptions = {
	@:optional var keepCarriageReturns:Bool;   // 保留 \r\n 的影响（只影响位置信息与 BOM 处理）
	@:optional var rejectDuplicateKeys:Bool;   // 默认 false：重复键两个都留
	@:optional var trackPositions:Bool;        // 在每个节点上记录行列
	@:optional var resolveAliases:Bool;        // 解析 &anchor / *alias，默认 false
}

typedef YamlWriteOptions = {
	@:optional var indentStep:Int;        // 默认 2
	@:optional var flowLineWidth:Int;     // 引号标量的折行宽度，默认 100，0 表示不折行
	@:optional var flowWrapColumn:Int;    // 流式集合逗号折行列，默认 80，0 表示不折行
	@:optional var lineEnding:String;     // 默认 "\n"
	@:optional var trailingNewline:Bool;  // 默认 true
}
```

### 4.6 辅助类

```haxe
class Scalars
{
	public static function toBool(text:String):Bool;                 // 非布尔则抛错
	public static function tryBool(text:String):Null<Bool>;         // true/false/yes/no/on/off/y/n 及 1/0
	public static function isQuoted(text:String):Bool;
	public static function isNumber(text:String):Bool;              // 接受 0 / -0 / 1.5 / .5 / 1e-05，拒绝 10f
	public static function isInteger(text:String):Bool;
	public static function tryInt(text:String):Null<Int>;           // 超 32 位返回 null（不依赖目标行为）
	public static function tryInt64(text:String):Null<Int64>;       // id 请用这个
	public static function tryFloat(text:String):Null<Float>;
	public static function isNullText(text:String):Bool;            // "" / ~ / null / Null / NULL
	public static function toHaxe(text:String):Dynamic;
	public static function node(value:Dynamic):YamlNode;            // null/String/Bool/Int/Float → 标量
	public static function ofString(text:String):YamlScalar;        // 需要时自动加单引号
	public static function needsQuoting(text:String):Bool;
}

class Strings
{
	public static function spaces(count:Int):String;
	public static function indentRest(text:String, indent:Int):String;
	public static function splitLines(text:String):Array<String>;   // 处理 \n、\r\n、孤立 \r
	public static function detectLineEnding(text:String):String;
	public static inline function int64(value:Int64):String;
}
```

> `Scalars.node` 不能接收 `haxe.Int64`：抽象类型在运行时没有类型信息，无法分派；而 `Float` 又存不下完整的 64 位 id。请用 `FileId.toStr(id)` 转成字符串再传入。

### 4.7 词法层（一般不需要直接用）

```haxe
class YamlLexer
{
	public var line(default, null):Int;
	public var column(default, null):Int;
	public function new(text:String);
	public function next():YamlToken;    // 输入耗尽后返回 Eof
}

enum YamlTokenType
{
	DocStart; BareDocStart; DocEnd; Directive; Key; Dash;
	FlowSeqStart; FlowSeqEnd; FlowMapStart; FlowMapEnd; Comma; Scalar; Eof;
}
```

词法器是行导向的，但显式处理几种跨行形态：折行的流式集合、跨多行的引号标量（`_serializedGraph` 那类值），以及块上下文里折行的多行纯文本标量（Odin 配置里过长的程序集名，换行折叠回一个空格）。行首的引号键（插件 importer `platformData` 里的 `''`）同样按键解析。

---

## 5. `hxunity.prefab` — 对象图编辑

### 5.1 `UnityPrefab`

在 `UnityDocumentSet` 之上加一层对象图，可以按名字而不是 `fileID` 遍历层级。

```haxe
class UnityPrefab
{
	public var documents(default, null):UnityDocumentSet;
	public var path(default, null):String;                  // 从文本解析时为 null
	public var parseOptions(default, null):YamlParseOptions;
	public var writeOptions(default, null):YamlWriteOptions;

	public function new(documents:UnityDocumentSet, ?path:String,
		?parseOptions:YamlParseOptions, ?writeOptions:YamlWriteOptions);

	// --- 构造 ---
	public static function parse(text:String, ?options:YamlParseOptions):UnityPrefab;
	public static function fromFile(path:String, ?options:YamlParseOptions):UnityPrefab;
	public static function createEmpty():UnityPrefab;        // 带标准 %YAML / %TAG 前导

	// --- 查询 ---
	public function reindex():Void;
	public function gameObjectById(fileId:Int64):GameObjectObject;
	public function componentById(fileId:Int64):Component;
	public function allGameObjects():Array<GameObjectObject>;
	public function rootGameObjects():Array<GameObjectObject>;   // transform 无父者
	public function find(name:String):GameObjectObject;          // 首个同名，无则 null
	public function findByPath(path:String):GameObjectObject;    // 层级路径，如 "Player/Hand"
	public function findAll(name:String):Array<GameObjectObject>;
	public function allComponentsOfType(classId:Int):Array<Component>;
	public function firstDocumentOfClass(classId:Int):UnityYamlDocument;

	// --- 结构编辑 ---
	public function createGameObject(name:String, ?parent:GameObjectObject, ?fileId:Int64):GameObjectObject;
	public function duplicate(source:GameObjectObject, ?newParent:GameObjectObject):GameObjectObject;
	public function removeObject(object:UnityObject):Void;
	public function removeDocument(document:UnityYamlDocument):Void;
	public function addDocument(document:UnityYamlDocument):UnityYamlDocument;
	public function indexOfDocument(document:UnityYamlDocument):Int;

	// --- 写出 ---
	public function emit(?options:YamlWriteOptions):String;
	public function save(?path:String, ?options:YamlWriteOptions):Void;   // 省略 path 则用加载路径
	public function count():Int;
}
```

**`duplicate` 的引用重写规则**

复制整棵子树时，每个文档都会分到新的 file id，只有指向**子树内部**的本地 `{fileID: N}` 引用会被改写；指向子树之外的引用（父对象、材质、脚本等其它资产）保持不动。带 `guid` 的引用永远指向别的资产，因此跳过。这正是"复制出来的对象不再与原对象共享内部结构，但仍共用同一份资产"的效果。

### 5.2 `UnityObject`（基类）

所有被封装的 Unity 对象的基类。任何访问器都直接读写文档的字段映射，所以**即使库里没有专用封装，任何 Unity 序列化字段依然可读写**。

```haxe
class UnityObject
{
	public var document(default, null):UnityYamlDocument;
	public var prefab(default, null):UnityPrefab;

	public function classId():Int;
	public function className():String;
	public function fileId():Int64;
	public function isStripped():Bool;
	public function fields():YamlMap;          // 从单键正文里展开出的字段映射

	public function get(key:String):YamlNode;
	public function set(key:String, value:YamlNode):YamlNode;
	public function getString(key:String):String;
	public function getInt(key:String):Null<Int>;
	public function getFloat(key:String):Null<Float>;
	public function getBool(key:String):Null<Bool>;
	public function getMap(key:String):YamlMap;
	public function getSeq(key:String):YamlSeq;
	public function getReference(key:String):UnityReference;   // 字段缺失为 null；{fileID: 0} 的 isNone() 为 true
	public function removeField(key:String):YamlNode;
	public function hasField(key:String):Bool;
	public function objectHideFlags():Null<Int>;
	public function resolve(key:String):UnityYamlDocument;     // 解析指向本地文档的引用字段
}
```

> `getReference` 与 `resolve` 的区别：前者返回引用对象本身（本地/外部/空都能区分），后者只在引用指向**本文件内**的文档时返回该文档，外部引用返回 `null`。

### 5.3 `GameObjectObject`

```haxe
class GameObjectObject extends UnityObject
{
	// 基本字段
	public function name():String;
	public function setName(value:String):Void;
	public function active():Bool;                     // m_IsActive，缺失时默认 true
	public function setActive(value:Bool):Void;
	public function tag():String;
	public function setTag(value:String):Void;
	public function layer():Null<Int>;
	public function setLayer(value:Int):Void;

	// 组件
	public function componentReferences():YamlSeq;     // m_Component 原始序列
	public function components():Array<Component>;     // 按序列化顺序，Transform 通常在最前
	public function getComponent(classId:Int):Component;
	public function getComponents(classId:Int):Array<Component>;
	public function transform():TransformObject;       // Transform 或 RectTransform，无则 null
	public function addComponent(className:String):Component;          // 未知类名抛错
	public function addComponentOfClass(classId:Int, ?fileId:Int64):Component;

	// 层级
	public function parent():GameObjectObject;
	public function children():Array<GameObjectObject>;
	public function descendants():Array<GameObjectObject>;   // 深度优先，不含自身
	public function depth():Int;                             // 根为 0
	public function path():String;                           // "Player/Hand/Bone"
	public function find(name:String):GameObjectObject;      // 含自身
	public function findAll(name:String):Array<GameObjectObject>;
	public function addChild(name:String):GameObjectObject;
	public function setParent(newParent:GameObjectObject):Void;   // null 表示移到根
	public function remove():Void;                                // 连同子孙一并移除
}
```

层级本身不存在 GameObject 上：每个 GameObject 拥有一个 Transform，父子关系在 Transform 的 `m_Father` / `m_Children` 里。本类跟随这些引用，调用方不必接触 `fileID`。

`addComponent` 会新建组件文档、分配新 id、写进 `m_Component`，并在 Transform 之后插入（Unity 把 Transform 排在首位）。Behaviour 子类会自动带上 `m_Enabled: 1`。

### 5.4 `Component`

```haxe
class Component extends UnityObject
{
	public static function create(document:UnityYamlDocument, prefab:UnityPrefab):Component;
	public function gameObject():GameObjectObject;      // 无归属则为 null
	public function gameObjectId();                     // 本地 fileID，无归属为 null
	public function enabled():Null<Bool>;               // m_Enabled，不序列化该字段的组件返回 null
	public function setEnabled(value:Bool):Void;
	public function remove():Void;                      // 从 m_Component 摘除并删除文档
}
```

### 5.5 `TransformObject`

```haxe
class TransformObject extends Component
{
	public function localPosition():VectorData;
	public function setLocalPosition(value:VectorData):Void;
	public function localScale():VectorData;
	public function setLocalScale(value:VectorData):Void;
	public function localRotation():QuaternionData;
	public function setLocalRotation(value:QuaternionData):Void;
	public function localEulerAnglesHint():VectorData;    // 仅编辑器提示，Unity 由 m_LocalRotation 重算
	public function setLocalEulerAnglesHint(value:VectorData):Void;

	public function parentTransform():TransformObject;
	public function parent():GameObjectObject;
	public function childTransforms():Array<TransformObject>;
	public function children():Array<GameObjectObject>;
	public function siblingIndex():Int;                   // 根对象为 -1
	public function setParent(newParent:GameObjectObject):Void;   // 同步两端链接；null 移到根
	public function detachFromParent():Void;
	public function setSiblingIndex(index:Int):Void;      // m_Children 顺序决定绘制顺序
}
```

`setParent` 同时更新本对象的 `m_Father` 与新旧父对象的 `m_Children`，本地位置与缩放不动 —— 对应 Unity 的 `SetParent(parent, false)`。

> **`parentTransform()` 与 `parent()` 语义不同，判断"是否为根"请用 `parent()`。**
>
> `m_Father` 可能指向一个 **stripped transform** —— 这是 Unity 为 prefab 实例的父级写出的形态：文档确实存在、也在索引里，但它没有 `m_GameObject`（真正的属主在源 prefab 里）。此时：
>
> - `parentTransform()` 返回**非 null** 的包装（文档是真的）；
> - 但 `parentTransform().gameObject()` 是 `null`；
> - `parent()` 返回 `null`。
>
> 所以 `parentTransform() != null` **不能**用来判断"这个对象有父级"。用 `parentTransform() == null` 做根判断会让这类对象同时从父列表和根列表里消失，只剩 `allGameObjects()` 能找到它。`UnityPrefab.rootGameObjects()` 内部用的就是 `transform.parent() == null`。
>
> 另外 `parentTransform()` 与 `childTransforms()` 都会校验解析出的文档**确实是 Transform / RectTransform**，避免手工改坏文件时把别的类误包装成 Transform。

### 5.6 `MonoBehaviourObject`

```haxe
class MonoBehaviourObject extends Component
{
	public function scriptReference():UnityReference;     // m_Script
	public function scriptGuid():String;                  // 脚本资产 GUID
	public function editorClassIdentifier():String;       // m_EditorClassIdentifier
	public function ownClassName():String;                // m_ClassName / m_Type，通常为 null
	public function resolveClassName(scriptGuids:Map<String, String>):String;
	public function assignScript(guid:String, fileId:haxe.Int64):Void;
}
```

脚本存在项目里而不在这个文件里，因此把 GUID 解析成 C# 类名需要调用方提供 `GUID → 类名` 的映射表（自行从项目的 `MonoScript` 资产与 `.meta` 文件构建）。prefab 没在编辑器里打开过时，`m_EditorClassIdentifier` 常为空。

`assignScript` 会清空 `m_EditorClassIdentifier`、`m_ClassName`、`m_Namespace` —— 留着旧值会让 Unity 在组件重新导入前一直显示旧脚本名。

### 5.7 `.unity` 场景

**场景可以直接用同一套 API 读写**，不需要单独的入口。`.unity` 与 `.prefab` 的文件结构完全一样，只是文档构成不同：

| | `.prefab` | `.unity` |
|---|---|---|
| 设置类文档 | 无 | `OcclusionCullingSettings`(29)、`RenderSettings`(104)、`LightmapSettings`(157)、`NavMeshSettings`(196) 等 |
| 根对象列表 | 无（由 Transform 推导） | `SceneRoots`(1660057539) 的 `m_Roots` |
| 层级 | `Transform.m_Father` / `m_Children` | 完全相同 |
| 根对象数量 | 通常 1 | 每个根对象一个 |

已验证的行为：

- 设置类文档照常读入，不影响 GameObject 遍历（`!u!29` / `!u!104` / `!u!157` 都能正确取到类名）；
- `rootGameObjects()` 在多根场景里返回多个根（不会把设置文档或子对象误算成根）；
- 场景里的 `Camera` 等组件与预置体一样可读可写；
- 未修改的场景逐字节往返；
- **新建根对象会自动登记进 `SceneRoots.m_Roots`**（否则 Unity 下次保存时会把它丢掉），挂在父节点下的对象不会；
- **删除场景根对象会自动从 `m_Roots` 摘除**，避免场景引用已删除的对象。

> **`m_Roots` 里存的是 Transform 的 fileID，不是 GameObject 的。** 两者是不同的文档、不同的 id，混用会让 Unity 找不到根对象（而且从 YAML 上很难一眼看出来）。本库内部已按 Transform id 登记。

```haxe
var scene = UnityPrefab.fromFile("Assets/Scenes/Main.unity");
for (root in scene.rootGameObjects()) Sys.println(root.name());

var spawned = scene.createGameObject("Spawned");   // 自动加入 SceneRoots
spawned.remove();                                  // 自动从 SceneRoots 摘除
scene.save();
```

> **`SceneRoots` 只是清单，不是层级的来源。** 真正的父子关系仍然只存在 `Transform` 里，`rootGameObjects()` 也是按 Transform 推导的。`m_Roots` 的作用是告诉 Unity"哪些对象是场景根"，两者必须保持一致。本库在 `createGameObject` / `remove` 里已自动同步；但如果你用 `documents.remove(...)` 这类底层接口直接删文档，就需要自己维护该列表。

> **不支持多场景合并视图**：一次只能读一个 `.unity`。如果对象跨场景引用（`{fileID: N}` 指向另一个场景的对象），那是无效引用，请按 `UnityReference.isExternal()` 的思路分别处理。

### 5.8 预制体实例（PrefabInstance）

场景里的预制体不是完整层级：`.unity` 只保存 `PrefabInstance`（classId 1001）文档
—— `m_SourcePrefab` 指向源资产 guid、`m_Modifications` 是实例覆盖、`m_TransformParent`
是挂载点 —— 外加实例根的 **stripped** 占位文档（`--- !u!4 &N stripped`，通过
`m_PrefabInstance` 指回实例）。完整结构只在 `.prefab` 文件里，`PrefabInstance`
把它组装起来：

```haxe
import hxunity.prefab.PrefabInstance;
import hxunity.prefab.UnityPrefab;
import hxunity.unity.CachedGuidIndex;

var cache = CachedGuidIndex.open(projectRoot);
cache.refresh();

var scene = UnityPrefab.fromFile(scenePath);
for (instance in PrefabInstance.list(scene, cache.index))
{
	// 完整结构：源预制体 + 全部覆盖已应用（内存视图，不写任何文件）
	var root = instance.rootGameObject();
	trace(root.name() + " <- " + instance.sourcePath() + ", 覆盖 " + instance.modificationCount() + " 条");

	// 场景层级里的位置
	var slot = instance.instanceTransform();     // stripped Transform 文档
	var parent = instance.parentGameObject();    // m_TransformParent 解析（父级是
	                                             // 另一实例的 stripped 时为 null）
}
```

覆盖管理（对应 Unity 的实例改动 —— 只写场景的 `m_Modifications`，绝不把预制体
内容展开进 `.unity`，否则 PrefabInstance 关系会永久丢失）：

```haxe
instance.setOverride(targetFileId, "m_Name", "Hero_Renamed");            // 标量覆盖，重复写入就地更新
instance.setObjectReferenceOverride(targetFileId, "m_Father",
	UnityReference.none().toNode());                                     // 引用覆盖，{fileID: 0} = 置空
instance.removeOverride(targetFileId, "m_LocalPosition.x");              // Revert 单项
instance.clearOverrides();                                               // Revert 全部
```

写回场景文件用 `scene.save()`。`applyToPrefab()` 对应编辑器的 Apply —— 覆盖写进
`.prefab` 文件并保存，场景里的覆盖保留（与 Unity 文件格式一致，编辑器只在刷新时
清理已一致条目）。指向**场景对象**的引用覆盖无法进入预制体，会被跳过并计入
`ApplyResult.skippedSceneReferences`。

属性路径引擎 [PropertyPath] 支持 `m_Name`、`m_LocalPosition.x`、
`AnimateDatas.Array.data[1].ChildTargetDatas.Array.data[5].Target` 这类 Unity 记法
（`Array.data[N]` 对应 YAML 数组第 N 项，越界时按 Unity 反序列化器行为扩容）。

嵌套预制体不在 `effectivePrefab()` 里自动展开：克隆里保留其 PrefabInstance 文档，
对克隆再跑一次 `PrefabInstance.list(clone, index)` 即可逐层取完整结构。

**共享缓存与克隆**：`effectivePrefab()` 用 `UnityPrefab.deepClone()`（节点树深拷贝，
不经序列化往返，标量原文逐字保留）而不是 emit→reparse，在 JS 目标上实测快约 5 倍。
`PrefabInstance.list(scene, index, cache)` 的第三个参数传 [PrefabSourceCache] 可跨
调用共享源预制体（按 guid + 文件 mtime 判定有效性，`applyToPrefab` 写回后自动刷新；
105 实例的场景只按唯一 guid 数量读盘）。缓存返回的是共享图，不得修改；跨多场景复用
时显式传入同一实例即可。

---

## 6. `hxunity.types` — Unity 值类型

### 6.1 `VectorData`（Vector2 / Vector3 / Vector4）

```haxe
class VectorData
{
	public var x:Float;
	public var y:Float;
	public var z:Null<Float>;
	public var w:Null<Float>;
	public var hasZ(default, null):Bool;    // 源里是否有 z
	public var hasW(default, null):Bool;

	public function new(x:Float = 0, y:Float = 0, z:Null<Float> = null, w:Null<Float> = null);

	public static function fromNode(node:YamlNode):VectorData;
	public static function fromField(fields:YamlMap, key:String):VectorData;   // 字段缺失返回 null
	public function toNode():YamlMap;
	public function writeTo(fields:YamlMap, key:String):Void;
	public function clone():VectorData;
}
```

Unity 用流式映射写这些值：`m_LocalPosition: {x: 0, y: -1.932, z: 0}`。`z` / `w` 是可选的，所以一个类能同时覆盖三种宽度。`hasZ` / `hasW` 记录源里是否真的出现过对应键 —— Vector2 读写往返后不会多出一个 `z: 0`。

### 6.2 `QuaternionData`

```haxe
class QuaternionData
{
	public var x:Float; public var y:Float; public var z:Float; public var w:Float;
	public function new(x:Float = 0, y:Float = 0, z:Float = 0, w:Float = 1);
	public static function fromNode(node:YamlNode):QuaternionData;
	public static function fromField(fields:YamlMap, key:String):QuaternionData;
	public function toNode():YamlMap;
}
```

按 `x, y, z, w` 顺序输出，与 Unity 一致。

### 6.3 `ColorData`

```haxe
class ColorData
{
	public var r:Float; public var g:Float; public var b:Float; public var a:Float;
	public function new(r:Float = 0, g:Float = 0, b:Float = 0, a:Float = 1);
	public static function fromNode(node:YamlNode):ColorData;
	public static function fromField(fields:YamlMap, key:String):ColorData;
	public static function fromHex(hex:String):ColorData;    // "#RRGGBB" 或 "#RRGGBBAA"
	public function toNode():YamlMap;                        // {r:, g:, b:, a:}
	public function toHex():String;                          // "#RRGGBBAA"
}
```

`Color` 与 `Color32` 的序列化形状相同（`Color32` 也按归一化浮点写），所以不需要区分。

### 6.4 `Numbers`

```haxe
class Numbers
{
	public static function format(value:Float):String;
	public static function isNegativeZero(value:Float):Bool;
}
```

对齐 Unity 的写法：整数不带小数部分（`1` 而不是 `1.0`）；`-0` 保留（Unity 大量写 `-0`，丢掉会让 diff 显示改动）；指数记法展开（`1e-005` → `0.00001`）。

---

## 7. `hxunity.unity` — id 与引用

### 7.1 `FileId`

Unity 对象 id 是**有符号 64 位**随机值，很容易超过 `2^53`（JS `Number` 与 JS 目标上 Haxe `Int` 能精确表示的上限）。本库所有 id 都用 `haxe.Int64` 承载。

```haxe
class FileId
{
	public static var NONE:Int64;
	public static function parse(text:String):Int64;             // 非整数返回 null
	public static function ofString(text:String):Int64;          // 非整数抛错
	public static function toStr(id:Int64):String;               // null → "0"
	public static function toNullableStr(id:Int64):String;       // null → null
	public static function zeroId():Int64;
	public static function isNone(id:Int64):Bool;                // null 或 0
	public static function fitsInt(id:Int64):Bool;
	public static function compare(a:Int64, b:Int64):Int;        // null/0 排最前，然后按数值
}
```

> 别把 id 当文本排序：`-1` 排在 `-10` 前面、`9` 排在 `10` 后面。用 `FileId.compare`。

### 7.2 `UnityReference`

Unity 序列化引用的形状：

```yaml
m_Script: {fileID: 11500000, guid: d247ba06193faa74d9335f5481b2b56c, type: 3}
m_Father: {fileID: 0}
```

```haxe
class UnityReference
{
	public static inline var TYPE_LOCAL = -1;     // 无 type：指向本文件
	public static inline var TYPE_BUILTIN = 0;    // type: 0，Unity 内置资源
	public static inline var TYPE_ASSET = 2;      // type: 2，导入资产（贴图等）内部的对象
	public static inline var TYPE_PROJECT = 3;    // type: 3，项目资产（脚本等）内部的对象

	public var fileId(default, null):Int64;
	public var guid(default, null):String;       // null 表示本地引用
	public var type(default, null):Int;

	public function new(fileId:Int64, guid:String, type:Int);

	public function isLocal():Bool;               // guid == null
	public function isExternal():Bool;            // guid != null
	public function isNone():Bool;                // {fileID: 0}

	public static function fromNode(node:YamlNode):UnityReference;   // 非映射返回 null；坏 fileID 抛错
	public function toNode():YamlMap;                                 // 字段顺序 fileID, guid, type
	public static function local(fileId:Int64):UnityReference;
	public static function asset(guid:String, fileId:Int64, type:Int):UnityReference;
	public static function none():UnityReference;                     // {fileID: 0}
	public function equals(other:UnityReference):Bool;                // 忽略 type 差异
}
```

三个字段含义不同：`fileID` 标识对象（无 `guid` 时是**本文件内**的 id，有 `guid` 时是**另一个资产内**的 id）；`guid` 是目标 `.meta` 里的资产 GUID；`type` 描述引用如何解析 —— 注意它与文档头里的 `!u!` 类 id **不是一回事**。

---

## 8. `ClassIds` — `!u!` 类 id 表

```haxe
class ClassIds
{
	// 122 个常量，覆盖 Unity 2022.3 能写进 .prefab/.asset/.unity/.controller/.mat 的全部 id
	public static inline var GameObject = 1;
	public static inline var Transform = 4;
	public static inline var Camera = 20;
	public static inline var MeshRenderer = 23;
	public static inline var MonoBehaviour = 114;
	public static inline var RectTransform = 224;
	public static inline var PrefabInstance = 1001;
	// ...

	public static var names(default, null):Map<Int, String>;
	public static function name(classId:Int):String;        // 未知返回 null
	public static function id(className:String):Int;        // 未知返回 -1
	public static function isComponent(classId:Int):Bool;   // 会出现在 m_Component 里的对象
	public static function isBehaviour(classId:Int):Bool;   // 派生自 Behaviour，序列化 m_Enabled
}
```

常用 id 摘录：

| id | 名称 | id | 名称 |
|---|---|---|---|
| 1 | GameObject | 114 | MonoBehaviour |
| 2 | Component | 115 | MonoScript |
| 4 | Transform | 119 | Projector |
| 20 | Camera | 120 | LineRenderer |
| 21 | Material | 199 | ParticleSystemRenderer |
| 23 | MeshRenderer | 212 | SpriteRenderer |
| 33 | MeshFilter | 213 | Sprite |
| 54 | Rigidbody | 222 | CanvasRenderer |
| 65 | BoxCollider | 223 | Canvas |
| 95 | Animator | 224 | RectTransform |
| 108 | Light | 225 | CanvasGroup |
| 111 | ShaderVariantCollection | 1001 | PrefabInstance |
| — | — | 1660057539 | SceneRoots（合成 id） |

`isComponent` 里 `Transform` 与 `RectTransform` 算组件 —— Unity 把 transform 排在 `m_Component` 首位，遍历组件的人会期望看到它；而 `GameObject`、`PrefabInstance` 与合成的 `SceneRoots` 不算，它们是组件的拥有者或引用者。

完整 id 表请直接看 `src/hxunity/yaml/ClassIds.hx`，或对照 Unity 官方的 [YAML Class ID Reference](https://docs.unity3d.com/Manual/ClassIDReference.html)。

---

## 9. GUID 索引与缓存

序列化引用用 GUID 而不是路径指向别的资产（`{fileID: 2100000, guid: 506c261d..., type: 2}`），所以要知道"这个材质是哪个文件"就需要一份**全工程 GUID → 资产**的索引。这一层在 `hxunity.unity` 下，共 12 个类。

详细设计与实测数据见 [GUID-INDEX.md](GUID-INDEX.md)。本节只是 API 速查。

### 9.1 `AssetGuidIndex`

```haxe
class AssetGuidIndex
{
	public var projectRoot(default, null):String;   // 构造时解析为绝对路径

	public function new(?projectRoot:String);

	// --- 填充 ---
	public function scan(root:String, ?options:ScanOptions):Int;        // 全量遍历，返回索引数
	public function scanDirectory(directory:String):Array<String>;      // 重读一个目录，返回其 GUID
	public function add(entry:AssetEntry):AssetEntry;
	public function addEntry(guid:String, path:String, kind:AssetKind, origin:Origin,
		?mainId:Int64, ?importer:String):AssetEntry;
	public function remove(guid:String):Bool;
	public function removeDirectory(directory:String):Int;
	public function invalidate():Void;                                  // 丢弃惰性查找缓存

	// --- 查询 ---
	public function size():Int;
	public function locate(guid:String):AssetEntry;      // 索引未命中时会走一遍工程找 .meta
	public function pathOf(guid:String):String;          // 相对 projectRoot
	public function absolutePathOf(guid:String):String;
	public function guidOf(path:String):String;          // 反向
	public function entries():Iterator<AssetEntry>;
	public function countOfKind(kind:AssetKind):Int;

	// --- 解析引用 ---
	public function resolve(reference:UnityReference):ResolvedReference;
	public function resolveOrigin(reference:UnityReference):Origin;
	public function isResolvableToFile(reference:UnityReference):Bool;

	// --- 跨文件（Level 2，按需读目标文件）---
	public function loadAsset(reference:UnityReference):UnityPrefab;
	public function documentSetOf(reference:UnityReference):UnityDocumentSet;
	public function resolveDocument(reference:UnityReference):UnityYamlDocument;
}
```

**两层设计**：Level 1 是索引本身（每个资产一条，来自 `.meta`），回答"哪个文件"和"什么类型"；Level 2 才去读资产正文，回答"这个 `fileID` 在文件里是哪个对象"。绝大多数场景 Level 1 就够。

**惰性模式**：不调 `scan` 也能用。`locate(guid)` 会遍历工程找到对应 `.meta`，结果进内存缓存；**未命中也会被记住**，避免每次重复走一遍。实测在 22,000 资产的工程上，首次查找约 3.7 秒，重复查找 0 毫秒。批量场景请用缓存。

### 9.2 `AssetEntry` / `AssetKind` / `Origin`

```haxe
class AssetEntry
{
	public var guid:String;        // 小写 32 位
	public var path:String;        // 相对 projectRoot，正斜杠；内置资源为 null
	public var kind:AssetKind;
	public var mainId:Int64;       // 主对象 fileID，可能为 null
	public var origin:Origin;
	public var importer:String;    // .meta 里的 importer 段名
	public function fileName():String;
	public function extension():String;
}

enum abstract AssetKind(String)
{
	var NativeAsset;  // .mat / .asset / .controller / .anim ...
	var Texture; var Model; var Prefab; var Script; var Text;
	var Audio; var Video; var Shader; var Font; var Folder;
	var Plugin; var Unknown;
	public static function parse(text:String):AssetKind;
	public function isUnitySerialised():Bool;
}

enum abstract Origin(String)
{
	var Project;   // Assets/
	var Package;   // Packages/ 或 Library/PackageCache/
	var Builtin;   // 引擎内置，无文件
	var Local;     // 无 guid，指向本文件
	var Missing;
	public function isOnDisk():Bool;
}
```

`AssetKind` 由 **importer 段名 + 扩展名**共同推导 —— `NativeFormatImporter` 同时覆盖 `.mat` / `.asset` / `.controller` / `.anim`，只有扩展名能区分。

`mainId` 优先取 `.meta` 里的 `mainObjectFileID`（**只有 `NativeFormatImporter` 会写这个字段**），取不到再按扩展名/导入器推导。预置体没有"主对象"（它是 GameObject 树），所以为 `null`。

### 9.3 `ResolvedReference`

`resolve()` 不返回 `null` 表示失败，而是返回一个描述**失败是哪一种**的对象 —— 这四种情况需要不同的处理：

```haxe
class ResolvedReference
{
	public var reference(default, null):UnityReference;
	public var entry(default, null):AssetEntry;    // 本地/缺失时为 null
	public var origin(default, null):Origin;
	public var fileId(default, null):Int64;
	public var isMainObject(default, null):Bool;

	public function hasFile():Bool;      // 是否有可读的文件
	public function isBuiltin():Bool;    // 引擎内置
	public function isLocal():Bool;      // 就在本文件里
	public function isMissing():Bool;    // 工程里查不到这个 GUID
	public function kind():AssetKind;
	public function path():String;
}
```

### 9.4 `BuiltinResources`

内置资源**不在工程里**，任何 `.meta` 遍历都查不到，必须靠固定表识别。

```haxe
class BuiltinResources
{
	public static var guids(default, null):Map<String, Bool>;
	public static var names(default, null):Map<String, String>;
	public static function isBuiltinGuid(guid:String):Bool;
	public static function isObjectId(fileId:Int64):Bool;   // fileID 0 不是对象
	public static function nameOf(fileId:Int64):String;     // 未确认的返回 null
	public static function mainObjectFileId(fileId:Int64):Int64;
}
```

> **判定条件是"guid 属于内置集合"，不是"guid 全零"。** 实测真实工程里内置引用用两个固定 guid（`...e000000000000000` 和 `...f000000000000000`），**都不是全零**。写判定时别写成 `guid == "000...0"`。
>
> `names` 表**故意很小**：只收录能确认的（目前只有 `10210` = 内置 Cube 网格）。查不到名字返回 `null` 而不是猜 —— 能报出"这是内置资源，fileID=10754"本身就有用。

### 9.5 `MetaFile`

```haxe
class MetaFile
{
	public var guid(default, null):String;                 // 已转小写
	public var importer(default, null):String;
	public var mainObjectFileId(default, null):Int64;
	public var isFolder(default, null):Bool;
	public static function parse(text:String):MetaFile;    // 永不抛错，读不懂就返回 null 字段
}
```

只读文件开头若干行、不建 YAML 树，因为全量索引时要读上万个 `.meta`，这是整个构建过程中最大的一笔开销。

两个实测踩到的解析细节，本类已处理：

- **`labels:` 可能排在 importer 段之前**，所以不能假设"第一个顶层键就是 importer"；
- **嵌套块里同名字段必须忽略** —— 只认 importer 段自己那一层的键。

### 9.6 `CachedGuidIndex` — 持久化缓存

```haxe
class CachedGuidIndex
{
	public static inline var FORMAT_VERSION = "v2";
	public static inline var DEFAULT_FILE_NAME = "guidindex.tsv";

	public var projectRoot(default, null):String;
	public var cacheFile(default, null):String;
	public var index(default, null):AssetGuidIndex;

	public static function open(projectRoot:String, ?cacheFile:String):CachedGuidIndex;
	public static function defaultCacheFile(projectRoot:String):String;   // Library/hxunity-yaml/guidindex.tsv
	public function isLoaded():Bool;
	public function size():Int;
	public function refresh(?force:Bool):RefreshResult;
	public function save():Bool;
	public function invalidate():Void;
}

typedef RefreshResult = {
	var valid:Bool;              // 缓存直接可用，未重读任何目录
	var rebuilt:Bool;            // 全量重建
	var rescanedDirs:Array<String>;
	var directoryCount:Int;
	var entryCount:Int;
	var elapsedMs:Int;
}
```

用法就是"打开 → refresh → 用"：

```haxe
var cache = CachedGuidIndex.open("D:/Project/MyGame");
var result = cache.refresh();          // 有效则很便宜；无效则增量或全量
Sys.println('${result.valid ? "cache hit" : "rebuilt"} in ${result.elapsedMs} ms');

var entry = cache.index.locate("506c261dd94da1d4c93293b19207e8b0");
```

**实测（22,147 个 `.meta` 的真实工程，22,082 个不同 GUID，1,408 个目录）**

| 操作 | 耗时 |
|---|---|
| 全量重建（冷，无缓存文件） | **≈ 12.1 秒** |
| 校验 + 无变化（常态） | **≈ 1.7 秒** |
| 命中缓存后查一个 GUID | **0 毫秒** |
| 缓存文件大小 | **3.79 MB** |

**有效性判定**：每次刷新都**列出每一个目录**，逐目录比较两件事 ——

| 比较 | 回答 |
|---|---|
| 子目录名列表 | 有没有增删目录 |
| 目录 mtime | 有没有增删文件 |

子目录名是更强的信号：mtime 只有 1 秒精度，同一秒内"删了又建"会漏判，而直接比名字不会。**原地编辑 `.meta` 内容两者都不变**，这是正确的 —— 内容改动不改变"有哪些资产"。

> **必须列出所有目录，不能因为某个目录没变就跳过它的子树。** 在 `Assets/Art` 里加一个文件**不会**改动 `Assets` 的 mtime，所以父目录的任何状态都无法证明子目录没变 —— 早期版本试过这种剪枝，结果"新增文件不失效"这个断言立刻抓到了它。代价就是刷新约 1.7 秒，相对 12 秒的重建仍有约 7 倍收益，而且成本落在目录数上而不是资产数上。
>
> **资产按目录替换，绝不按子树清空。** 父目录自己没有 `.meta`，清空子树会删掉子目录的条目而无人能恢复 —— 这正是"新增一个目录导致其他资产消失"那类 bug 的成因。

缓存文件格式是 TSV + 注释头，双份映射（每资产一行 + 每目录一行），行式可流式解析。写入走临时文件 + rename，中断不会留下半截缓存。

### 9.7 `ProjectFiles` / `ScanOptions`

```haxe
typedef ScanOptions = {
	@:optional var includePackages:Bool;      // 默认 true
	@:optional var skip:Array<String>;        // 额外跳过的目录名
	@:optional var onDirectory:String->Void;  // 进度回调
}
```

`ProjectFiles` 把所有文件系统访问集中在一处，并用 `#if sys` 保护，因此**索引的类型定义在纯 JS 目标上也能编译**（只是不能扫描，需要手工 `add`）。

> **`skip` 的默认值只有 `library`、`logs`、`.git`、`.svn`、`node_modules`。** 早期版本还跳过了 `build` / `obj` / `temp`，结果在真实工程上**漏掉了半个项目** —— `Assets/Art/Build/` 是合法内容目录，不是构建输出。按名字全局跳过这几个是危险的。

---

## 10. 错误处理

```haxe
class YamlError
{
	public var message(default, null):String;
	public var line(default, null):Int;      // 1 基，未知为 0
	public var column(default, null):Int;    // 0 基，未知为 -1
	public function new(message:String, line:Int = 0, column:Int = -1);
	public function toString():String;       // "YamlError: <msg> (line N, column M)"
}
```

抛出 `YamlError` 的场合：

- 解析到结构性错误（`---` 头缺 `!u!` 类 id、流式集合未闭合等）；
- 对类型不符的节点调用 `asMap` / `asSeq` / `asScalar`；
- `YamlScalar.toInt` / `toFloat` / `toBool` / `toInt64` 遇到无法解释的文本；
- `Scalars.node` 收到无法转换的值。

其它场合用普通 Haxe 异常：`FileId.ofString("x")` 抛 `String`，`GameObjectObject.addComponent("NotAUnityClass")` 抛 `String`，`UnityPrefab.save()` 未给路径时抛 `String`。

```haxe
try
{
	var prefab = UnityPrefab.fromFile(path);
}
catch (e:YamlError)
{
	Sys.println("格式错误：" + e);   // 带行列号
}
catch (e:Dynamic)
{
	Sys.println("其它错误：" + Std.string(e));
}
```

---

## 11. 保真格式的保证与边界

**保证**

| 项目 | 说明 |
|---|---|
| 行尾 | `\n` 与 `\r\n` 各自保留，写出时按原样 |
| 尾随换行 | 原文件没有则写出也不加 |
| BOM | 被识别、从首个键名中剥离，写出时按原样补回 |
| 前导指令 | `%YAML` / `%TAG` 按文件顺序保留 |
| 字段顺序 | 就地替换，不重排 |
| 引号风格 | 单引号 / 双引号 / 无引号分别保留；引号内的原文（`\uXXXX` 转义大小写、折行位置）逐字重现，`setRaw` 改值后改按当前值重新编码 |
| 流式 vs 块式 | 节点记住源码形态 |
| 流式折行 | 逗号落在第 80 列之后才折行，续行缩进 = 所属键起始列 + 2（最少 4）；不超过 89 列的引用保持单行 |
| plain 关键字 | Unity 写的 `folderAsset: yes` 等保持无引号 |
| 空值冒号 | `value: `（场景，带空格）与 `userData:`（meta，无空格）各自保留 |
| 数字写法 | `-0`、整数不带 `.0`、不用指数记法 |
| 未知类 id | 保留 id，类名从正文键还原 |
| 无头文档 | `.meta` 不会被凭空加上 `--- !u!` |

**边界**

- 不保证对**手工编辑过、格式非 Unity 习惯**的文件也能逐字节还原 —— 目标是与 Unity 自己的输出一致。
- **同一文件内混用两种行尾**的文件（真实语料里存在，例如部分 `.controller`）只保留占比最高的一种，无法逐字节还原。
- 修改字段会替换该字段的整个节点；如果你希望只改标量文本而保留原引号/标签，用 `YamlMap.setRaw`。
- `UnityPrefab.save()` 是整文件覆盖写，没有原子写入或备份。

---

## 12. 常见任务配方

### 按路径找对象并改名

```haxe
var prefab = UnityPrefab.fromFile(path);
var node = prefab.findByPath("Root/Body/Head");
if (node == null) throw "找不到 Root/Body/Head";
node.setName("Skull");
prefab.save();
```

### 批量替换同名对象的位置

```haxe
for (obj in prefab.findAll("SpawnPoint"))
{
	obj.transform().setLocalPosition(new VectorData(0, 1, 0));
}
```

### 原地复制一个子树并挂到别处

```haxe
var source = prefab.find("Enemy");
var target = prefab.find("EnemyHolder");
var clone = prefab.duplicate(source, target);
clone.setName("Enemy_2");
```

### 给对象加组件并填字段

```haxe
var renderer = obj.addComponent("MeshRenderer");
renderer.set("m_SortingOrder", Scalars.node(35));
renderer.setEnabled(false);
```

### 拆掉一个对象

```haxe
prefab.find("Debug").remove();                 // 连同子孙
prefab.find("Player").getComponent(ClassIds.MeshRenderer).remove();   // 只拆组件
```

### 解析脚本引用到类名

```haxe
var guids = new Map<String, String>();
// 自行遍历项目：MonoScript 资产 + .meta 得到 guid → 类名
var behaviour:MonoBehaviourObject = cast prefab.find("Player").getComponent(ClassIds.MonoBehaviour);
Sys.println(behaviour.resolveClassName(guids));
```

### 只读字段、不想惊动格式

```haxe
var doc = prefab.documents.firstOfClass(ClassIds.MeshRenderer);
Sys.println(doc.getString("m_SortingOrder"));   // 原文
```

### 处理 `.meta`

```haxe
var meta = UnityDocumentSet.parse(sys.io.File.getContent("Assets/Hero.prefab.meta"));
Sys.println(meta.at(0).getString("guid"));
meta.at(0).fields().setRaw("userData", "MyTool");
meta.save("Assets/Hero.prefab.meta");
```

### 解析引用指向哪个资产

```haxe
var cache = CachedGuidIndex.open(projectRoot);
cache.refresh();   // 有效则约 0.8 秒，无效则增量或全量重建

var renderer = prefab.find("Child").getComponent(ClassIds.MeshRenderer);
var materials = renderer.getSeq("m_Materials");
for (item in materials.items)
{
	var resolved = cache.index.resolve(UnityReference.fromNode(item));
	if (resolved.isBuiltin())
	{
		var name = BuiltinResources.nameOf(resolved.fileId);
		Sys.println("内置资源 fileID=" + Int64.toStr(resolved.fileId) + (name == null ? "" : " (" + name + ")"));
	}
	else if (resolved.hasFile())
	{
		Sys.println(resolved.path() + "  " + resolved.kind());
	}
	else if (resolved.isMissing())
	{
		Sys.println("工程里找不到这个 GUID（资产可能被删了）");
	}
}
```

### 新建场景根对象

```haxe
var scene = UnityPrefab.parse(sys.io.File.getContent("Assets/Scenes/Main.unity"));
scene.createGameObject("NewRoot");    // 若存在 SceneRoots 文档，会自动登记进 m_Roots
scene.save();
```

---

## 13. 构建与测试

```cmd
tools\build\test.cmd                              :: 跑测试套件（不用真实语料）
tools\build\test.cmd D:\Project\Game\Assets       :: 同时对真实 Unity 文件做往返校验
tools\build\test.cmd sampale                      :: 用仓库自带的样例 prefab 做往返校验
tools\build\test.cmd --rebuild                    :: 强制重新编译
```

当前状态：

| 分组 | 断言数 |
|---|---|
| Scalars | 50 |
| Yaml | 85 |
| Yaml lexer | 7 |
| Unity | 83 |
| Prefab | 153 |
| Guid index | 64 |
| Round trip | 2（需要语料，否则跳过） |
| **合计** | **444** |

带语料运行时（`tools\build\test.cmd sampale`）444 条全绿，其中 Round trip 会校验 `sampale/test.prefab` 逐字节往返一致。面对大型真实项目建议再跑一次 `tools\build\test.cmd <Assets 路径>`。

单独校验任意 Unity 文件或目录的往返一致性（只读，不改动文件）：

```cmd
haxe -cp src -cp src\tools -main Validate -neko build\validate.n
neko build\validate.n <path> [--limit N] [--show N]
```

> `Validate` 用 `Sys.args()` 读取路径，所以不能走 `--interp`（Haxe 会把参数当成类路径解析）。先编译成 neko 再运行。

---

## 14. 已知限制

- **真实语料实测**：在一个 27802 个资产文件的 Unity 2022.3 工程上全量 `Validate`，99.99% 逐字节一致、0 解析错误；仅剩 4 个 `.controller` 文件为单文件内混用两种行尾的特例（见下条）。仓库自带样例 `sampale/test.prefab` 逐字节往返一致。
- **同一文件内混用两种行尾**的文件（真实语料里存在，例如部分 `.controller`）只保留占比最高的一种，无法逐字节还原。
- **`Projector` 的类 id 曾写错**（与 `LineRenderer` 重复用了 120），已改为 119。该表建议对照官方 [YAML Class ID Reference](https://docs.unity3d.com/Manual/ClassIDReference.html) 完整核一遍。
- `LevelGameManager`（id 3）在 `ClassIds` 里有常量但未登记进 `names`，因此 `ClassIds.name(3)` 返回 `null`。
- **内置资源表故意很小**：只有 `10210`（Cube）一个名字是确认过的。其余内置 id 仍会被正确识别为"内置资源"并给出 `fileID`，只是没有名字。补全需要可靠来源，不靠猜。
- **`mainId` 推导表里有一部分是按 Unity "`<class id>000000`" 约定填的**（见 `AssetClassifier.buildMainIds()` 的注释分层），只在 `.mat` / `.asset` / `.cs` 上做过实测。用错主对象 id 的后果是"解析到错误的子对象"，因此这些值建议在真实项目上核对。
- **GUID → C# 类名未实现**：`MonoBehaviourObject.resolveClassName` 仍需要调用方提供 `Map<String,String>`。本层不读 `.cs` 文件，这是刻意的取舍（省掉全量索引里最大的一笔开销）。
- **缓存有效性依赖目录 mtime 与子目录名**：同一秒内"删了又建"理论上可能漏判（概率极低，且后果只是路径过期到下次刷新）。
- **`src/tools/` 下仍有 `Dump.hx` / `Tokens.hx` 等开发期工具**，不随库发布。
