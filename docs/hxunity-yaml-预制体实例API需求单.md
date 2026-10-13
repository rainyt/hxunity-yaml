# hxunity-yaml 需求单：预制体实例的创建 API（写方向）

> 提出方：mapeditor PSD 导出器（`Source/tools/psd/PsdExporter.hx` 改造）
> 交付目标：`hxunity-yaml` 库
> 状态：待实现

## 背景

PSD 导出器要把一份 PSD 拆成「N 个组预制体 + 1 个根预制体」，根预制体通过
PrefabInstance 引用各组预制体。库目前只有 PrefabInstance 的**读取**能力
（`list` / `effectivePrefab` / `setOverride` / `applyToPrefab`），缺少**创建**一个
实例的 API。

消费方约定：mapeditor 的渲染树（`RenderTreeBuilder.walkInstance`）与层级面板
（`PrefabTools`）已按现有读取约定工作，新建实例的产出格式必须与这些读取约定
逐字段对齐（见下方格式基准），否则编辑器无法展开实例。

## 已确认可复用的库内能力（调研结论）

- `UnityYamlDocument` 构造器支持 `stripped` 标记；`UnityDocumentSet.emit` 已输出
  `--- !u!4 &<id> stripped` 头（`UnityDocumentSet.hx:291`）。
- `UnityDocumentSet.newFileId()` 可分配新 fileId（`UnityDocumentSet.hx:234`）。
- `ComponentDefaults.transform` 已产出完整字段集（含 `m_CorrespondingSourceObject`
  / `m_PrefabInstance` / `m_PrefabAsset` / `serializedVersion`），stripped 变体可在其
  基础上改写。
- `TransformObject.childTransforms()` 按 `m_Children` 解析任何 Transform 类文档；
  占位文档 `m_GameObject: {fileID: 0}` 时 `gameObject()` 返回 `null`——渲染树与
  层级面板正是以此识别嵌套实例（`m_PrefabInstance` 反查）。
- `PrefabInstance` 构造器与 `UnityPrefab` 同包（`hxunity.prefab`），可直接构造返回。
- 浮点/引用的写出规则沿用 `ComponentDefaults` 与 `UnityReference` 现有工厂。

## 需求 1（必须）：`UnityPrefab.createPrefabInstance`

签名（命名可按库内风格调整，契约不变）：

```haxe
// hxunity.prefab.UnityPrefab
/**
 * 在本 prefab/scene 中创建一个预制体实例：
 * 一个 PrefabInstance 文档（classId 1001）+ 一个 stripped Transform 占位文档。
 *
 * @param sourceGuid                 源 .prefab 资产 guid
 * @param sourceRootGameObjectFileId 源预制体根 GameObject 的 fileID（m_Name 覆盖的 target）
 * @param sourceRootTransformFileId  源预制体根 Transform 的 fileID（位移/旋转覆盖的 target）
 * @param parent                     挂载父对象；null = 根级（本期限宿主文件内普通对象，不做嵌套挂载）
 * @return 新建实例；源根 fileID 记录在其上，供便利覆盖方法使用
 */
public function createPrefabInstance(
    sourceGuid:String,
    sourceRootGameObjectFileId:Int64,
    sourceRootTransformFileId:Int64,
    ?parent:GameObjectObject
):PrefabInstance
```

行为：

1. 新建 PrefabInstance 文档（fileId 走 `newFileId()`），格式见「格式基准」，其中
   `m_Modification.m_TransformParent` = parent 的 Transform fileId（parent 为 null 时
   写 `{fileID: 0}`），`m_Modifications` 初始为空序列，`m_RemovedGameObjects` /
   `m_RemovedComponents` 为空序列，`m_SourcePrefab` 指向 `sourceGuid`。
2. 新建 stripped Transform 占位文档（classId 4，`stripped = true`），字段集复用
   `ComponentDefaults.transform`，差异点：
   - `m_ObjectHideFlags: 1`；
   - `m_GameObject: {fileID: 0}`；
   - `m_CorrespondingSourceObject: {fileID: <sourceRootTransformFileId>, guid: <sourceGuid>, type: 3}`；
   - `m_PrefabInstance: {fileID: <实例文档 fileId>}`（注意不是 0）；
   - `m_Father` = parent 的 Transform（null 时 `{fileID: 0}`）；
   - `m_LocalRotation` / `m_LocalPosition` 建议镜像后续覆盖值（仅为可读性，读取
     路径不使用；创建时可先写单位值，便利方法写覆盖时同步刷新即可，亦可不刷新）。
3. 把占位 Transform 的 fileId 追加到 parent Transform 的 `m_Children` 尾部
   （与 `createGameObject` 的挂接方式一致；追加顺序 = 创建顺序，消费方依赖它
   保持绘制顺序）。parent 为 null 时不挂接。
4. 返回 `new PrefabInstance(this, 实例文档, null, null)`。文档说明需注明：index 为
   null 时 `sourcePrefab()` / `effectivePrefab()` 在落盘 + 带索引重读前返回 null 是
   预期行为；`setOverride` / 便利覆盖方法不受影响。

## 需求 2（推荐）：实例摆放的便利方法

位置 + 旋转 + 名字覆盖共 9 条标量，调用方手拼容易错（`m_Name` 的 target 是根
**GameObject**，TRS 的 target 是根 **Transform**，两者不同）。建议在
`PrefabInstance` 上加：

```haxe
/** 实例名覆盖（target = 创建时登记的源根 GameObject fileID）。 */
public function setInstanceName(name:String):Void;

/** 实例位置与旋转覆盖（target = 创建时登记的源根 Transform fileID），写 7 条标量覆盖。 */
public function setInstancePlacement(x:Float, y:Float, z:Float, qx:Float, qy:Float, qz:Float, qw:Float):Void;
```

