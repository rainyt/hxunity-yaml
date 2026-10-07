package hxunity.prefab;

import haxe.Int64;
import hxunity.unity.AssetGuidIndex;
import hxunity.unity.UnityReference;
import hxunity.prefab.GameObjectObject;
import hxunity.prefab.TransformObject;
import hxunity.yaml.ClassIds;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlError;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;

/**
	[ApplyResult](applyToPrefab) 的统计。
**/
typedef ApplyResult =
{
	/** 成功写进目标对象的覆盖条数。 **/
	var applied:Int;

	/** target.fileID 在目标文件里找不到，或路径写不进去的条数。 **/
	var missingTargets:Int;

	/** 因引用场景对象而跳过、不写入预制体的条数。 **/
	var skippedSceneReferences:Int;
}

/**
	场景里的一个预制体实例（PrefabInstance，classId 1001），对应 Unity 的
	预制体工作流：

	- 场景文件只保存三样东西：`m_SourcePrefab`（指向 .prefab 资产的 guid）、
	  `m_Modifications`（实例覆盖列表）、`m_TransformParent`（挂载点）；
	  预制体的完整层级只存在于 .prefab 文件里。
	- 编辑器里的实例改动只写进场景的 m_Modifications，在场景打开时生效；
	  点击 Apply 才写进 .prefab 资产。本类提供同样语义的两组操作。

	```haxe
	var cache = CachedGuidIndex.open(projectRoot);
	cache.refresh();
	var scene = UnityPrefab.fromFile(scenePath);

	for (instance in PrefabInstance.list(scene, cache.index))
	{
		// 完整结构：源预制体 + 全部覆盖已应用（内存视图，不写任何文件）
		var view = instance.effectivePrefab();
		var root = instance.rootGameObject();
		trace(root.name() + " at " + instance.sourcePath());

		// 实例覆盖：只写场景的 m_Modifications，与 Unity 一致
		instance.setOverride(root.fileId(), "m_Name", "Hero_Renamed");

		// 对应编辑器的 Apply：把覆盖写进 .prefab 文件
		var result = instance.applyToPrefab();
	}
	```

	**与 Unity 文件格式的两处对齐**，写回时必须遵守：

	- 覆盖永远只进场景的 m_Modifications，绝不把预制体内容展开写进 .unity——
	  展开会让 Unity 把这些对象当成普通场景对象，PrefabInstance 关系即丢失；
	- `objectReference` 指向场景对象的覆盖（本地 fileID）不能应用进预制体，
	  [applyToPrefab] 会跳过并计入 [ApplyResult.skippedSceneReferences]。

	嵌套预制体（prefab 里还有 PrefabInstance）不在 [effectivePrefab] 里自动
	展开；克隆里保留嵌套文档，用 [list] 对克隆递归即可逐层取完整结构。
**/
class PrefabInstance
{
	var scene:UnityPrefab;
	var documentNode:UnityYamlDocument;
	var index:AssetGuidIndex;
	var loadedSource:UnityPrefab;

	function new(scene:UnityPrefab, document:UnityYamlDocument, index:AssetGuidIndex)
	{
		this.scene = scene;
		this.documentNode = document;
		this.index = index;
	}

	/** 场景里的全部预制体实例，按文档顺序。 **/
	public static function list(scene:UnityPrefab, index:AssetGuidIndex):Array<PrefabInstance>
	{
		var out:Array<PrefabInstance> = [];
		for (document in scene.documents.documents)
		{
			if (document.isPrefabInstance())
			{
				out.push(new PrefabInstance(scene, document, index));
			}
		}
		return out;
	}

	// ---------------------------------------------------------------- 依赖关系

	/** 场景里的 PrefabInstance 文档。 **/
	public function document():UnityYamlDocument
	{
		return documentNode;
	}

	/** 源预制体资产的 guid。 **/
	public function sourceGuid():String
	{
		return referenceOf("m_SourcePrefab") == null ? null : referenceOf("m_SourcePrefab").guid;
	}

