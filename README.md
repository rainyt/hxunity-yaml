# hxunity-yaml

用 Haxe 读写 Unity 2022.3 的 YAML 资产：`.prefab` / `.asset` / `.unity` / `.mat` / `.controller` / `.anim` / `.meta`。

## 特性

1. 使用 Haxe 编程语言实现，不依赖任何其它 haxelib 包；
2. 针对 Unity 2022.3 版本的 Yaml 格式读写支持；
3. 修改和读写 Yaml 文件时尽可能保持原始格式，避免引入额外的空行或缩进；
4. 除纯语法层外，还提供一层 Unity 对象图 API，可按名字/层级路径操作 GameObject、Transform 与组件；`.unity` 场景同样直接支持；
5. 64 位 `fileID` 全程用 `haxe.Int64` 承载，不经过 `Float`，JavaScript 目标上也不会丢精度；
6. **GUID 索引**：把 `{fileID: 2100000, guid: 506c261d..., type: 2}` 这类引用解析到实际资产（材质、贴图、网格、图集…），带持久化缓存与增量刷新。

## 保真往返

文件读入再写出时，下面这些都会原样保留，未改动的文件逐字节还原：

- 行尾风格（`\n` / `\r\n`）与尾随换行；
- `%YAML` / `%TAG` 前导指令；
- 字段顺序（就地替换，不重排）；
- 标量引号风格（无引号 / 单引号 / 双引号 / 块标量）；引号内的原文（`\uXXXX` 转义大小写、折行位置）逐字重现；
- 流式（`{fileID: 0}`）与块式形态；
- 流式映射的折行位置与续行缩进（逗号超过 80 列才折行，续行缩进 = 键起始列 + 2）；
- 数字写法（`-0` 保留、整数不带 `.0`、不用指数记法）。

这样改动在版本控制里只显示真正的差异，而不是整文件重排。

## 快速开始

```haxe
import hxunity.prefab.UnityPrefab;
import hxunity.types.VectorData;

class Main
{
	static function main()
	{
		var prefab = UnityPrefab.fromFile("Assets/Hero.prefab");

		var hand = prefab.findByPath("Player/Hand");
		hand.setName("LeftHand");
		hand.transform().setLocalPosition(new VectorData(0.5, 1, 0));

		prefab.save();
	}
}
```

新建一个 prefab：

```haxe
var prefab = UnityPrefab.createEmpty();
var root = prefab.createGameObject("Only");
root.addChild("Nested").addComponent("MeshRenderer");
prefab.save("Assets/New.prefab");
```

解析 GUID 引用：

```haxe
import hxunity.unity.CachedGuidIndex;
import hxunity.unity.UnityReference;

var cache = CachedGuidIndex.open("D:/Project/MyGame");
cache.refresh();   // 缓存有效时约 1.7 秒，全量重建约 12 秒

var resolved = cache.index.resolve(UnityReference.fromNode(item));
if (resolved.hasFile()) Sys.println(resolved.path() + " " + resolved.kind());
else if (resolved.isBuiltin()) Sys.println("内置资源 fileID=" + Int64.toStr(resolved.fileId));
else if (resolved.isMissing()) Sys.println("工程里找不到这个 GUID");
```

## 编译

```hxml
-cp src
```

## 测试

```cmd
tools\build\test.cmd                          :: 跑测试套件
tools\build\test.cmd D:\Project\Game\Assets   :: 同时对真实 Unity 文件做往返校验
tools\build\test.cmd sampale                  :: 用仓库自带样例 prefab 做往返校验
tools\build\test.cmd --rebuild                :: 强制重新编译
```

当前 **462 条断言通过**（带 `sampale` 语料运行时全绿，其中 `sampale/test.prefab` 确认逐字节往返一致）。不传语料时往返分组会跳过。

在一个 27802 个资产文件的真实工程（Unity 2022.3，含场景 / 预制体 / 材质 / 动画控制器 / `.meta`）上全量 `Validate`：**99.99% 逐字节一致、0 解析错误**；仅剩的 4 个文件均为同一文件内混用 `\n` 与 `\r\n` 两种行尾的特例（见 docs/API.md 已知限制）。

单独校验任意文件或目录（只读）：

```cmd
haxe -cp src -cp src\tools -main Validate -neko build\validate.n
neko build\validate.n <path> [--limit N] [--show N]
```

## 文档

完整 API 参考见 [docs/API.md](docs/API.md)，包含：

- 三个入口层（文档层 / 对象层 / 语法层）的选择建议；
- `UnityDocumentSet`、`UnityYamlDocument`、`YamlMap` / `YamlSeq` / `YamlScalar` 的逐项签名；
- `UnityPrefab`、`GameObjectObject`、`TransformObject`、`Component`、`MonoBehaviourObject` 的完整方法表；
- `.unity` 场景（设置类文档、`SceneRoots`、多根对象）；
- `VectorData` / `QuaternionData` / `ColorData` / `Numbers` 值类型；
- `FileId` / `UnityReference` 与 `!u!` 类 id 表；
- **GUID 索引与缓存**（`AssetGuidIndex` / `CachedGuidIndex` / `BuiltinResources` / `MetaFile`）；
- 错误处理、保真边界、常见任务配方与已知限制。

GUID 索引的设计与实测数据另见 [docs/GUID-INDEX.md](docs/GUID-INDEX.md)。

## 目录结构

```
src/
  hxunity/yaml/                YAML 与文档层（词法、语法、节点、文档集）
  hxunity/prefab/              Unity 对象图层
  hxunity/types/               Unity 值类型
  hxunity/unity/               64 位 id、序列化引用、GUID 索引与缓存
  tools/                       开发/校验工具（Validate 等）
tests/                         测试套件
tools/build/test.cmd           一键编译并运行测试
docs/API.md                    API 参考
docs/GUID-INDEX.md             GUID 索引设计与实测
```
