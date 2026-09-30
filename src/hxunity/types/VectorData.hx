package hxunity.types;

import hxunity.yaml.ScalarKind;
import hxunity.yaml.Scalars;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;

/**
	A Unity `Vector2`, `Vector3` or `Vector4` as serialised in a prefab.

	Unity writes these as a flow mapping with named components:

	```yaml
	m_LocalPosition: {x: 0, y: -1.932, z: 0}
	physicsPositionInheritanceFactor: {x: 1, y: 1}
	m_Pivot: {x: 0.5, y: 0.5, z: 0}
	```

	`z` and `w` are optional, which is what lets one class cover all three
	types without guessing the widths wrong.
**/
class VectorData
{
	public var x:Float;
	public var y:Float;
	public var z:Null<Float>;
	public var w:Null<Float>;

	/**
		True when the source mapping had a `z` key.

		Kept so a Vector2 round trips as a Vector2: Unity's own `Vector2` field
		writes `{x: 1, y: 1}` and adding `z: 0` would change the field's shape.
	**/
	public var hasZ(default, null):Bool;

	/** True when the source mapping had a `w` key. **/
	public var hasW(default, null):Bool;

	public function new(x:Float = 0, y:Float = 0, z:Null<Float> = null, w:Null<Float> = null)
	{
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
		this.hasZ = z != null;
		this.hasW = w != null;
	}

	/** Reads a vector from a `{x: .., y: ..}` mapping, or `null`. **/
	public static function fromNode(node:YamlNode):VectorData
	{
		if (node == null || !Std.isOfType(node, YamlMap)) return null;
		var map:YamlMap = cast node;
		var zScalar = map.get("z");
		var wScalar = map.get("w");
		var value = new VectorData(component(map, "x", 0), component(map, "y", 0), zScalar == null ? null : component(map, "z", 0),
			wScalar == null ? null : component(map, "w", 0));
		value.hasZ = zScalar != null;
		value.hasW = wScalar != null;
		return value;
	}

	/**
		Reads a vector from a field of a component.

		Returns `null` when the field is absent, which lets callers distinguish
		"no position field" from "position is the origin".
	**/
	public static function fromField(fields:YamlMap, key:String):VectorData
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

	/** Writes the vector as the flow mapping Unity expects. **/
	public function toNode():YamlMap
	{
		var map = new YamlMap(null, true);
		map.set("x", scalar(x));
		map.set("y", scalar(y));
		if (hasZ || z != null) map.set("z", scalar(z == null ? 0 : z));
		if (hasW || w != null) map.set("w", scalar(w == null ? 0 : w));
		return map;
	}

	/** Writes the vector into [fields] under [key], keeping field order. **/
	public function writeTo(fields:YamlMap, key:String):Void
	{
		fields.set(key, toNode());
	}

	static function scalar(value:Float):YamlScalar
	{
		return new YamlScalar(Numbers.format(value), ScalarKind.Plain);
	}

	public function clone():VectorData
	{
		var copy = new VectorData(x, y, z, w);
		copy.hasZ = hasZ;
		copy.hasW = hasW;
		return copy;
	}

	public function toString():String
	{
		if (hasW) return '($x, $y, $z, $w)';
		if (hasZ) return '($x, $y, $z)';
		return '($x, $y)';
	}
}