	/**
		源预制体的资产路径（相对工程根），通过 GUID 索引解析；找不到返回
		`null`（[isMissing] 为真）。
	**/
	public function sourcePath():String
	{
		if (index == null) return null;
		var resolved = index.resolve(sourceReference());
		return resolved == null || resolved.isMissing() ? null : resolved.path();
	}

	/** 源预制体资产在磁盘上解析不到时为真。 **/
	public function isMissing():Bool
	{
		return sourcePath() == null;
	}

	/**
		实例在场景里挂载到的父 Transform 的 fileID（`m_TransformParent`）；
		没有写时为 0。
	**/
	public function parentTransformFileId():Int64
	{
		var reference = referenceOf("m_TransformParent");
		return reference == null ? Int64.ofInt(0) : reference.fileId;
	}

	/**
		实例在场景层级中的位置：场景里那个 stripped Transform 文档
		（`m_PrefabInstance` 指回本实例）。

		它是占位文档，没有自己的 GameObject；[effectivePrefab] 的根对象对应
		的就是它。
	**/
	public function instanceTransform():TransformObject
	{
		var instanceId = documentNode.fileId;
		for (candidate in scene.documents.documents)
		{
			if (!candidate.stripped) continue;
			if (candidate.classId != ClassIds.Transform && candidate.classId != ClassIds.RectTransform) continue;
			var classMap = candidate.body.asMap().getMap("Transform");
			if (classMap == null) classMap = candidate.body.asMap().getMap("RectTransform");
			if (classMap == null) continue;
			var reference = referenceOfNode(classMap.get("m_PrefabInstance"));
			if (reference != null && reference.fileId == instanceId)
			{
				return new TransformObject(candidate, scene);
			}
		}
		return null;
	}

	/**
		实例挂载到的场景父对象，由 m_TransformParent 解析。

		父级是另一个实例的 stripped transform 时返回 `null`（该文档没有
		GameObject）——用 [instanceTransform] 与 [list] 把 stripped 文档映射回
		所属实例后再取其根对象。
	**/
	public function parentGameObject():GameObjectObject
	{
		var fileId = parentTransformFileId();
		if (fileId == Int64.ofInt(0)) return null;
		var parent = scene.documents.byId(fileId);
		if (parent == null || (parent.classId != ClassIds.Transform && parent.classId != ClassIds.RectTransform)) return null;
		return new TransformObject(parent, scene).gameObject();
	}

	// ------------------------------------------------------------- 源与视图

	/**
		源预制体文件的对象图，从磁盘加载并按路径缓存。

		[fresh] 为真时绕过缓存重新读盘——[applyToPrefab] 内部就是这样用的，
		避免对已应用过覆盖的缓存重复写入。解析不到源资产返回 `null`。
	**/
	public function sourcePrefab(fresh:Bool = false):UnityPrefab
	{
		if (!fresh && loadedSource != null) return loadedSource;
		if (index == null) return null;
		var absolute = index.absolutePathOf(sourceGuid());
		if (absolute == null) return null;
		loadedSource = UnityPrefab.fromFile(absolute);
		return loadedSource;
	}

	/**
		完整结构的内存视图：源预制体的独立克隆 + 本实例全部覆盖已应用。

		不写任何文件；对视图的检查用现有的对象图 API（rootGameObject /
		findByPath / components 等）。克隆与源文件相互独立，改它不会影响
		场景或预制体。

		嵌套预制体不自动展开：克隆里保留其 PrefabInstance 文档，用
		[list] 对克隆递归即可逐层取完整结构。
	**/
	public function effectivePrefab():UnityPrefab
	{
		var source = sourcePrefab();
		if (source == null) return null;
		var clone = UnityPrefab.parse(source.emit());
		applyAll(clone, false);
		return clone;
	}

	/** 实例根对象（[effectivePrefab] 的第一个根）。源资产缺失时为 `null`。 **/
	public function rootGameObject():GameObjectObject
	{
		var view = effectivePrefab();
		if (view == null) return null;
		var roots = view.rootGameObjects();
		return roots.length > 0 ? roots[0] : null;
	}

	// ----------------------------------------------------------------- 覆盖

