package hxunity.unity;

import haxe.Int64;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;

/**
	A serialised reference to a Unity object, the shape Unity writes as

	```yaml
	m_Script: {fileID: 11500000, guid: d247ba06193faa74d9335f5481b2b56c, type: 3}
	m_Father: {fileID: 0}
	```

	Three fields matter and each means something different:

	* `fileID` identifies the object. The value is only meaningful together with
	  a guid: without one it is an id **inside this file**; with one it names an
	  object inside another asset, except for the small set of built-in
	  resources that use a negative or fixed id together with the all-zero guid.
	* `guid` is the asset GUID from the target's `.meta` file, or absent for a
	  local reference.
	* `type` says where the object lives, and is *not* the class id from a
	  document header. `type: 0` is an engine built-in, `type: 2` a native asset
	  Unity serialises itself (`.mat`, `.asset`, `.controller`, `.anim`) and
	  `type: 3` everything else in the project — imported assets such as textures,
	  shaders and scripts, plus prefabs and the objects inside them.

	  The split and the counts behind it are in [AssetReference], which is where
	  the `{fileID, type}` pair for each asset type is maintained. Prefer its
	  typed constructors ([texture], [material], [prefab], [sprite]) over
	  [asset]: a hand written file id is the most common way a generated asset
	  ends up silently pointing at nothing.
**/
class UnityReference
{
	/** How a reference resolves, which is what `type:` records. **/
	public static inline var TYPE_LOCAL = -1;

	/** `type: 0` — a resource built into the Unity editor or engine. **/
	public static inline var TYPE_BUILTIN = 0;

	/**
		`type: 2` — an object inside a native asset: a `.mat`, `.asset`,
		`.controller` or `.anim`, i.e. a file Unity serialises itself.

		Kept under its original name for callers that predate [TYPE_NATIVE].
	**/
	public static inline var TYPE_ASSET = 2;

	/**
		`type: 3` — an object inside an imported asset or a prefab: a texture,
		shader, script, model, audio clip, or anything inside a `.prefab`.

		Kept under its original name for callers that predate [TYPE_IMPORTED].
	**/
	public static inline var TYPE_PROJECT = 3;

	/** `type: 2`, the clearer name for [TYPE_ASSET]. **/
	public static inline var TYPE_NATIVE = TYPE_ASSET;

	/** `type: 3`, the clearer name for [TYPE_PROJECT]. **/
	public static inline var TYPE_IMPORTED = TYPE_PROJECT;

	/** `fileID` value, or `null` when the map carried none. **/
	public var fileId(default, null):Int64;

	/** Asset GUID, or `null` when the reference is local. **/
	public var guid(default, null):String;

	/** `type:` value, or [TYPE_LOCAL] when the map carried none. **/
	public var type(default, null):Int;

	var fileIdTextMemo:String;

	public function new(fileId:Int64, guid:String, type:Int, ?fileIdText:String)
	{
		this.fileId = fileId;
		this.guid = guid;
		this.type = type;
		this.fileIdTextMemo = fileIdText;
	}

	/**
		The file id as decimal text, memoised.

		[fromNode] captures the text exactly as the YAML wrote it, so a reference
		parsed from a file never needs `Int64.toStr` at all — document lookups key
		on this, which keeps Haxe's software `divMod` (the top CPU cost on the
		JavaScript target) out of hierarchy traversal.
	**/
	public function fileIdText():String
	{
		if (fileIdTextMemo == null) fileIdTextMemo = FileId.toStr(fileId);
		return fileIdTextMemo;
	}

	/** True when the reference resolves inside the same file. **/
	public function isLocal():Bool
	{
		return guid == null;
	}

	/** True when the reference resolves inside another asset. **/
	public function isExternal():Bool
	{
		return guid != null;
	}

	/** True when this is `{fileID: 0}`, i.e. nothing. **/
	public function isNone():Bool
	{
		return isLocal() && FileId.isNone(fileId);
	}

	/**
		Reads a reference from a mapping such as `{fileID: 0, guid: ..., type: 3}`.

		Returns `null` when [node] is not a mapping, so callers can distinguish
		"no reference field" from "a reference to nothing".
	**/
	public static function fromNode(node:YamlNode):UnityReference
	{
		if (node == null || !Std.isOfType(node, YamlMap)) return null;
		var map:YamlMap = cast node;
		var fileText = map.getString("fileID");
		var guid = map.getString("guid");
		var typeText = map.getString("type");
		var id:Int64 = null;
		if (fileText != null)
		{
			id = FileId.parse(fileText);
			if (id == null) throw 'fileID "$fileText" is not an integer (line ${node.line})';
		}
		var type = TYPE_LOCAL;
		if (typeText != null)
		{
			var parsed = Scalars.tryInt(typeText);
			if (parsed == null) throw 'reference type "$typeText" is not an integer (line ${node.line})';
			type = parsed;
		}
		return new UnityReference(id, guid, type, fileText);
	}

