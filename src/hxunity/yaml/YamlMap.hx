package hxunity.yaml;

import haxe.Int64;

/**
	A YAML mapping that preserves entry order.

	Entries are an array rather than a hash map on purpose: a prefab that is read
	and written back must keep Unity's field order, and Haxe's [Map] types do not
	promise one.
**/
class YamlMap extends YamlNode
{
	/** Ordered key/value entries. **/
	public var entries(default, null):Array<YamlEntry>;

	/** True when the source wrote the mapping in flow style, `{a: 1}`. **/
	public var flow(default, null):Bool;

	public function new(entries:Array<YamlEntry> = null, flow:Bool = false, line:Int = 0, column:Int = -1)
	{
		super(line, column);
		this.entries = entries == null ? [] : entries;
		this.flow = flow;
	}

	override public function isCollection():Bool
	{
		return true;
	}

	override public function deepClone():YamlNode
	{
		var out = new YamlMap(null, flow, line, column);
		for (entry in entries)
		{
			out.entries.push(new YamlEntry(entry.key, entry.value == null ? null : entry.value.deepClone(), entry.line));
		}
		return out;
	}

	override public function asMap():YamlMap
	{
		return this;
	}

	/** Throws: a mapping is not a sequence, and a positioned error says where. **/
	override public function asSeq():YamlSeq
	{
		throw new YamlError("expected a sequence but found a mapping", line, column);
	}

	/** Throws: a mapping is not a scalar, and a positioned error says where. **/
	override public function asScalar():YamlScalar
	{
		throw new YamlError("expected a scalar but found a mapping", line, column);
	}

	override public function typeName():String
	{
		return flow ? "flow mapping" : "mapping";
	}

	/** Number of entries. **/
	public function size():Int
	{
		return entries.length;
	}

	/** True when the mapping has no entries. **/
	public function isEmpty():Bool
	{
		return entries.length == 0;
	}

	/** Index of [key] in [entries], or -1 when absent. **/
	public function indexOf(key:String):Int
	{
		for (i in 0...entries.length)
		{
			if (entries[i].key == key) return i;
		}
		return -1;
	}

	/** True when [key] is present. **/
	public function has(key:String):Bool
	{
		return indexOf(key) >= 0;
	}

	/** Value stored under [key], or `null` when absent. **/
	public function get(key:String):YamlNode
	{
		var i = indexOf(key);
		return i < 0 ? null : entries[i].value;
	}

	/** Entry stored under [key], or `null` when absent. **/
	public function getEntry(key:String):YamlEntry
	{
		var i = indexOf(key);
		return i < 0 ? null : entries[i];
	}

	/**
		Stores [value] under [key], replacing the existing entry in place so the
		field order Unity wrote is preserved.
	**/
	public function set(key:String, value:YamlNode):YamlNode
	{
		var i = indexOf(key);
		if (i >= 0)
		{
			entries[i].value = value;
			return value;
		}
		entries.push(new YamlEntry(key, value));
		return value;
	}

	/** Replaces the node stored under [key] without touching its position. **/
	public function setRaw(key:String, raw:String):YamlNode
	{
		var existing = get(key);
		if (existing != null && Std.isOfType(existing, YamlScalar))
		{
			(cast existing : YamlScalar).setRaw(raw);
			return existing;
		}
		return set(key, new YamlScalar(raw, Plain));
	}

	/** Appends an entry without checking for duplicates. **/
	public function add(key:String, value:YamlNode):YamlNode
	{
		entries.push(new YamlEntry(key, value));
		return value;
	}

	/** Removes [key] and returns its value, or `null` when absent. **/
	public function remove(key:String):YamlNode
	{
		var i = indexOf(key);
		if (i < 0) return null;
		return entries.splice(i, 1)[0].value;
	}

	/** Scalar value stored under [key], or `null` when absent or a collection. **/
	public function getString(key:String):String
	{
		var n = get(key);
		return (n == null || n.isCollection()) ? null : n.toString();
	}

	/** Scalar under [key] read as a 64 bit integer, or `null`. **/
	public function getInt64(key:String):Int64
	{
		var s = getString(key);
		return s == null ? null : Scalars.tryInt64(s);
	}

	/** Scalar under [key] read as an int, or `null` when absent or out of range. **/
	public function getInt(key:String):Null<Int>
	{
		var s = getString(key);
		return s == null ? null : Scalars.tryInt(s);
	}

	/** Scalar under [key] read as a float, or `null` when not numeric. **/
	public function getFloat(key:String):Null<Float>
	{
		var s = getString(key);
		return s == null ? null : Scalars.tryFloat(s);
	}

	/** Scalar under [key] read as a bool, or `null` when not a keyword. **/
	public function getBool(key:String):Null<Bool>
	{
		var s = getString(key);
		return s == null ? null : Scalars.tryBool(s);
	}

	/** Mapping stored under [key], or `null` when absent or not a mapping. **/
	public function getMap(key:String):YamlMap
	{
		var n = get(key);
		return (n != null && Std.isOfType(n, YamlMap)) ? cast n : null;
	}

	/** Sequence stored under [key], or `null` when absent or not a sequence. **/
	public function getSeq(key:String):YamlSeq
	{
		var n = get(key);
		return (n != null && Std.isOfType(n, YamlSeq)) ? cast n : null;
	}

	/** Builds a mapping from plain key/value pairs, values go through [Scalars.node]. **/
	public static function of(pairs:Array<{key:String, value:Dynamic}>):YamlMap
	{
		var map = new YamlMap();
		for (pair in pairs)
		{
			map.set(pair.key, Scalars.node(pair.value));
		}
		return map;
	}

	override public function deepEquals(other:YamlNode):Bool
	{
		if (!Std.isOfType(other, YamlMap)) return false;
		var o:YamlMap = cast other;
		if (o.entries.length != entries.length) return false;
		for (i in 0...entries.length)
		{
			if (o.entries[i].key != entries[i].key) return false;
			if (!o.entries[i].value.deepEquals(entries[i].value)) return false;
		}
		return true;
	}

	override public function toHaxe():Dynamic
	{
		var out = new Map<String, Dynamic>();
		for (entry in entries)
		{
			out.set(entry.key, entry.value.toHaxe());
		}
		return out;
	}

	override function writeJson(sb:StringBuf, indent:Int):Void
	{
		if (entries.length == 0)
		{
			sb.add("{}");
			return;
		}
		var pad = Strings.spaces(indent + 2);
		sb.add("{\n");
		for (i in 0...entries.length)
		{
			sb.add(pad);
			YamlWriter.writeJsonString(sb, entries[i].key);
			sb.add(": ");
			entries[i].value.writeJson(sb, indent + 2);
			if (i < entries.length - 1) sb.add(",");
			sb.add("\n");
		}
		sb.add(Strings.spaces(indent));
		sb.add("}");
	}
}