	/** 全部覆盖记录（场景 m_Modifications 的视图，按文件顺序）。 **/
	public function modifications():Array<PrefabModification>
	{
		var out:Array<PrefabModification> = [];
		var seq = modificationsSeq(false);
		if (seq == null) return out;
		for (item in seq.items)
		{
			if (Std.isOfType(item, YamlMap)) out.push(new PrefabModification(cast item));
		}
		return out;
	}

	/** 覆盖条数。 **/
	public function modificationCount():Int
	{
		return modifications().length;
	}

	/**
		写入（或更新）一条标量覆盖：只改场景的 m_Modifications，与 Unity 编辑器
		里的实例改动一致。

		同样的 target + propertyPath 只保留一条记录，重复写入是就地更新；
		objectReference 重置为 `{fileID: 0}`，与 Unity 的四键写法一致。
		[value] 的引号风格由内容决定（与 `Scalars.ofString` 相同）。
	**/
	public function setOverride(targetFileId:Int64, propertyPath:String, value:String):Void
	{
		var entry = upsertEntry(targetFileId, propertyPath);
		entry.setValue(value);
		entry.setObjectReference(zeroReference());
	}

	/**
		写入（或更新）一条引用覆盖。

		[reference] 传 [UnityReference.toNode] 的产出：引用场景对象用
		`UnityReference.local(fileId)`，置空用 `UnityReference.none()`（即
		`{fileID: 0}`），引用资产用带 guid 的引用。
	**/
	public function setObjectReferenceOverride(targetFileId:Int64, propertyPath:String, reference:YamlNode):Void
	{
		var entry = upsertEntry(targetFileId, propertyPath);
		entry.setValue("");
		entry.setObjectReference(reference == null ? zeroReference() : reference);
	}

	/** 撤销一条覆盖（对应 Unity 的 Revert 单项），存在时返回真。 **/
	public function removeOverride(targetFileId:Int64, propertyPath:String):Bool
	{
		var seq = modificationsSeq(false);
		if (seq == null) return false;
		var entry = findEntry(targetFileId, propertyPath);
		if (entry == null) return false;
		return seq.removeItem(entry.entry);
	}

	/** 撤销全部覆盖（对应 Unity 的 Revert All）；m_Modifications 清空但保留。 **/
	public function clearOverrides():Void
	{
		var seq = modificationsSeq(true);
		while (seq.length() > 0)
		{
			seq.removeAt(seq.length() - 1);
		}
	}

	// ----------------------------------------------------------------- 应用

	/**
		把全部覆盖写进源预制体文件（对应编辑器的 Apply），返回统计。

		预制体总是从磁盘重新加载、应用后立即保存，保证写入的是文件当前内容；
		场景文件不受影响——Apply 之后场景里的覆盖仍然保留（Unity 的文件格式
		也是如此，编辑器只在刷新时清理已一致的条目）。

		引用场景对象的覆盖无法进入预制体，被跳过并计入
		[ApplyResult.skippedSceneReferences]；源资产解析不到时抛 [YamlError]。
	**/
	public function applyToPrefab():ApplyResult
	{
		var source = sourcePrefab(true);
		if (source == null)
		{
			throw new YamlError('cannot apply prefab instance: source asset "${sourceGuid()}" is missing', documentNode.line, 0);
		}
		var result = applyAll(source, true);
		source.save();
		return result;
	}

	// ----------------------------------------------------------------- 内部

	function sourceReference():UnityReference
	{
		return referenceOf("m_SourcePrefab");
	}

	function referenceOf(key:String):UnityReference
	{
		var body = documentNode.body.asMap();
		if (body == null) return null;
		var classMap = body.getMap("PrefabInstance");
		if (classMap == null) return null;
		return referenceOfNode(classMap.get(key));
	}

	static function referenceOfNode(node:YamlNode):UnityReference
	{
		return node == null ? null : UnityReference.fromNode(node);
	}

