package hxunity.prefab;

import haxe.Int64;
import hxunity.yaml.ClassIds;
import hxunity.yaml.UnityYamlDocument;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlSeq;
import hxunity.unity.UnityReference;

/**
	Base class for a serialised Unity object, wrapping its `--- !u!` document.

	Every accessor that reads or writes a field goes straight to the document's
	field mapping, so anything Unity serialises is reachable even when this
	library has no dedicated wrapper for it:

	```haxe
	var renderer = gameObject.getComponent(ClassIds.MeshRenderer);
	renderer.set("m_SortingOrder", hxunity.yaml.Scalars.node(5));
	```
**/
class UnityObject
{
	/** The parsed document this object wraps. **/
	public var document(default, null):UnityYamlDocument;

	/** The prefab that owns this object. **/
	public var prefab(default, null):UnityPrefab;

	public function new(document:UnityYamlDocument, prefab:UnityPrefab)
	{
		this.document = document;
		this.prefab = prefab;
	}

	/** Unity class id, e.g. 1 for `GameObject`. **/
	public inline function classId():Int
	{
		return document.classId;
	}

	/** Unity class name, e.g. `GameObject` or `MonoBehaviour`. **/
	public function className():String
	{
		return document.className();
	}

	/**
		File id of this object: the `&1234` anchor of its document.

		This is the value other objects store to reference it.
	**/
	public inline function fileId():Int64
	{
		return document.fileId;
	}

	/** True when Unity marked this document `stripped`. **/
	public inline function isStripped():Bool
	{
		return document.stripped;
	}

	/** Field mapping of the document body, unwrapped from the class-name key. **/
	public function fields():YamlMap
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

	/** Field value, or `null` when absent. **/
	public function get(key:String):YamlNode
	{
		var map = fields();
		return map == null ? null : map.get(key);
	}

	/** Stores a field value, creating the field when it is absent. **/
	public function set(key:String, value:YamlNode):YamlNode
	{
		return fields().set(key, value);
	}

	/** Scalar text of a field, or `null`. **/
	public function getString(key:String):String
	{
		var map = fields();
		return map == null ? null : map.getString(key);
	}

	/** Field read as an int, or `null` when absent or not numeric. **/
	public function getInt(key:String):Null<Int>
	{
		var map = fields();
		return map == null ? null : map.getInt(key);
	}

	/** Field read as a float, or `null` when absent or not numeric. **/
	public function getFloat(key:String):Null<Float>
	{
		var map = fields();
		return map == null ? null : map.getFloat(key);
	}

	/** Field read as a bool, or `null` when absent or not a keyword. **/
	public function getBool(key:String):Null<Bool>
	{
		var map = fields();
		return map == null ? null : map.getBool(key);
	}

	/** Field read as a nested mapping, or `null`. **/
	public function getMap(key:String):YamlMap
	{
		var map = fields();
		return map == null ? null : map.getMap(key);
	}

	/** Field read as a nested sequence, or `null`. **/
	public function getSeq(key:String):YamlSeq
	{
		var map = fields();
		return map == null ? null : map.getSeq(key);
	}

	/**
		Field read as a reference, or `null` when the field is absent.

		A field written as `{fileID: 0}` yields a reference whose [isNone] is true,
		which is different from the field not existing at all.
	**/
	public function getReference(key:String):hxunity.unity.UnityReference
	{
		return hxunity.unity.UnityReference.fromNode(get(key));
	}

	/** Removes a field and returns its value, or `null`. **/
	public function removeField(key:String):YamlNode
	{
		var map = fields();
		return map == null ? null : map.remove(key);
	}

	/** True when the object has any field with [key]. **/
	public function hasField(key:String):Bool
	{
		var map = fields();
		return map != null && map.has(key);
	}

	/** `m_ObjectHideFlags`, Unity's serialisation visibility flags. **/
	public function objectHideFlags():Null<Int>
	{
		return getInt("m_ObjectHideFlags");
	}

	/** Resolves a field that holds a local reference to a document. **/
	public function resolve(key:String):UnityYamlDocument
	{
		var reference = getReference(key);
		if (reference == null || reference.isExternal()) return null;
		return prefab.documents.byIdText(reference.fileIdText());
	}

	public function toString():String
	{
		return className() + "(" + hxunity.unity.FileId.toStr(fileId()) + ")";
	}
}
