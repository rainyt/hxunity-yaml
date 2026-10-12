package hxunity.prefab;

import haxe.Int64;
import hxunity.yaml.ClassIds;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlScalar;
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

	// ------------------------------------------------------------ typed writes
	//
	// The write side of the accessors above. Every value goes through the same
	// facilities the reader uses — [Scalars.ofString] for text, [Numbers.format]
	// for floats, a flow [YamlMap] for a reference — so a field written here is
	// spelled the way Unity spells it, and the writer has nothing left to decide.

	/** Stores an integer field. **/
	public function setInt(key:String, value:Int):YamlNode
	{
		return set(key, plainNode(Std.string(value)));
	}

	/** Stores a float field, formatted the way Unity writes floats. **/
	public function setFloat(key:String, value:Float):YamlNode
	{
		return set(key, plainNode(hxunity.types.Numbers.format(value)));
	}

	/** Stores a boolean field as the `1` / `0` Unity writes for one. **/
	public function setBool(key:String, value:Bool):YamlNode
	{
		return set(key, plainNode(value ? "1" : "0"));
	}

	/**
		Stores a text field, quoted when a bare value would not read back the same.

		`ofString` decides that, so a name containing `: ` or starting with `#`
		gets the quotes it needs without the caller thinking about it.
	**/
	public function setString(key:String, value:String):YamlNode
	{
		return set(key, Scalars.ofString(value));
	}

	/** Stores a reference, written as `{fileID: ..., guid: ..., type: ...}`. **/
	public function setReference(key:String, value:UnityReference):YamlNode
	{
		if (value == null) return set(key, UnityReference.none().toNode());
		return set(key, value.toNode());
	}

	/**
		Stores a reference to another asset, by GUID.

		A `null` [fileId] writes `{fileID: 0}` next to the GUID, which is a
		reference Unity cannot resolve; pass the id the target's object actually
		has. [hxunity.unity.AssetReference.mainObjectIdOf] and the typed
		constructors on [UnityReference] are what know those numbers, so this is
		the low level form — `setReference(key, UnityReference.material(guid))` is
		almost always what a caller wants, since it fills both fields in.
	**/
	public function setGuidReference(key:String, guid:String, ?fileId:Int64, ?type:Int):YamlNode
	{
		var id = fileId == null ? hxunity.unity.FileId.zeroId() : fileId;
		var kind = type == null ? UnityReference.TYPE_IMPORTED : type;
		return set(key, new UnityReference(id, guid, kind).toNode());
	}

	/** Stores a reference to another object in this same file. **/
	public function setLocalReference(key:String, fileId:Int64):YamlNode
	{
		return set(key, UnityReference.local(fileId).toNode());
	}

	/** Stores a `Vector2`, `Vector3` or `Vector4` as a flow mapping. **/
	public function setVector(key:String, value:hxunity.types.VectorData):YamlNode
	{
		if (value == null) return set(key, plainNode(""));
		return set(key, value.toNode());
	}

	/** Stores a colour as `{r: .., g: .., b: .., a: ..}`. **/
	public function setColor(key:String, value:hxunity.types.ColorData):YamlNode
	{
		if (value == null) return set(key, plainNode(""));
		return set(key, value.toNode());
	}

	/** Stores a rotation as `{x: .., y: .., z: .., w: ..}`. **/
	public function setQuaternion(key:String, value:hxunity.types.QuaternionData):YamlNode
	{
		if (value == null) return set(key, plainNode(""));
		return set(key, value.toNode());
	}

	/** Replaces a sequence field with [values], creating it when absent. **/
	public function setSeq(key:String, values:Array<YamlNode>):YamlSeq
	{
		var seq = new YamlSeq();
		if (values != null)
		{
			for (value in values)
			{
				if (value != null) seq.push(value);
			}
		}
		set(key, seq);
		return seq;
	}

	/**
		Appends [value] to the sequence under [key], creating the sequence when the
		field is absent or is not one.

		This is how a list Unity keeps growing is written: `m_Materials`,
		`m_Children`, `m_Component`.
	**/
	public function addToSeq(key:String, value:YamlNode):YamlNode
	{
		var seq = getSeq(key);
		if (seq == null)
		{
			seq = new YamlSeq();
			set(key, seq);
		}
		return seq.push(value);
	}

	/** Appends a reference to the sequence under [key]. **/
	public function addReferenceToSeq(key:String, value:UnityReference):YamlNode
	{
		return addToSeq(key, value == null ? UnityReference.none().toNode() : value.toNode());
	}

	/**
		Stores a flow mapping built from plain values.

		For the inline mappings Unity writes on one line, such as
		`m_StaticBatchInfo: {firstSubMesh: 0, subMeshCount: 0}` or a
		`m_TexEnvs` entry's `m_Scale`. Values go through [Scalars.node], so an
		[Int], [Float], [Bool] or [String] is written as the matching scalar.
	**/
	public function setFlowMap(key:String, pairs:Array<{key:String, value:Dynamic}>):YamlMap
	{
		var map = new YamlMap(null, true);
		if (pairs != null)
		{
			for (pair in pairs)
			{
				map.set(pair.key, Scalars.node(pair.value));
			}
		}
		set(key, map);
		return map;
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

	/** A plain scalar node, for a value already spelled the way Unity spells it. **/
	static function plainNode(text:String):YamlScalar
	{
		return new YamlScalar(text, ScalarKind.Plain);
	}

	public function toString():String
	{
		return className() + "(" + hxunity.unity.FileId.toStr(fileId()) + ")";
	}
}
