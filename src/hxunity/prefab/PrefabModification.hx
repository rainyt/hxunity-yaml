package hxunity.prefab;

import haxe.Int64;
import hxunity.unity.UnityReference;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;

/**
	m_Modifications 里的一条覆盖记录。

	Unity 的写法固定四个键：`target`（对象在源预制体文件内的 fileID + guid）、
	`propertyPath`、`value`、`objectReference`。后两者二选一生效：引用型修改的
	`value` 为空、标量型修改的 `objectReference` 恒为 `{fileID: 0}`。

	本类既是只读视图，也通过 [setValue] / [setObjectReference] 就地改写场景
	文件里的这条记录（保持字段顺序与格式，往返不受影响）。
**/
class PrefabModification
{
	/** 覆盖记录的映射节点，位于场景的 m_Modifications 序列里。 **/
	public var entry(default, null):YamlMap;

	public function new(entry:YamlMap)
	{
		this.entry = entry;
	}

	/** 目标对象在源预制体文件内的 fileID。 **/
	public function targetFileId():Int64
	{
		var reference = target();
		return reference == null ? Int64.ofInt(0) : reference.fileId;
	}

	/** 目标对象的源预制体 guid，通常与实例的 m_SourcePrefab 相同。 **/
	public function targetGuid():String
	{
		var reference = target();
		return reference == null ? null : reference.guid;
	}

	/** 要修改的属性路径，例如 `m_LocalPosition.x`。 **/
	public function propertyPath():String
	{
		var node = entry.get("propertyPath");
		return node == null ? null : node.toString();
	}

	/** `value` 键的原文；引用型修改时为空字符串。 **/
	public function valueText():String
	{
		var node = entry.get("value");
		return node == null ? "" : node.toString();
	}

	/** `objectReference` 节点；缺失返回 `null`。 **/
	public function objectReference():YamlNode
	{
		return entry.get("objectReference");
	}

	/**
		引用是否指向场景对象（本地 fileID、无 guid）。

		这样的覆盖在场景里生效，但**不能**应用进预制体文件——预制体无法引用
		某个场景里的对象，[PrefabInstance.applyToPrefab] 会跳过并计数。
	**/
	public function referencesSceneObject():Bool
	{
		var node = objectReference();
		if (node == null) return false;
		var parsed = UnityReference.fromNode(node);
		if (parsed == null) return false;
		return parsed.isLocal() && parsed.fileId != Int64.ofInt(0);
	}

	/** 改写 `value`（空串表示置空，与 Unity 写出的 `value: ` 一致）。 **/
	public function setValue(text:String):Void
	{
		entry.set("value", new YamlScalar(text == null ? "" : text, ScalarKind.Plain));
	}

	/** 改写 `objectReference`（[UnityReference.toNode] 产出即可直接使用）。 **/
	public function setObjectReference(node:YamlNode):Void
	{
		entry.set("objectReference", node);
	}

	/** 与目标 fileID + 属性路径是否匹配（覆盖去重与更新的依据）。 **/
	public function matches(fileId:Int64, path:String):Bool
	{
		return targetFileId() == fileId && propertyPath() == path;
	}

	function target():UnityReference
	{
		var node = entry.get("target");
		return node == null ? null : UnityReference.fromNode(node);
	}
}
