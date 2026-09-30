package hxunity.yaml;

import haxe.Int64;

/**
	One `--- !u!<classId> &<fileId>` document of a Unity YAML file.

	A `.prefab`, `.asset`, `.unity` or `.mat` file is a stream of these, one per
	serialised object. [body] is the parsed mapping keyed by the Unity class name
	(`GameObject:`, `Transform:`, `MonoBehaviour:`, ...), which is how the class
	name is recovered even for ids this library does not know.

	The document is also a [YamlNode], so it can be handed to [YamlWriter] and
	walked with the same accessors as any other mapping.
**/
class UnityYamlDocument extends YamlNode
{
	/** Unity class id from the `!u!` tag, or 0 for a document without one. **/
	public var classId(default, null):Int;

	/** Anchor of the header, the object's file id. **/
	public var fileId(default, null):Int64;

	/** True when the header was `--- !u!114 &1 stripped`. **/
	public var stripped(default, null):Bool;

	/** True when the header carried an anchor at all. **/
	public var hasFileId(default, null):Bool;

	/** Parsed body: normally a [YamlMap] with a single class-name key. **/
	public var body(default, null):YamlNode;

	/** 1 based line of the `---` header. **/
	public var documentLine(default, null):Int;

	/**
		True when the document was introduced by a `---` marker.

		A `.meta` file, or a hand written fixture, has no header: it is a bare
		mapping at the top level. Writing one back must not invent a header, so the
		flag is recorded rather than guessed from [classId].
	**/
	public var hasHeader(default, null):Bool;

	/** Class name reported by the body, e.g. `MonoBehaviour`, or `null`. **/
	public var bodyName(default, null):String;

	public function new(classId:Int, fileId:Int64, stripped:Bool, body:YamlNode, documentLine:Int = 0, hasFileId:Bool = true,
			hasHeader:Bool = true)
	{
		super(documentLine, 0);
		this.classId = classId;
		this.fileId = fileId;
		this.stripped = stripped;
		this.body = body;
		this.documentLine = documentLine;
		this.hasFileId = hasFileId;
		this.hasHeader = hasHeader;
		this.bodyName = detectBodyName(body);
	}

	static function detectBodyName(body:YamlNode):String
	{
		if (body == null || !Std.isOfType(body, YamlMap)) return null;
		var map:YamlMap = cast body;
		if (map.entries.length == 0) return null;
		// Unity writes exactly one class-name key, so take the first key that is a
		// name this library knows. Checking the name against the table rather than
		// just its first letter keeps a `.meta` file correct: its body is a real
		// mapping whose `PrefabImporter:` key is capitalised but is not a class, and
		// treating it as one would report a `PrefabImporter` document instead of
		// the class id 0 a headerless file actually has.
		for (entry in map.entries)
		{
			if (entry.key.length > 0 && entry.key.charAt(0) == entry.key.charAt(0).toUpperCase() && ClassIds.id(entry.key) >= 0)
			{
				return entry.key;
			}
		}
		return null;
	}

	/** Unity class name, falling back to the body key for unknown ids. **/
	public function className():String
	{
		if (bodyName != null) return bodyName;
		return classNameOf(classId);
	}

	/** True when this document is a `GameObject` (class id 1). **/
	public inline function isGameObject():Bool
	{
		return classId == ClassIds.GameObject;
	}

	/** True when this document is a `Transform` or `RectTransform`. **/
	public inline function isTransform():Bool
	{
		return classId == ClassIds.Transform || classId == ClassIds.RectTransform;
	}

	/** True when this document is a `PrefabInstance` (class id 1001). **/
	public inline function isPrefabInstance():Bool
	{
		return classId == ClassIds.PrefabInstance;
	}

	/** True when the body is a [YamlMap], i.e. it has serialised fields. **/
	public inline function hasFields():Bool
	{
		return Std.isOfType(body, YamlMap);
	}

	/** Body as a mapping, throwing when it is not one. **/
	public function fields():YamlMap
	{
		return body.asMap();
	}

	/** Value of [key] in the body mapping, or `null`. **/
	public function get(key:String):YamlNode
	{
		var map = bodyMap();
		return map == null ? null : map.get(key);
	}

	/** Stores [value] under [key] in the body mapping, or throws. **/
	public function set(key:String, value:YamlNode):YamlNode
	{
		return body.asMap().set(key, value);
	}

	/** Scalar text of [key] in the body mapping, or `null`. **/
	public function getString(key:String):String
	{
		var map = bodyMap();
		return map == null ? null : map.getString(key);
	}

	/** Scalar of [key] read as an int, or `null`. **/
	public function getInt(key:String):Null<Int>
	{
		var map = bodyMap();
		return map == null ? null : map.getInt(key);
	}

	/** Scalar of [key] read as a float, or `null`. **/
	public function getFloat(key:String):Null<Float>
	{
		var map = bodyMap();
		return map == null ? null : map.getFloat(key);
	}

	/** Scalar of [key] read as a bool, or `null`. **/
	public function getBool(key:String):Null<Bool>
	{
		var map = bodyMap();
		return map == null ? null : map.getBool(key);
	}

	/** Nested mapping of [key], or `null`. **/
	public function getMap(key:String):YamlMap
	{
		var map = bodyMap();
		return map == null ? null : map.getMap(key);
	}

	/** Nested sequence of [key], or `null`. **/
	public function getSeq(key:String):YamlSeq
	{
		var map = bodyMap();
		return map == null ? null : map.getSeq(key);
	}

	function bodyMap():YamlMap
	{
		return Std.isOfType(body, YamlMap) ? cast body : null;
	}

	override public function toString():String
	{
		return 'UnityYamlDocument(!u!$classId &${Int64.toStr(fileId)}${stripped ? " stripped" : ""} ${className()})';
	}

	override public function typeName():String
	{
		return "unity document";
	}

	override public function deepEquals(other:YamlNode):Bool
	{
		if (!Std.isOfType(other, UnityYamlDocument)) return false;
		var o:UnityYamlDocument = cast other;
		return o.classId == classId && Int64.compare(o.fileId, fileId) == 0 && o.stripped == stripped
			&& o.body.deepEquals(body);
	}

	/** Unity `!u!` class ids used by this library. **/
	public static function classNameOf(classId:Int):String
	{
		var name = ClassIds.names.get(classId);
		return name == null ? 'Class$classId' : name;
	}
}