	function modificationsSeq(create:Bool):YamlSeq
	{
		var body = documentNode.body.asMap();
		if (body == null) return null;
		var classMap = body.getMap("PrefabInstance");
		if (classMap == null) return null;
		var modification = classMap.getMap("m_Modification");
		if (modification == null)
		{
			if (!create) return null;
			modification = new YamlMap();
			modification.set("serializedVersion", new YamlScalar("3", ScalarKind.Plain));
			modification.set("m_TransformParent", UnityReference.none().toNode());
			classMap.set("m_Modification", modification);
		}
		var seq = modification.getSeq("m_Modifications");
		if (seq == null && create)
		{
			seq = new YamlSeq();
			modification.set("m_Modifications", seq);
		}
		return seq;
	}

	function findEntry(targetFileId:Int64, propertyPath:String):PrefabModification
	{
		for (modification in modifications())
		{
			if (modification.matches(targetFileId, propertyPath)) return modification;
		}
		return null;
	}

	function upsertEntry(targetFileId:Int64, propertyPath:String):PrefabModification
	{
		var existing = findEntry(targetFileId, propertyPath);
		if (existing != null) return existing;
		var entry = new YamlMap();
		var target = new YamlMap(null, true);
		target.set("fileID", new YamlScalar(Int64.toStr(targetFileId), ScalarKind.Plain));
		target.set("guid", new YamlScalar(sourceGuid() == null ? "" : sourceGuid(), ScalarKind.Plain));
		target.set("type", new YamlScalar("3", ScalarKind.Plain));
		entry.set("target", target);
		entry.set("propertyPath", Scalars.ofString(propertyPath));
		entry.set("value", new YamlScalar("", ScalarKind.Plain));
		entry.set("objectReference", zeroReference());
		modificationsSeq(true).push(entry);
		return new PrefabModification(entry);
	}

	static function zeroReference():YamlNode
	{
		return UnityReference.none().toNode();
	}

	/**
		把全部覆盖应用到 [target] 的对象图上。

		[skipSceneRefs] 为真时跳过引用场景对象的条目（写预制体时必须跳过）；
		为假时原样写入（内存视图需要看到场景引用本身）。
	**/
	function applyAll(target:UnityPrefab, skipSceneRefs:Bool):ApplyResult
	{
		var applied = 0;
		var missingTargets = 0;
		var skippedSceneReferences = 0;
		for (modification in modifications())
		{
			if (skipSceneRefs && modification.referencesSceneObject())
			{
				skippedSceneReferences++;
				continue;
			}
			var value = valueOf(modification);
			var owner = target.documents.byId(modification.targetFileId());
			if (owner == null)
			{
				missingTargets++;
				continue;
			}
			if (PropertyPath.set(fieldMapOf(owner), modification.propertyPath(), value))
			{
				applied++;
			}
			else
			{
				missingTargets++;
			}
		}
		return {applied: applied, missingTargets: missingTargets, skippedSceneReferences: skippedSceneReferences};
	}

	/**
		文档的字段映射：与 [UnityObject.fields] 相同的解包规则 —— body 只有一个
		类键（`GameObject:` / `Transform:` / …）时进入类键内部写，覆盖才会落在
		Unity 读取的字段层级上；若直接写 body 顶层，多出来的条目会让该解包
		启发式失效，对象图随之读不到组件。
	**/
	static function fieldMapOf(document:UnityYamlDocument):YamlMap
	{
		var body = document.body;
		if (!Std.isOfType(body, YamlMap)) return null;
		var map:YamlMap = cast body;
		if (map.entries.length == 1)
		{
			var inner = map.entries[0].value;
			if (Std.isOfType(inner, YamlMap)) return cast inner;
		}
		return map;
	}

	/**
		覆盖的目标值：引用型取 objectReference 节点；标量型取 value 文本。
		两者都空（`value: ` + `{fileID: 0}`）表示置空，与 Unity 的写法一致。
	**/
	function valueOf(modification:PrefabModification):YamlNode
	{
		var reference = modification.objectReference();
		if (reference != null)
		{
			var parsed = UnityReference.fromNode(reference);
			if (parsed != null && parsed.fileId != Int64.ofInt(0)) return reference;
			if (parsed == null) return reference;
		}
		var text = modification.valueText();
		if (text.length > 0) return Scalars.ofString(text);
		return new YamlScalar("", ScalarKind.Plain);
	}
}