	/**
		Builds the flow mapping Unity writes for this reference.

		The field order is `fileID`, `guid`, `type`, which is the order Unity
		itself uses, so a written file looks hand-authored by the editor.
	**/
	public function toNode():YamlMap
	{
		var map = new YamlMap(null, true);
		map.set("fileID", new YamlScalar(FileId.toStr(fileId), hxunity.yaml.ScalarKind.Plain));
		if (guid != null)
		{
			map.set("guid", new YamlScalar(guid, hxunity.yaml.ScalarKind.Plain));
			map.set("type", new YamlScalar(Std.string(isLocal() ? TYPE_PROJECT : type), hxunity.yaml.ScalarKind.Plain));
		}
		return map;
	}

	/** A reference to another object inside the same file. **/
	public static function local(fileId:Int64):UnityReference
	{
		return new UnityReference(fileId, null, TYPE_LOCAL);
	}

	/** A reference to an object inside the asset identified by [guid]. **/
	public static function asset(guid:String, fileId:Int64, type:Int):UnityReference
	{
		return new UnityReference(fileId, guid, type);
	}

	/** `{fileID: 0}`, i.e. an empty reference. **/
	public static function none():UnityReference
	{
		return new UnityReference(FileId.zeroId(), null, TYPE_LOCAL);
	}

	// ------------------------------------------------- typed asset references
	//
	// One per asset type the library can name a main object for. Each writes the
	// file id and `type:` Unity writes, so a caller never spells either out; the
	// numbers and the evidence for them are in [AssetReference].

	/** A texture: `{fileID: 2800000, guid, type: 3}`. **/
	public static function texture(guid:String, ?fileId:Int64):UnityReference
	{
		return hxunity.unity.AssetReference.of(guid, "png", fileId);
	}

	/** A material: `{fileID: 2100000, guid, type: 2}`. **/
	public static function material(guid:String, ?fileId:Int64):UnityReference
	{
		return hxunity.unity.AssetReference.of(guid, "mat", fileId);
	}

	/** A prefab: `{fileID: 100100000, guid, type: 3}`. **/
	public static function prefab(guid:String, ?fileId:Int64):UnityReference
	{
		return hxunity.unity.AssetReference.of(guid, "prefab", fileId);
	}

	/**
		A sprite, either the texture's first sprite or a named sub sprite.

		[fileId] names the sprite inside the texture: Unity numbers them from
		21300000 in steps of two, so a caller that has read an `spriteID` out of
		the texture's `.meta` passes it here.
	**/
	public static function sprite(guid:String, ?fileId:Int64):UnityReference
	{
		var id = fileId == null ? Int64.ofInt(AssetReference.SPRITE_ID) : fileId;
		return new UnityReference(id, AssetGuid.normalise(guid), TYPE_IMPORTED);
	}

	/** A `MonoScript`: `{fileID: 11500000, guid, type: 3}`. **/
	public static function script(guid:String):UnityReference
	{
		return hxunity.unity.AssetReference.of(guid, "cs");
	}

	/** A shader: `{fileID: 4800000, guid, type: 3}`. **/
	public static function shader(guid:String):UnityReference
	{
		return hxunity.unity.AssetReference.of(guid, "shader");
	}

	/**
		A Unity built-in resource: `{fileID: <id>, guid: 0000000000000000f000000000000000,
		type: 0}`.

		[guid] defaults to the built-in resources GUID, which is the one used by
		shaders, materials and textures that ship with the editor.
	**/
	public static function builtin(fileId:Int64, ?guid:String):UnityReference
	{
		return new UnityReference(fileId, guid == null ? BUILTIN_RESOURCES_GUID : AssetGuid.normalise(guid), TYPE_BUILTIN);
	}

	/** GUID of Unity's built-in resources, used by [builtin] when none is given. **/
	public static inline var BUILTIN_RESOURCES_GUID = "0000000000000000f000000000000000";

	/**
		True when two references point at the same object.

		A `type:` mismatch is ignored: Unity sometimes writes `type: 3` and
		sometimes omits it for the same target, and both resolve identically.
	**/
	public function equals(other:UnityReference):Bool
	{
		if (other == null) return false;
		if (guid != other.guid) return false;
		return FileId.compare(fileId, other.fileId) == 0;
	}

	public function toString():String
	{
		var id = FileId.toStr(fileId);
		if (guid == null) return '{fileID: $id}';
		return '{fileID: $id, guid: $guid, type: $type}';
	}
}
