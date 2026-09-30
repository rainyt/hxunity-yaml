package hxunity.types;

import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;

/**
	A Unity `Quaternion`, serialised as `{x: 0, y: 0, z: 0, w: 1}`.

	Field order matters for a readable diff against Unity's own output, and Unity
	writes `x, y, z, w`.
**/
class QuaternionData
{
	public var x:Float;
	public var y:Float;
	public var z:Float;
	public var w:Float;

	public function new(x:Float = 0, y:Float = 0, z:Float = 0, w:Float = 1)
	{
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}

	/** Reads a quaternion from a mapping, or `null`. **/
	public static function fromNode(node:YamlNode):QuaternionData
	{
		if (node == null || !Std.isOfType(node, YamlMap)) return null;
		var map:YamlMap = cast node;
		return new QuaternionData(component(map, "x", 0), component(map, "y", 0), component(map, "z", 0), component(map, "w", 1));
	}

	/** Reads a quaternion from a component field, or `null`. **/
	public static function fromField(fields:YamlMap, key:String):QuaternionData
	{
		return fields == null ? null : fromNode(fields.get(key));
	}

	static function component(map:YamlMap, key:String, fallback:Float):Float
	{
		var text = map.getString(key);
		if (text == null) return fallback;
		var value = Scalars.tryFloat(text);
		return value == null ? fallback : value;
	}

	/** Writes the flow mapping Unity expects, in `x, y, z, w` order. **/
	public function toNode():YamlMap
	{
		var map = new YamlMap(null, true);
		map.set("x", scalar(x));
		map.set("y", scalar(y));
		map.set("z", scalar(z));
		map.set("w", scalar(w));
		return map;
	}

	public function toString():String
	{
		return '($x, $y, $z, $w)';
	}

	static function scalar(value:Float):YamlScalar
	{
		return new YamlScalar(Numbers.format(value), ScalarKind.Plain);
	}
}