- 两个源根 fileID 由 `createPrefabInstance` 记录在实例上（只读字段即可）。
- 实例不是由 `createPrefabInstance` 创建（从磁盘加载）时，这两个方法抛
  `YamlError`，提示改用 `setOverride` 显式指定 target。
- 浮点格式化与 `ComponentDefaults` 同规则；标量覆盖条目带
  `objectReference: {fileID: 0}`（与现有 `setOverride` 输出一致）。
- 若嫌侵入可不加，调用方直接 `setOverride` 亦可——需求 1 独立成立。

## 需求 3（顺手修）：`parentTransformFileId` / `parentGameObject` 的读取路径

现状 bug：`referenceOf("m_TransformParent")` 从 PrefabInstance 类映射**顶层**取值，
而真实 Unity 文件与库自己的测试夹具（`TestPrefabInstance.writeFixture`）都把
`m_TransformParent` 放在 `m_Modification:` 之下——这两个方法目前恒返回
0 / null。当前 mapeditor 未调用它们，但需求 1 的写出格式按 Unity 惯例走嵌套
路径，读取应对齐：

```haxe
// 改为从 m_Modification.m_TransformParent 读取
function transformParentReference():UnityReference {
    var classMap = documentNode.body.asMap().getMap("PrefabInstance");
    if (classMap == null) return null;
    var modification = classMap.getMap("m_Modification");
    return modification == null ? null : UnityReference.fromNode(modification.get("m_TransformParent"));
}
```

## 格式基准（写出必须逐字段对齐）

PrefabInstance 文档（Unity 2022 惯例，字段顺序按样例）：

```yaml
--- !u!1001 &900
PrefabInstance:
  m_ObjectHideFlags: 0
  serializedVersion: 2
  m_Modification:
    serializedVersion: 3
    m_TransformParent: {fileID: 101}
    m_Modifications:
    - target: {fileID: 100, guid: <sourceGuid>, type: 3}
      propertyPath: m_Name
      value: safa
      objectReference: {fileID: 0}
    - target: {fileID: 101, guid: <sourceGuid>, type: 3}
      propertyPath: m_LocalPosition.x
      value: 1.5
      objectReference: {fileID: 0}
    # ... m_LocalPosition.y / .z、m_LocalRotation.x / .y / .z / .w 同理
    m_RemovedGameObjects: []
    m_RemovedComponents: []
  m_SourcePrefab: {fileID: 100100000, guid: <sourceGuid>, type: 3}
```

stripped Transform 占位文档：

```yaml
--- !u!4 &901 stripped
Transform:
  m_ObjectHideFlags: 1
  m_CorrespondingSourceObject: {fileID: 101, guid: <sourceGuid>, type: 3}
  m_PrefabInstance: {fileID: 900}
  m_PrefabAsset: {fileID: 0}
  m_GameObject: {fileID: 0}
  serializedVersion: 2
  m_LocalRotation: {x: 0, y: 0, z: 0, w: 1}
  m_LocalPosition: {x: 0, y: 0, z: 0}
  m_LocalScale: {x: 1, y: 1, z: 1}
  m_ConstrainProportionsScale: 0
  m_Children: []
  m_Father: {fileID: 101}
  m_LocalEulerAnglesHint: {x: 0, y: 0, z: 0}
```

说明：`m_RootOrder` 库内现有 Transform 文档同样省略、读取不依赖，可继续省略；
`m_Modifications` 标量条目的 `objectReference: {fileID: 0}` 是 Unity 真实产物的
四键写法，需带上（现有 `setOverride` 已如此输出）。

## 验收标准

1. 创建实例 → `emit`/`save` → `UnityPrefab.fromFile` 重读 → `PrefabInstance.list`
   恰好列出该实例，`sourceGuid()` 正确。
2. 带索引的 `effectivePrefab()` 应用 `m_Name` / `m_LocalPosition.*` /
   `m_LocalRotation.*` 覆盖后，视图根对象的名字与 TRS 与覆盖值一致。
3. 父 Transform 的 `m_Children` 含占位 fileId 且按创建顺序排列；
   `PrefabInstance.instanceTransform()` 能反查占位文档；占位的 `gameObject()` 为
   null、其 `m_PrefabInstance` 指回实例文档。
4. 落盘文件中实例文档与占位文档的头部为 `--- !u!1001 &<id>` 与
   `--- !u!4 &<id> stripped`。
5. 按 `TestPrefabInstance` 现有风格补端到端测试：临时工程内建源 prefab +
   宿主 prefab，`createPrefabInstance` + 便利覆盖 → 落盘 → 重读断言 1–4。
6. 需求 3：对测试夹具（嵌套格式的 `m_TransformParent`）断言
   `parentTransformFileId()` 返回正确值。

## 调用方使用方式（供 API 形状参考）

```haxe
// mapeditor PSD 导出器（宿主 = 根预制体，源 = 组预制体）
var groupEntry = UnityAssetFactory.createPrefab(projectRoot, "Assets/PsdExport/safa.prefab", groupPrefab, index);
var groupRoot = groupPrefab.rootGameObjects()[0];
var instance = rootPrefab.createPrefabInstance(
    groupEntry.guid,
    groupRoot.fileId(),
    groupRoot.transform().fileId(),
    rootGo
);
instance.setInstanceName("safa");
instance.setInstancePlacement(px, py, 0, 0, 0, 0, 0.7071068);
```
